[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()][string]$RepoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path,
    [Parameter()][string]$ModuleSearchPattern = '*.psd1',
    [Parameter()][switch]$RunTests,
    [Parameter()][switch]$CodeCoverage,
    [Parameter()][string[]]$CoveragePaths,
    [Parameter()][string]$CoverageOutputDir = $null,
    [Parameter()][string]$Version,
    [Parameter()][switch]$Publish,
    [Parameter()][string]$FeedName,
    [Parameter()][string]$FeedUrl,
    [Parameter()][string]$PesterPath = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Find-Modules {
    param([string]$Root, [string]$Pattern)
    Get-ChildItem -Path $Root -Recurse -Filter $Pattern -File |
        Where-Object { $_.Name -notlike '*Tests.psd1' } |
        ForEach-Object {
            $content = Get-Content -Path $_.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -match 'RootModule\s*=') {
                [pscustomobject]@{
                    ManifestPath = $_.FullName
                    ModuleDir    = Split-Path -Path $_.FullName -Parent
                    RelativePath = Resolve-Path -Path $_.FullName | ForEach-Object { $_.Path.Replace((Resolve-Path $Root).Path, '').TrimStart('\','/') }
                    NameNoExt    = [IO.Path]::GetFileNameWithoutExtension($_.FullName)
                }
            }
        }
}

function Invoke-ModuleBuild {
    param([pscustomobject]$Module, [string]$Root, [string]$Version)
    $moduleRel = $Module.RelativePath.TrimStart('\','/')
    $moduleNameParam = ($moduleRel -replace '/', '\').TrimEnd('.psd1')
    $buildScript = Join-Path -Path $Module.ModuleDir -ChildPath 'build\build.ps1'
    if (Test-Path $buildScript) {
        Write-Host "Building via: $buildScript for $moduleNameParam"
        $env:BUILDVER = if ($Version) { $Version } else { $env:BUILDVER }
        & $buildScript -ModuleName $moduleNameParam -WorkingDirectory $Root -Confirm:$false
    } else {
        Write-Host "No module-specific build script found for $($Module.ManifestPath). Skipping build step."
    }
}

function Invoke-ModulePublish {
    param([pscustomobject]$Module, [string]$FeedName, [string]$FeedUrl)
    $repoName = if ($FeedName) { $FeedName } else { 'AzureArtifacts' }
    if (-not $FeedUrl) {
        $orgUrl = $env:SYSTEM_COLLECTIONURI.TrimEnd('/')  # e.g. https://dev.azure.com/org/
        $project = $env:SYSTEM_TEAMPROJECT
        if (-not $orgUrl -or -not $project) { throw 'SYSTEM_COLLECTIONURI/SYSTEM_TEAMPROJECT not set. Provide -FeedUrl explicitly.' }
        if (-not $FeedName) { throw 'FeedName not provided. Set -FeedName or FEED_NAME build variable.' }
        $FeedUrl = "$orgUrl$project/_packaging/$FeedName/nuget/v2"
    }

    $pat = $env:SYSTEM_ACCESSTOKEN
    if (-not $pat) { throw 'SYSTEM_ACCESSTOKEN not available. Enable "Allow scripts to access OAuth token" and pass System.AccessToken to the step env.' }
    $sec = ConvertTo-SecureString $pat -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential ('azdo', $sec)

    if (-not (Get-PSRepository -Name $repoName -ErrorAction SilentlyContinue)) {
        Register-PSRepository -Name $repoName -SourceLocation $FeedUrl -PublishLocation $FeedUrl -InstallationPolicy Trusted -Credential $cred
    }

    Write-Host "Publishing module from $($Module.ModuleDir) to feed '$repoName' ($FeedUrl)"
    Publish-Module -Path $Module.ModuleDir -Repository $repoName -NuGetApiKey 'azdo' -ErrorAction Stop
}

# Discover modules
$modules = Find-Modules -Root $RepoRoot -Pattern $ModuleSearchPattern | Sort-Object ManifestPath
if (-not $modules) { Write-Warning 'No modules discovered.' }

# Build modules
foreach ($m in $modules) { Invoke-ModuleBuild -Module $m -Root $RepoRoot -Version $Version }

# Run tests
if ($RunTests) {
    if ($PesterPath) { $testPath = $PesterPath } else { $testPath = Join-Path $RepoRoot 'Xml\Tests' }
    if (Test-Path $testPath) {
        Write-Host "Running tests in $testPath"
        if (-not (Get-Module -ListAvailable -Name Pester)) {
            Write-Host 'Installing Pester (CurrentUser)'
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            Install-Module Pester -Scope CurrentUser -Force -MinimumVersion 5.4.0
        }
        Import-Module Pester -ErrorAction Stop
        if ($CodeCoverage) {
            # Defaults for coverage paths if none provided
            if (-not $CoveragePaths -or $CoveragePaths.Count -eq 0) {
                $CoveragePaths = @(
                    (Join-Path $RepoRoot 'Xml\Public\*.ps1'),
                    (Join-Path $RepoRoot 'Xml\Private\*.ps1'),
                    (Join-Path $RepoRoot 'build\*.ps1')
                )
            }

            # Ensure output directory
            if (-not $CoverageOutputDir) {
                $CoverageOutputDir = Join-Path $RepoRoot 'TestResults\Coverage'
            }
            New-Item -ItemType Directory -Path $CoverageOutputDir -Force | Out-Null

            Write-Host "Running tests with code coverage in $testPath"
            $cfg = New-PesterConfiguration
            $cfg.Run.Path = $testPath
            $cfg.Run.PassThru = $true
            $cfg.Run.Exit = $false
            $cfg.Output.Verbosity = 'Normal'
            $cfg.CodeCoverage.Enabled = $true
            $cfg.CodeCoverage.Path = $CoveragePaths
            # Emit JaCoCo XML to a predictable path so CI can publish it
            $cfg.CodeCoverage.OutputFormat = 'JaCoCo'
            $cfg.CodeCoverage.OutputPath = (Join-Path $CoverageOutputDir 'coverage.xml')
            $cfg.CodeCoverage.OutputEncoding = 'UTF8'

            $result = Invoke-Pester -Configuration $cfg

            # Write coverage summaries
            try {
                $summaryTxt = Join-Path $CoverageOutputDir 'summary.txt'
                $summaryJson = Join-Path $CoverageOutputDir 'pester-coverage.json'
                $percentTxt = Join-Path $CoverageOutputDir 'coveragePercent.txt'
                $indexHtml = Join-Path $CoverageOutputDir 'index.html'

                $percent = $null
                if ($result -and $result.CodeCoverage) { $percent = $result.CodeCoverage.CoveragePercent }
                if ($null -ne $percent) { Set-Content -Path $percentTxt -Value ([string]$percent) -Force }
                ($result.CodeCoverage | Out-String) | Set-Content -Path $summaryTxt -Force
                $result.CodeCoverage | ConvertTo-Json -Depth 6 | Set-Content -Path $summaryJson -Force

                # Generate a lightweight HTML report (so the Code Coverage tab can render HTML)
                $html = @(
                    '<!doctype html>'
                    '<html lang="en">'
                    '<head><meta charset="utf-8"/>'
                    '<title>Pester Coverage Report</title>'
                    '<style>body{font-family:Segoe UI,Tahoma,Arial,sans-serif;margin:20px} .kpi{font-size:48px;font-weight:600} .muted{color:#666}</style>'
                    '</head>'
                    '<body>'
                    '  <h1>Pester Coverage</h1>'
                    '  <div class="kpi">' + ($percent ?? '0') + '%</div>'
                    '  <p class="muted">Summary generated ' + (Get-Date) + '</p>'
                    '  <h2>Artifacts</h2>'
                    '  <ul>'
                    '    <li><a href="pester-coverage.json">pester-coverage.json</a></li>'
                    '    <li><a href="summary.txt">summary.txt</a></li>'
                    '    <li><a href="coveragePercent.txt">coveragePercent.txt</a></li>'
                    '  </ul>'
                    '</body></html>'
                ) -join [Environment]::NewLine
                Set-Content -Path $indexHtml -Value $html -Force -Encoding UTF8
            } catch {
                Write-Warning "Failed to write coverage artifacts: $_"
            }
        }
        else {
            Invoke-Pester -Path $testPath -CI
        }
    } else {
        Write-Warning "Test path not found: $testPath"
    }
}

# Publish modules (typically on main)
if ($Publish) {
    foreach ($m in $modules) { Invoke-ModulePublish -Module $m -FeedName $FeedName -FeedUrl $FeedUrl }
}
