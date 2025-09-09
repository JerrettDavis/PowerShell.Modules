function Remove-XmlNode {
    <#
    .SYNOPSIS
        Removes nodes from an XML file based on the provided XPath.

    .DESCRIPTION
        Removes node(s) matched by the given XPath. Supports -WhatIf/-Confirm. By default, removes all
        matching nodes; use -SingleNode to enforce exactly one match.

    .PARAMETER XmlFilePath
        The path to the XML file from which nodes will be removed.

    .PARAMETER XPath
        The XPath expression to locate the nodes to be removed.

    .PARAMETER SingleNode
        Enforce removal only when exactly one node matches; throws if multiple nodes match.

    .EXAMPLE
        Remove-XmlNode -XmlFilePath 'file.xml' -XPath "/root/parent/child[@id='1']"

    .EXAMPLE
        Remove-XmlNode -XmlFilePath 'file.xml' -XPath '/root/parent/child' -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$XmlFilePath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$XPath,
        [switch]$SingleNode
    )

    $xmlDoc = Get-JDXmlDocument -Path $XmlFilePath

    $nodesToRemove = $xmlDoc.SelectNodes($XPath)
    if (-not $nodesToRemove -or $nodesToRemove.Count -eq 0) {
        Write-Warning "No nodes found matching the XPath '$XPath'."
        return
    }
    if ($SingleNode -and $nodesToRemove.Count -gt 1) {
        throw "XPath '$XPath' matched multiple nodes ($($nodesToRemove.Count)); use -SingleNode only when exactly one node matches or refine the XPath."
    }

    foreach ($node in @($nodesToRemove)) {
        $targetDesc = "node selected by XPath '$XPath' in '$XmlFilePath'"
        if ($PSCmdlet.ShouldProcess($targetDesc, 'Remove XML node')) {
            $parentNode = $node.ParentNode
            if ($null -ne $parentNode) {
                [void]$parentNode.RemoveChild($node)
            }
            else {
                throw "The node to be removed has no parent."
            }
        }
    }

    Save-JDXmlDocument -Xml $xmlDoc -Path $XmlFilePath
}