[CmdletBinding()]
param(
    [Parameter(HelpMessage = 'One or more test paths to run. Defaults to Xml/Tests and build/Tests if they exist.')]
    [string[]] $Paths,

    [switch] $CI,

    [switch] $InstallPesterIfNeeded
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot

# Default test paths
if (-not $Paths -or $Paths.Count -eq 0) {
    $Paths = Get-ChildItem -Path $repoRoot -Recurse -Directory -Filter 'Tests' | ForEach-Object { $_.FullName }
    Write-Host $Paths.Count "test path(s) found."
    foreach ($p in $Paths) { Write-Host " - $p" }
}

# Resolve to absolute if needed, only keep those that exist
$resolved = foreach ($p in $Paths) {
    # if fully qualified, continue
    if (Test-Path -LiteralPath $p) { (Resolve-Path -LiteralPath $p).Path; continue }
    # else, combine with repo root
    $full = Join-Path -Path $repoRoot -ChildPath $p
    if (Test-Path -LiteralPath $full) { (Resolve-Path -LiteralPath $full).Path }
}



if (-not $resolved -or $resolved.Count -eq 0) {
    Write-Warning 'No test paths found to run.'
    return
}

# Ensure Pester is available if requested or in CI
if ($InstallPesterIfNeeded -or $CI) {
    if (-not (Get-Module -ListAvailable -Name Pester)) {
        Write-Host 'Pester not found. Installing for current user...'
        Install-Module Pester -Force -Scope CurrentUser -AllowClobber
    }
}

$invokeParams = @{ Path = $resolved }
if ($CI) { $invokeParams['CI'] = $true }

Write-Host "Running tests in:`n - " ($resolved -join "`n - ")
Invoke-Pester @invokeParams
