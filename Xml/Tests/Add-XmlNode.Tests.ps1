# Resolve core paths in BeforeAll and store in $script: scope for reliability across Pester v3 blocks
Describe 'Add-XmlNode' {
    BeforeAll {
        $script:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Path $MyInvocation.MyCommand.Path -Parent } else { (Get-Location).Path }
        $modulePathCandidate = Join-Path -Path $script:ScriptRoot -ChildPath '..\JerrettDavis.Xml.psm1'
        $script:ModuleLocation = (Resolve-Path -Path $modulePathCandidate -ErrorAction Stop).Path
        Import-Module -Name $script:ModuleLocation -Force
    }
    Context 'When the XML file does not exist' {
        It 'should throw an error' {
            $nonExistentFilePath = Join-Path -Path $script:ScriptRoot -ChildPath 'nonexistent.xml'
            { Add-XmlNode -XmlFilePath $nonExistentFilePath -XPath "/root" -NewNodeName "child" } | Should -Throw
        }
    }

    Context 'When the XPath does not match any nodes' {
        It 'should throw an error' {
            $xmlContent = "<root></root>"
            $xmlFilePath = Join-Path -Path $script:ScriptRoot -ChildPath 'test.xml'
            $xmlContent | Set-Content -Path $xmlFilePath

            { Add-XmlNode -XmlFilePath $xmlFilePath -XPath "/nonexistent" -NewNodeName "child" } | Should -Throw
        }
    }

    Context 'When adding a new node to an empty parent' {
        It 'should add the new node successfully' {
            $xmlContent = "<root><parent></parent></root>"
            $xmlFilePath = Join-Path -Path $script:ScriptRoot -ChildPath 'test.xml'
            $xmlContent | Set-Content -Path $xmlFilePath

            Add-XmlNode -XmlFilePath $xmlFilePath -XPath "/root/parent" -NewNodeName "child" -NewNodeValue "value" -Confirm:$false

            $xmlDoc = [xml](Get-Content -Path $xmlFilePath -Raw)
            $childNode = $xmlDoc.SelectSingleNode("/root/parent/child")
            $childNode.InnerText | Should -Be "value"
        }
    }

    Context 'When adding a new node with attributes' {
        It 'should add the new node with the specified attributes' {
            $xmlContent = "<root><parent></parent></root>"
            $xmlFilePath = Join-Path -Path $script:ScriptRoot -ChildPath 'test.xml'
            $xmlContent | Set-Content -Path $xmlFilePath

            Add-XmlNode -XmlFilePath $xmlFilePath -XPath "/root/parent" -NewNodeName "child" -Attributes @{id = "1"; type = "example" } -Confirm:$false

            $xmlDoc = [xml](Get-Content -Path $xmlFilePath -Raw)
            $childNode = $xmlDoc.SelectSingleNode("/root/parent/child")
            $childNode.Attributes["id"].Value | Should -Be "1"
            $childNode.Attributes["type"].Value | Should -Be "example"
        }
    }

    Context 'When RequireUnique is true and a matching node exists' {
        It 'should not add the new node' {
            $xmlContent = "<root><parent><child id='1' type='example'>value</child></parent></root>"
            $xmlFilePath = Join-Path -Path $script:ScriptRoot -ChildPath 'test.xml'
            $xmlContent | Set-Content -Path $xmlFilePath

            Add-XmlNode -XmlFilePath $xmlFilePath -XPath "/root/parent" -NewNodeName "child" -NewNodeValue "value" -Attributes @{id = "1"; type = "example" } -RequireUnique $true -Confirm:$false

            $xmlDoc = [xml](Get-Content -Path $xmlFilePath -Raw)
            $childNodes = $xmlDoc.SelectNodes("/root/parent/child")
            $childNodes.Count | Should -Be 1
        }
    }

    AfterAll {
        $testFile = Join-Path -Path $script:ScriptRoot -ChildPath 'test.xml'
        if (Test-Path -Path $testFile) { Remove-Item -Path $testFile -Force -ErrorAction SilentlyContinue }
    }
}
        
