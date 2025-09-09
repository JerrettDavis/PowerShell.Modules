Describe 'build.ps1 behavior' {
    BeforeAll {
        # Resolve paths relative to this test file using $PSScriptRoot (reliable in script scope)
        $TestDir = $PSScriptRoot
        $RepoRoot = (Resolve-Path -Path (Join-Path $TestDir '..\..')).Path

        # Create a temporary workspace to avoid touching repo files
        $Temp = Join-Path $env:TEMP ("BuildTest_$([guid]::NewGuid().ToString())")
        New-Item -ItemType Directory -Path $Temp -Force | Out-Null

        # Prepare module layout: <Temp>\Xml\JerrettDavis.Xml.psd1
        $moduleFolder = Join-Path $Temp 'Xml'
        New-Item -ItemType Directory -Path $moduleFolder -Force | Out-Null

        Copy-Item -Path (Join-Path $RepoRoot 'Xml\JerrettDavis.Xml.psd1') -Destination (Join-Path $moduleFolder 'JerrettDavis.Xml.psd1') -Force

        # Create Public functions folder with a dummy function
        $public = Join-Path $moduleFolder 'Public'
        New-Item -ItemType Directory -Path $public -Force | Out-Null
        Set-Content -Path (Join-Path $public 'FuncA.ps1') -Value "function FuncA { [CmdletBinding()] param() }" -Force

        # Run the build script against the temporary module copy
        $BuildScript = Join-Path $RepoRoot 'Xml\build\build.ps1'
        & $BuildScript -ModuleName 'Xml\\JerrettDavis.Xml' -BuildVersion '2.3.4' -WorkingDirectory $Temp

        # Read manifest content for assertions
        $ManifestPath = Join-Path $moduleFolder 'JerrettDavis.Xml.psd1'
        $ManifestContent = Get-Content -Path $ManifestPath -Raw -ErrorAction Stop
    }

    AfterAll {
        if ($Temp -and (Test-Path -Path $Temp)) {
            Remove-Item -Path $Temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'updates ModuleVersion in the manifest' {
        ($ManifestContent -match "ModuleVersion\s*=\s*'2.3.4'") | Should -BeTrue
    }

    It 'lists public functions in FunctionsToExport' {
        ($ManifestContent -match "'FuncA'") | Should -BeTrue
    }
}
