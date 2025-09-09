<#
.SYNOPSIS
    Update a module manifest's ModuleVersion and FunctionsToExport fields for a build.

.DESCRIPTION
    Reads the module manifest (.psd1) and updates the ModuleVersion token and the
    FunctionsToExport list based on *.ps1 files found in the module's Public folder.
    The script supports ShouldProcess (-WhatIf/-Confirm) and emits informative
    verbose/host messages.

.PARAMETER ModuleName
    The module name including relative path from the working directory to the
    module folder (for example: "Xml\JerrettDavis.Xml"). The manifest file is
    expected at: <WorkingDirectory>\<ModuleName>.psd1

.PARAMETER BuildVersion
    The version string to write into the manifest. If the environment variable
    BUILDVER is set and the parameter was not explicitly provided, the
    environment variable takes precedence.

.PARAMETER WorkingDirectory
    Optional base working directory. Precedence: parameter > env:SYSTEM_DEFAULTWORKINGDIRECTORY > current directory.

.EXAMPLE
    .\build.ps1 -ModuleName 'Xml\JerrettDavis.Xml' -BuildVersion '1.2.3'

.NOTES
    - The script will safely replace the placeholder '<ModuleVersion>' when present
      or fallback to replacing the ModuleVersion assignment line.
    - If no public functions are found, FunctionsToExport will be left empty (@()).
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleName,

    [Parameter(Position = 1)]
    [ValidateNotNullOrEmpty()]
    [string]$BuildVersion = '0.0.0',

    [Parameter(Position = 2)]
    [string]$WorkingDirectory = $null
)

# Contract: inputs/outputs, error modes
# - Inputs: ModuleName (path-like), BuildVersion, optional WorkingDirectory
# - Output: overwrites the target .psd1 manifest with updated ModuleVersion and FunctionsToExport
# - Errors: missing files, IO errors -> thrown as terminating errors

try {
    # Determine BuildVersion precedence: env var wins only when user did not supply the param explicitly
    if ($env:BUILDVER -and -not $PSBoundParameters.ContainsKey('BuildVersion')) {
        Write-Verbose "Using build version from environment variable: $env:BUILDVER"
        $ResolvedBuildVersion = $env:BUILDVER
    }
    else {
        Write-Verbose "Using build version from parameter: $BuildVersion"
        $ResolvedBuildVersion = $BuildVersion
    }

    # Determine working directory: parameter > env > current location
    if ($WorkingDirectory) {
        $ResolvedWorkingDirectory = $WorkingDirectory
        Write-Verbose "Using working directory from parameter: $ResolvedWorkingDirectory"
    }
    elseif ($env:SYSTEM_DEFAULTWORKINGDIRECTORY) {
        $ResolvedWorkingDirectory = $env:SYSTEM_DEFAULTWORKINGDIRECTORY
        Write-Verbose "Using working directory from environment variable: $ResolvedWorkingDirectory"
    }
    else {
        $ResolvedWorkingDirectory = (Get-Location).Path
        Write-Verbose "SYSTEM_DEFAULTWORKINGDIRECTORY not set. Using current directory: $ResolvedWorkingDirectory"
    }

    $manifestPath = Join-Path -Path $ResolvedWorkingDirectory -ChildPath "$ModuleName.psd1"
    if (-not (Test-Path -Path $manifestPath)) {
        throw "Manifest not found at path: $manifestPath"
    }

    if ($PSCmdlet.ShouldProcess($manifestPath, "Update ModuleVersion to $ResolvedBuildVersion and FunctionsToExport")) {
        $manifestContent = Get-Content -Path $manifestPath -Raw -ErrorAction Stop

        # Update ModuleVersion placeholder first, else replace ModuleVersion = '<value>' line
        if ($manifestContent -match '<ModuleVersion>') {
            $manifestContent = $manifestContent -replace [regex]::Escape('<ModuleVersion>'), [string]$ResolvedBuildVersion
        }
        else {
            # Replace an assignment like: ModuleVersion     = '1.0.0' (handle varying whitespace)
            $manifestContent = [regex]::Replace(
                $manifestContent,
                "(?m)^(\s*ModuleVersion\s*=\s*)'.*?'\s*$",
                "$1'$ResolvedBuildVersion'"
            )
        }

        # Discover public functions in the module's Public folder.
        $moduleDir = Split-Path -Path $manifestPath -Parent
        $publicFuncFolderPath = Join-Path -Path $moduleDir -ChildPath 'Public'

        if ((Test-Path -Path $publicFuncFolderPath) -and (Get-ChildItem -Path $publicFuncFolderPath -Filter '*.ps1' -File -ErrorAction SilentlyContinue)) {
            $publicFunctionNames = Get-ChildItem -Path $publicFuncFolderPath -Filter '*.ps1' -File | Select-Object -ExpandProperty BaseName
            if ($publicFunctionNames) {
                # Build a comma-separated quoted list like: 'Func1','Func2'
                $funcStrings = "'$($publicFunctionNames -join "','")'"
            }
            else {
                $funcStrings = ""
            }
        }
        else {
            $funcStrings = ""
        }

        # Replace the placeholder inside the array: @('<FunctionsToExport>') -> @('a','b') or @()
        if ($funcStrings -ne "") {
            $manifestContent = $manifestContent -replace "'<FunctionsToExport>'", $funcStrings
        }
        else {
            # remove the quoted placeholder so @() results
            $manifestContent = $manifestContent -replace "'<FunctionsToExport>'", ''
        }

        # Write updated manifest (preserve UTF8 encoding)
        Set-Content -Path $manifestPath -Value $manifestContent -Encoding UTF8 -Force -ErrorAction Stop
        Write-Host "Updated manifest: $manifestPath" -ForegroundColor Green
    }
    else {
        Write-Verbose "Operation skipped by ShouldProcess (WhatIf/Confirm)."
    }
}
catch {
    Write-Error "Failed to update manifest: $_"
    throw
}