Describe 'Update-XmlNode' {
    BeforeAll {
        $script:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Path $MyInvocation.MyCommand.Path -Parent } else { (Get-Location).Path }
        $modulePathCandidate = Join-Path -Path $script:ScriptRoot -ChildPath '..\JerrettDavis.Xml.psm1'
        $script:ModuleLocation = (Resolve-Path -Path $modulePathCandidate -ErrorAction Stop).Path
        Import-Module -Name $script:ModuleLocation -Force

        $script:XmlPath = Join-Path -Path $script:ScriptRoot -ChildPath 'update-test.xml'
        Set-Content -Path $script:XmlPath -Value "<root><parent><child id='1'>old</child><child id='2'>old</child></parent></root>" -Encoding UTF8
    }

    AfterAll {
        if (Test-Path -Path $script:XmlPath) { Remove-Item -Path $script:XmlPath -Force -ErrorAction SilentlyContinue }
    }

    It 'supports WhatIf with no file writes' {
        $before = Get-Content -Path $script:XmlPath -Raw
        Update-XmlNode -FilePath $script:XmlPath -XPath "/root/parent/child[@id='1']" -NewValue 'new' -WhatIf
        $after = Get-Content -Path $script:XmlPath -Raw
        $before | Should -Be $after
    }

    It 'updates a single node by default' {
    Update-XmlNode -FilePath $script:XmlPath -XPath "/root/parent/child[@id='1']" -NewValue 'new' -Confirm:$false
        $xml = [xml](Get-Content -Path $script:XmlPath -Raw)
        ($xml.SelectSingleNode("/root/parent/child[@id='1']").InnerText) | Should -Be 'new'
        ($xml.SelectSingleNode("/root/parent/child[@id='2']").InnerText) | Should -Be 'old'
    }

    It 'updates all nodes when -All is used' {
        # reset content
        Set-Content -Path $script:XmlPath -Value "<root><parent><child id='1'>old</child><child id='2'>old</child></parent></root>" -Encoding UTF8
    Update-XmlNode -FilePath $script:XmlPath -XPath "/root/parent/child" -NewAttributes @{ state = 'updated' } -All -Confirm:$false
        $xml = [xml](Get-Content -Path $script:XmlPath -Raw)
        $nodes = $xml.SelectNodes("/root/parent/child")
        ($nodes | ForEach-Object { $_.GetAttribute('state') } | Sort-Object | Get-Unique) -eq 'updated' | Should -BeTrue
    }

    It 'throws if -SingleNode is specified and multiple nodes match' {
        # reset content
        Set-Content -Path $script:XmlPath -Value "<root><parent><child id='1'>old</child><child id='2'>old</child></parent></root>" -Encoding UTF8
        { Update-XmlNode -FilePath $script:XmlPath -XPath "/root/parent/child" -NewValue 'new' -SingleNode } | Should -Throw
    }

    It 'throws when -All and -SingleNode are used together' {
        { Update-XmlNode -FilePath $script:XmlPath -XPath "/root/parent/child[@id='1']" -NewValue 'x' -All -SingleNode } | Should -Throw
    }

    It 'throws when TestValue does not match' {
        { Update-XmlNode -FilePath $script:XmlPath -XPath "/root/parent/child[@id='1']" -TestValue 'not-old' -NewValue 'x' } | Should -Throw
    }

    It 'throws when TestAttributes do not match' {
        { Update-XmlNode -FilePath $script:XmlPath -XPath "/root/parent/child[@id='1']" -TestAttributes @{ id = 'wrong' } -NewValue 'x' } | Should -Throw
    }
}
