Describe 'ci-discover-and-build.ps1' {
    BeforeAll {
        $script:TestRoot = Join-Path $env:TEMP ("CiDiscoverBuild_$([guid]::NewGuid())")
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null

        # Resolve repository root relative to this test file
        $script:RepoRoot = if ($PSScriptRoot) {
            (Resolve-Path -Path (Join-Path $PSScriptRoot '..' '..')).Path
        } elseif ($MyInvocation.MyCommand.Path) {
            (Resolve-Path -Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..' '..')).Path
        } else {
            (Get-Location).Path
        }

        # Create two fake modules each with a manifest and a dummy build script that records invocation
        function New-FakeModule {
            param(
                [string]$Name
            )
            $modDir = Join-Path $script:TestRoot $Name
            New-Item -ItemType Directory -Path $modDir -Force | Out-Null

            # Manifest (copy template for realism)
            $template = Join-Path $script:RepoRoot 'Xml' 'JerrettDavis.Xml.psd1'
            $manifestPath = Join-Path $modDir ("$Name.psd1")
            Copy-Item -Path $template -Destination $manifestPath -Force

            # Dummy build script that captures env:BUILDVER and writes a marker file
            $buildDir = Join-Path $modDir 'build'
            New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
            $buildScriptPath = Join-Path $buildDir 'build.ps1'
            @'
param(
    [string]$ModuleName,
    [string]$WorkingDirectory
)
$moduleDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$marker = Join-Path $moduleDir 'built.txt'
"Built:$ModuleName;WD:$WorkingDirectory;BUILDVER:$env:BUILDVER" | Set-Content -Path $marker -Force
'@ | Set-Content -Path $buildScriptPath -Encoding UTF8 -Force

            return [pscustomobject]@{ Name = $Name; Dir = $modDir; Manifest = $manifestPath }
        }

        $script:ModuleA = New-FakeModule -Name 'ModuleA'
        $script:ModuleB = New-FakeModule -Name 'ModuleB'

    # Path to the CI script under test
    $script:CiScript = (Resolve-Path -Path (Join-Path $script:RepoRoot 'build' 'ci-discover-and-build.ps1')).Path
    }

    AfterAll {
        if (Test-Path -Path $script:TestRoot) {
            Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Discovery and build invocation' {
        It 'invokes each module build and passes the version via env:BUILDVER' {
            & $script:CiScript -RepoRoot $script:TestRoot -Version '9.8.7' | Out-Null

            $aMarker = Join-Path $script:ModuleA.Dir 'built.txt'
            $bMarker = Join-Path $script:ModuleB.Dir 'built.txt'
            (Test-Path $aMarker) | Should -BeTrue
            (Test-Path $bMarker) | Should -BeTrue

            $a = Get-Content -Path $aMarker -Raw
            $b = Get-Content -Path $bMarker -Raw
            ($a -match 'BUILDVER:9\.8\.7') | Should -BeTrue
            ($b -match 'BUILDVER:9\.8\.7') | Should -BeTrue
        }
    }

    Context 'Running tests with -RunTests' {
        It 'calls Invoke-Pester with the provided test path' {
            # Create a dummy tests folder and a trivial test file
            $testsFolder = Join-Path $script:TestRoot 'SomeTests'
            New-Item -ItemType Directory -Path $testsFolder -Force | Out-Null
            Set-Content -Path (Join-Path $testsFolder 'sample.Tests.ps1') -Value "Describe 'sample' { It 'passes' { 1 | Should -Be 1 } }" -Force

            Mock -CommandName Invoke-Pester -ParameterFilter { $Path -eq $testsFolder -and $CI } -MockWith { return } -Verifiable

            & $script:CiScript -RepoRoot $script:TestRoot -RunTests -PesterPath $testsFolder -Version '0.0.1' | Out-Null

            Assert-MockCalled Invoke-Pester -Times 1 -ParameterFilter { $Path -eq $testsFolder -and $CI }
        }
    }

    Context 'Publishing with -Publish' {
        It 'registers the PSRepository if needed and publishes each module' {
            # Ensure environment variables for constructing the feed URL
            $oldCol = $env:SYSTEM_COLLECTIONURI
            $oldProj = $env:SYSTEM_TEAMPROJECT
            $oldTok = $env:SYSTEM_ACCESSTOKEN
            $env:SYSTEM_COLLECTIONURI = 'https://dev.azure.com/org/'
            $env:SYSTEM_TEAMPROJECT = 'Project'
            $env:SYSTEM_ACCESSTOKEN = 'token'

            try {
                Mock -CommandName Get-PSRepository -MockWith { return $null }
                Mock -CommandName Register-PSRepository -ParameterFilter { $Name -eq 'TestFeed' } -MockWith { return } -Verifiable
                Mock -CommandName Publish-Module -ParameterFilter { $Repository -eq 'TestFeed' } -MockWith { return } -Verifiable

                & $script:CiScript -RepoRoot $script:TestRoot -Publish -FeedName 'TestFeed' -Version '1.0.0' | Out-Null

                Assert-MockCalled Register-PSRepository -Times 1 -ParameterFilter { $Name -eq 'TestFeed' }
                # Expect two publishes (one per module)
                Assert-MockCalled Publish-Module -Times 2 -ParameterFilter { $Repository -eq 'TestFeed' }
            }
            finally {
                $env:SYSTEM_COLLECTIONURI = $oldCol
                $env:SYSTEM_TEAMPROJECT = $oldProj
                $env:SYSTEM_ACCESSTOKEN = $oldTok
            }
        }
    }
}
