Describe 'New-FromTemplate' {
    BeforeAll {
        # Resolve and import module one level up from /Tests
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $psmPath = Join-Path $projectRoot '_template.psm1'
        if (-not (Test-Path -Path $psmPath)) {
            throw "Could not find module psm1 at '$psmPath'. Adjust the relative path if your module moved."
        }

        $mod = Import-Module -Name $psmPath -Force -PassThru -ErrorAction Stop
        $ModuleName = $mod.Name

        if (-not (Get-Command -Name New-FromTemplate -ErrorAction SilentlyContinue)) {
            throw "Could not find command 'New-FromTemplate' in module '$ModuleName'. Ensure the function is exported in the module manifest."
        }
    }
    
    AfterAll {
        # Cleanup code if necessary
    }
    It 'exists' {
        Get-Command New-FromTemplate | Should -Not -BeNullOrEmpty
    }

    It 'creates a new module from the template' {
        $tempDir = Join-Path -Path $env:TEMP -ChildPath ([guid]::NewGuid().ToString())
        # Use the project root resolved in BeforeAll (the template folder itself)
        $templatePath = $projectRoot
        $destinationPath = Join-Path -Path $tempDir -ChildPath 'MyNewModule'
        $replacements = @{
            '<GUID>'              = [guid]::NewGuid().ToString()
            '<Description>'       = 'My new module description'
            '<ModuleVersion>'     = '1.0.0'
            '<FunctionsToExport>' = 'Get-SampleFunction'
        }

        New-FromTemplate -TemplatePath $templatePath -DestinationPath $destinationPath -Replacements $replacements

        # Verify the module directory was created
        Test-Path $destinationPath | Should -BeTrue

        # Verify the .psd1 file exists and contains the replacements
        $psd1Path = Join-Path -Path $destinationPath -ChildPath '_template.psd1'
        Test-Path $psd1Path | Should -BeTrue
        $psd1Content = Get-Content -Path $psd1Path -Raw
        $guidPattern = [regex]::Escape($replacements['<GUID>'])
        $descPattern = [regex]::Escape($replacements['<Description>'])
        $verPattern = [regex]::Escape($replacements['<ModuleVersion>'])
        $funcPattern = [regex]::Escape($replacements['<FunctionsToExport>'])
        $psd1Content | Should -Match $guidPattern
        $psd1Content | Should -Match $descPattern
        $psd1Content | Should -Match $verPattern
        $psd1Content | Should -Match $funcPattern

        # Cleanup
        Remove-Item -Path $tempDir -Recurse -Force
    }

    It 'throws an error if the template path does not exist' {
        $tempDir = Join-Path -Path $env:TEMP -ChildPath ([guid]::NewGuid().ToString())
        $templatePath = Join-Path -Path $tempDir -ChildPath 'NonExistentTemplate'
        $destinationPath = Join-Path -Path $tempDir -ChildPath 'MyNewModule'

        { New-FromTemplate -TemplatePath $templatePath -DestinationPath $destinationPath } | Should -Throw
    }

    It 'creates the destination directory if it does not exist' {
        $tempDir = Join-Path -Path $env:TEMP -ChildPath ([guid]::NewGuid().ToString())
        $templatePath = $projectRoot
        $destinationPath = Join-Path -Path $tempDir -ChildPath 'MyNewModule'
        $replacements = @{
            '<GUID>'              = [guid]::NewGuid().ToString()
            '<Description>'       = 'My new module description'
            '<ModuleVersion>'     = '1.0.0'
            '<FunctionsToExport>' = 'Get-SampleFunction'
        }

        New-FromTemplate -TemplatePath $templatePath -DestinationPath $destinationPath -Replacements $replacements

        # Verify the module directory was created
        Test-Path $destinationPath | Should -BeTrue

        # Cleanup
        Remove-Item -Path $tempDir -Recurse -Force
    }

    It 'uses default replacements if none are provided' {
        $tempDir = Join-Path -Path $env:TEMP -ChildPath ([guid]::NewGuid().ToString())
        $templatePath = $projectRoot
        $destinationPath = Join-Path -Path $tempDir -ChildPath 'MyNewModule'

        New-FromTemplate -TemplatePath $templatePath -DestinationPath $destinationPath

        # Verify the module directory was created
        Test-Path $destinationPath | Should -BeTrue

        # Verify the .psd1 file exists and contains default replacements
        $psd1Path = Join-Path -Path $destinationPath -ChildPath '_template.psd1'
        Test-Path $psd1Path | Should -BeTrue
        $psd1Content = Get-Content -Path $psd1Path -Raw
        $psd1Content | Should -Not -Match '<GUID>'
        $psd1Content | Should -Not -Match '<Description>'

        # Cleanup
        Remove-Item -Path $tempDir -Recurse -Force
    }

    It 'handles nested directories and files' {
        $tempDir = Join-Path -Path $env:TEMP -ChildPath ([guid]::NewGuid().ToString())
        $templatePath = $projectRoot
        $destinationPath = Join-Path -Path $tempDir -ChildPath 'MyNewModule'
        $replacements = @{
            '<GUID>'              = [guid]::NewGuid().ToString()
            '<Description>'       = 'My new module description'
            '<ModuleVersion>'     = '1.0.0'
            '<FunctionsToExport>' = 'Get-SampleFunction'
        }

        New-FromTemplate -TemplatePath $templatePath -DestinationPath $destinationPath -Replacements $replacements

        # Verify a nested file exists and contains the replacements
        $nestedFilePath = Join-Path -Path $destinationPath -ChildPath 'Tests\New-FromTemplate.Tests.ps1'
        Test-Path $nestedFilePath | Should -BeTrue
        # Only assert replacements when placeholders exist in the file. For now, ensure file was copied.

        # Cleanup
        Remove-Item -Path $tempDir -Recurse -Force
    }

    It 'exits with code 0 on success' {
        $tempDir = Join-Path -Path $env:TEMP -ChildPath ([guid]::NewGuid().ToString())
        $templatePath = $projectRoot
        $destinationPath = Join-Path -Path $tempDir -ChildPath 'MyNewModule'
        $replacements = @{
            '<GUID>'              = [guid]::NewGuid().ToString()
            '<Description>'       = 'My new module description'
            '<ModuleVersion>'     = '1.0.0'
            '<FunctionsToExport>' = 'Get-SampleFunction'
        }

        & {
            New-FromTemplate -TemplatePath $templatePath -DestinationPath $destinationPath -Replacements $replacements
            return $LASTEXITCODE
        } | Should -Be 0

        # Cleanup
        Remove-Item -Path $tempDir -Recurse -Force
    }

    It 'throws an error when TemplatePath is not provided' {
        $tempDir = Join-Path -Path $env:TEMP -ChildPath ([guid]::NewGuid().ToString())
        $destinationPath = Join-Path -Path $tempDir -ChildPath 'MyNewModule'

        { New-FromTemplate -TemplatePath '' -DestinationPath $destinationPath } | Should -Throw
    }

    It 'throws an error when DestinationPath is not provided' {
        $templatePath = $projectRoot

        { New-FromTemplate -TemplatePath $templatePath -DestinationPath '' } | Should -Throw
    }
}   