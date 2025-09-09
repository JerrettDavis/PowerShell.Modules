[CmdletBinding()]
param(
    [Parameter()][string]$RepoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path,
    [Parameter()][string]$ModuleSearchPattern = '*.psd1',
    [Parameter()][string]$OutputDir = (Join-Path $RepoRoot 'out\nuspec')
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
                    ModuleName   = [IO.Path]::GetFileNameWithoutExtension($_.FullName)
                }
            }
        }
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$modules = Find-Modules -Root $RepoRoot -Pattern $ModuleSearchPattern
if (-not $modules) { Write-Warning 'No modules found to generate nuspecs for.'; return }

foreach ($m in $modules) {
    $nuspecPath = Join-Path $OutputDir ("$($m.ModuleName).nuspec")

    # Try to enrich metadata from the manifest
    $author = 'Unknown'
    $description = ''
    try {
        $data = Import-PowerShellDataFile -Path $m.ManifestPath
        if ($data.Author) { $author = [string]$data.Author }
        if ($data.Description) { $description = [string]$data.Description }
    } catch { }

    $moduleDirRel = Resolve-Path -Path $m.ModuleDir | ForEach-Object { $_.Path }
    $moduleName = $m.ModuleName

    $nuspec = @(
        '<?xml version="1.0"?>'
        '<package>'
        '  <metadata>'
        "    <id>$moduleName</id>"
        '    <version>0.0.0</version>'
        "    <authors>$author</authors>"
        "    <owners>$author</owners>"
        "    <description>$([System.Security.SecurityElement]::Escape($description))</description>"
        '    <requireLicenseAcceptance>false</requireLicenseAcceptance>'
        '  </metadata>'
        '  <files>'
        # Place the entire module directory under a folder named after the module in the package root
    "    <file src=`"$moduleDirRel\**\*.*`" target=`"$moduleName`" exclude=`"**\Tests\**;**\build\**`" />"
        '  </files>'
        '</package>'
    ) -join [Environment]::NewLine

    Set-Content -Path $nuspecPath -Value $nuspec -Encoding UTF8 -Force
    Write-Host "Generated $nuspecPath"
}
