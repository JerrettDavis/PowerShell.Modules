function Update-XmlNode {
    <#
    .SYNOPSIS
        Updates one or more nodes in an XML file based on an XPath.

    .DESCRIPTION
        Updates the node(s) selected by XPath with a new inner text value and/or attributes.
        If TestValue and/or TestAttributes are provided, each target node must match those
        conditions before the update is applied. Supports -WhatIf/-Confirm.

    .PARAMETER FilePath
        The path to the XML file to update.

    .PARAMETER XPath
        The XPath query selecting the node(s) to update.

    .PARAMETER NewValue
        Optional new inner text value to set on the node(s).

    .PARAMETER TestValue
        Optional expected current inner text value; if provided, nodes with a different value will cause an error.

    .PARAMETER NewAttributes
        Optional hashtable of attributes to add or update on the node(s) (e.g. @{ id = '2'; type = 'updated' }).

    .PARAMETER TestAttributes
        Optional hashtable of attributes that must already be present with matching values; otherwise an error is thrown.

    .PARAMETER All
        Update all nodes matched by the XPath. By default, only the first matching node is updated (backwards compatible).

    .PARAMETER PassThru
        When specified, outputs the updated XmlNode objects.

    .EXAMPLE
        Update-XmlNode -FilePath 'C:\path\to\file.xml' -XPath '/root/parent/child' -NewValue 'new' -NewAttributes @{ id = '2' } -WhatIf

    .EXAMPLE
        Update-XmlNode -FilePath 'file.xml' -XPath '//item' -NewAttributes @{ state = 'active' } -All -Confirm
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$XPath,

        [string]$NewValue = $null,
        [string]$TestValue = $null,

        [hashtable]$NewAttributes = $null,
        [hashtable]$TestAttributes = $null,

        [switch]$All,
        [switch]$SingleNode,
        [switch]$PassThru
    )

    if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
        throw "The specified XML file path '$FilePath' does not exist."
    }

    try {
        [xml]$xmlDoc = Get-Content -Path $FilePath -Raw -ErrorAction Stop
    }
    catch {
        throw "Failed to load XML file. Ensure the file is a valid XML document. Error: $_"
    }

    # Validate flag combinations
    if ($All -and $SingleNode) {
        throw "Parameters -All and -SingleNode are mutually exclusive. Choose one."
    }

    # Select nodes; default to the first one (backwards-compatible) unless -All is used.
    $selectedNodes = $xmlDoc.SelectNodes($XPath)
    if (-not $selectedNodes -or $selectedNodes.Count -eq 0) {
        throw "XPath '$XPath' did not return any nodes in the XML document."
    }
    if ($SingleNode -and $selectedNodes.Count -gt 1) {
        throw "XPath '$XPath' matched multiple nodes ($($selectedNodes.Count)); use -SingleNode only when exactly one node matches or refine the XPath."
    }
    if (-not $All) {
        $selectedNodes = @($selectedNodes[0])
    }

    $updatedNodes = @()
    $anyChanges = $false

    foreach ($nodeToUpdate in $selectedNodes) {
        # Validate preconditions only if parameters were explicitly provided
        if ($PSBoundParameters.ContainsKey('TestValue') -and $nodeToUpdate.InnerText -ne $TestValue) {
            throw "Node at XPath '$XPath' does not match TestValue. Current: '$($nodeToUpdate.InnerText)'; Expected: '$TestValue'"
        }
        if ($PSBoundParameters.ContainsKey('TestAttributes') -and $null -ne $TestAttributes) {
            foreach ($key in $TestAttributes.Keys) {
                $attr = $nodeToUpdate.Attributes[$key]
                if (-not $attr -or $attr.Value -ne $TestAttributes[$key]) {
                    throw "Node at XPath '$XPath' attribute '$key' does not match expected value. Current: '$($attr?.Value)'; Expected: '$($TestAttributes[$key])'"
                }
            }
        }

        # Build a concise description for ShouldProcess
        $targetDesc = "node selected by XPath '$XPath' in '$FilePath'"
        $actionDesc = "Update"

        if ($PSCmdlet.ShouldProcess($targetDesc, $actionDesc)) {
            $nodeChanged = $false

            if ($null -ne $NewValue -and $nodeToUpdate.InnerText -ne $NewValue) {
                $nodeToUpdate.InnerText = $NewValue
                $nodeChanged = $true
            }
            if ($null -ne $NewAttributes) {
                foreach ($key in $NewAttributes.Keys) {
                    $existing = $nodeToUpdate.Attributes[$key]
                    $newVal = [string]$NewAttributes[$key]
                    if ($existing) {
                        if ($existing.Value -ne $newVal) {
                            $existing.Value = $newVal
                            $nodeChanged = $true
                        }
                    }
                    else {
                        $newAttr = $xmlDoc.CreateAttribute($key)
                        $newAttr.Value = $newVal
                        [void]$nodeToUpdate.Attributes.Append($newAttr)
                        $nodeChanged = $true
                    }
                }
            }

            if ($nodeChanged) {
                $anyChanges = $true
                if ($PassThru) { $updatedNodes += $nodeToUpdate }
            }
        }
    }

    if ($anyChanges) {
        if ($PSCmdlet.ShouldProcess($FilePath, 'Save updated XML')) {
            try {
                $xmlDoc.Save($FilePath)
                Write-Verbose "Successfully updated the XML file at '$FilePath'."
            }
            catch {
                throw "Failed to save the updated XML file. Error: $_"
            }
        }
    }

    if ($PassThru) { return $updatedNodes }
}