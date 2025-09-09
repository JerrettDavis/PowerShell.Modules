function Get-JDXmlDocument {
    <#
    .SYNOPSIS
        Loads an XML file and returns it as an XmlDocument object.  
    .DESCRIPTION
        Loads the XML file at the specified path and returns it as an XmlDocument. Throws if the file does not exist or cannot be loaded.
    .PARAMETER Path
        The file path of the XML document to load.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path
    )
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "The specified XML file path '$Path' does not exist."
    }
    try {
        return [xml](Get-Content -Path $Path -Raw -ErrorAction Stop)
    } catch {
        throw "Failed to load XML file at '$Path'. Error: $_"
    }
}
