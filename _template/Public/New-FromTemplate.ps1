function New-FromTemplate {
    <#
    .SYNOPSIS
        Creates a new PowerShell module from a template.
    .DESCRIPTION
        This function copies a template directory and replaces placeholders in the files with specified values.
    .PARAMETER TemplatePath
        The path to the template directory.
    .PARAMETER DestinationPath
        The path where the new module will be created.
    .PARAMETER Replacements
        A hashtable of placeholders and their replacement values. Default includes a new GUID and a description.
    .EXAMPLE
        New-FromTemplate -TemplatePath ".\_template" -DestinationPath ".\MyNewModule" -Replacements @{ '<GUID>' = [guid]::NewGuid().ToString(); '<Description>' = 'My new module description' }
        Creates a new module in ".\MyNewModule" using the template at ".\_template" and replaces the placeholders with a new GUID and the specified description.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$TemplatePath,
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath,
        [Parameter(Mandatory=$false)]
        [hashtable]$Replacements = @{
            '<GUID>'        = [guid]::NewGuid().ToString();
            '<Description>' = 'A description of the new module';
        }
    )
    # Ensure the template path exists
    if (-Not (Test-Path $TemplatePath)) {
        throw "Template path '$TemplatePath' does not exist."
    }

    # Create the destination directory if it doesn't exist
    if (-Not (Test-Path $DestinationPath)) {
        New-Item -Path $DestinationPath -ItemType Directory | Out-Null
    }

    # Create the replacements hashtable if it doesn't exist
    if (-Not $Replacements) {
        $Replacements = @{
            '<GUID>'        = [guid]::NewGuid().ToString();
            '<Description>' = 'A description of the new module';
        }
    }

    # Copy the template directory contents into the destination
    # Support passing the template root folder path; copy its children, not the root folder name itself
    Get-ChildItem -Path $TemplatePath -Force | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $DestinationPath -Recurse -Force
    }

    # Replace placeholders in the copied files (text files only)
    if ($Replacements) {
        Get-ChildItem -Path $DestinationPath -Recurse -File -Force | ForEach-Object {
            try {
                $content = Get-Content -Path $_.FullName -Raw -ErrorAction Stop
                foreach ($key in $Replacements.Keys) {
                    $content = $content -replace [regex]::Escape($key), [string]$Replacements[$key]
                }
                Set-Content -Path $_.FullName -Value $content -NoNewline
            }
            catch {
                # Skip binary or unreadable files silently
            }
        }
    }

    # Set exit code for callers without terminating the session (avoid breaking Pester host)
    $global:LASTEXITCODE = 0
}
