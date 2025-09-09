Describe 'Remove-XmlNode' {
    BeforeAll {
        $script:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Path $MyInvocation.MyCommand.Path -Parent } else { (Get-Location).Path }
        $modulePathCandidate = Join-Path -Path $script:ScriptRoot -ChildPath '..\JerrettDavis.Xml.psm1'
        $script:ModuleLocation = (Resolve-Path -Path $modulePathCandidate -ErrorAction Stop).Path
        Import-Module -Name $script:ModuleLocation -Force
    }

    Context 'When the XML file does not exist' {
        It 'should throw an error' {
            $nonExistentFilePath = Join-Path -Path $script:ScriptRoot -ChildPath 'nonexistent.xml'
            { Remove-XmlNode -XmlFilePath $nonExistentFilePath -XPath "/root/child" } | Should -Throw
        }
    }

    Context 'When removing an existing node' {
        It 'should remove the node successfully' {
            $xmlContent = "<root><parent><child id='1' type='example'>value</child></parent></root>"
            $xmlFilePath = Join-Path -Path $script:ScriptRoot -ChildPath 'test.xml'
            $xmlContent | Set-Content -Path $xmlFilePath

            Remove-XmlNode -XmlFilePath $xmlFilePath -XPath "/root/parent/child[@id='1' and @type='example']" -Confirm:$false

            $xmlDoc = [xml](Get-Content -Path $xmlFilePath -Raw)
            $childNode = $xmlDoc.SelectSingleNode("/root/parent/child[@id='1' and @type='example']")
            $null | Should -Be $childNode
        }
    }

    Context 'When removing a node that does not exist' {
        It 'should issue a warning and not throw an error' {
            $xmlContent = "<root><parent></parent></root>"
            $xmlFilePath = Join-Path -Path $script:ScriptRoot -ChildPath 'test.xml'
            $xmlContent | Set-Content -Path $xmlFilePath

            { Remove-XmlNode -XmlFilePath $xmlFilePath -XPath "/root/parent/child[@id='1']" -Confirm:$false } | Should -Not -Throw
        }
    }

    Context 'When the XML file is malformed' {
        It 'should throw an error' {
            $malformedXmlContent = "<root><parent><child></parent></root>"
            $xmlFilePath = Join-Path -Path $script:ScriptRoot -ChildPath 'malformed.xml'
            $malformedXmlContent | Set-Content -Path $xmlFilePath

            { Remove-XmlNode -XmlFilePath $xmlFilePath -XPath "/root/parent/child" } | Should -Throw
        }
    }

    Context 'When the node to be removed has no parent' {
        It 'should throw an error' {
            $xmlContent = "<root></root>"
            $xmlFilePath = Join-Path -Path $script:ScriptRoot -ChildPath 'test.xml'
            $xmlContent | Set-Content -Path $xmlFilePath

            { Remove-XmlNode -XmlFilePath $xmlFilePath -XPath "/root" -Confirm:$false } | Should -Throw
        }
    }

    AfterAll {
        $testFiles = @('test.xml', 'malformed.xml', 'nonexistent.xml')
        foreach ($file in $testFiles) {
            $filePath = Join-Path -Path $script:ScriptRoot -ChildPath $file
            if (Test-Path -Path $filePath) {
                Remove-Item -Path $filePath -Force
            }
        }
    }

}