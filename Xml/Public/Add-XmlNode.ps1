function Add-XmlNode {
    <#
    .SYNOPSIS
        Adds a new node to an XML file at the specified XPath location.

    .DESCRIPTION
        Adds a new node to an XML file under the parent selected by XPath. Supports -WhatIf/-Confirm.

    .PARAMETER XmlFilePath
        The path to the XML file where the new node will be added.

    .PARAMETER XPath
        The XPath expression to locate the parent node where the new node will be added.

    .PARAMETER NewNodeName
        The name of the new node to be added.

    .PARAMETER NewNodeValue
        Optional value to assign to the new node.

    .PARAMETER Attributes
        Optional hashtable of attributes to add to the new node.

    .PARAMETER RequireUnique
        When true, prevents adding a node if one with the same name and attributes already exists.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$XmlFilePath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$XPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$NewNodeName,
        [string]$NewNodeValue = $null,
        [hashtable]$Attributes = $null,
        [bool]$RequireUnique = $false
    )

    $xmlDoc = Get-JDXmlDocument -Path $XmlFilePath
    $parentNode = $xmlDoc.SelectSingleNode($XPath)
    if (-not $parentNode) { throw "XPath '$XPath' did not return any nodes in the XML document." }

    if ($RequireUnique) {
        $existingNodes = $parentNode.SelectNodes($NewNodeName)
        foreach ($node in $existingNodes) {
            $isMatch = $true
            if ($Attributes) {
                foreach ($key in $Attributes.Keys) {
                    if ($node.Attributes[$key] -and $node.Attributes[$key].Value -ne $Attributes[$key]) { $isMatch = $false; break }
                }
            }
            if ($isMatch) { Write-Verbose "A matching node already exists. Skipping addition."; return }
        }
    }

    $targetDesc = "parent selected by XPath '$XPath' in '$XmlFilePath'"
    if ($PSCmdlet.ShouldProcess($targetDesc, 'Add new XML node')) {
        $newNode = $xmlDoc.CreateElement($NewNodeName)
        if ($NewNodeValue) { $newNode.InnerText = $NewNodeValue }
        if ($Attributes) { foreach ($key in $Attributes.Keys) { $newNode.SetAttribute($key, [string]$Attributes[$key]) } }
        [void]$parentNode.AppendChild($newNode)
        Save-JDXmlDocument -Xml $xmlDoc -Path $XmlFilePath
    }
}