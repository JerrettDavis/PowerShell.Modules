function Save-JDXmlDocument {
    <#
    .SYNOPSIS
        Saves an XmlDocument object to a specified file path.   
    .DESCRIPTION
        Saves the provided XmlDocument to the given path. Supports -WhatIf/-Confirm.
    .PARAMETER Xml
        The XmlDocument object to save.
    .PARAMETER Path
        The file path where the XML document will be saved.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][ValidateNotNull()][xml]$Xml,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path
    )
    if ($PSCmdlet.ShouldProcess($Path, 'Save updated XML')) {
        try { $Xml.Save($Path) } catch { throw "Failed to save the updated XML file '$Path'. Error: $_" }
    }
}
