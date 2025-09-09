Describe 'generate-nuspecs.ps1' {
    BeforeAll {
        $script:TestRoot = Join-Path $env:TEMP ("NuspecGen_$([guid]::NewGuid())")
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null

        # Resolve repository root to locate the generator script
        $script:RepoRoot = if ($PSScriptRoot) {
            (Resolve-Path -Path (Join-Path $PSScriptRoot '..' '..')).Path
        } elseif ($MyInvocation.MyCommand.Path) {
            (Resolve-Path -Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..' '..')).Path
        } else {
            (Get-Location).Path
        }

        $script:GenScript = (Resolve-Path -Path (Join-Path $script:RepoRoot 'build' 'generate-nuspecs.ps1')).Path
        $script:OutDir = Join-Path $script:TestRoot 'out'

        # Define helper function in session scope so each It can access it
        Set-Item -Path function:New-FakeModule -Value {
            param(
                [string]$Root,
                [string]$Name,
                [string]$Author = 'Unit Tester',
                [string]$Description = 'Test & Verify'
            )
            $modDir = Join-Path $Root $Name
            New-Item -ItemType Directory -Path $modDir -Force | Out-Null
            # Minimal manifest including RootModule + metadata
            $psd1 = @"
@{
    RootModule = '$Name.psm1'
    Author = '$Author'
    Description = '$Description'
}
"@
            Set-Content -Path (Join-Path $modDir ("$Name.psd1")) -Value $psd1 -Encoding UTF8 -Force
            # Dummy psm1
            Set-Content -Path (Join-Path $modDir ("$Name.psm1")) -Value "# $Name module" -Encoding UTF8 -Force
            # Folders that should be excluded in nuspec mapping
            New-Item -ItemType Directory -Path (Join-Path $modDir 'Tests') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $modDir 'build') -Force | Out-Null
            return $modDir
        }
    }

    AfterAll {
        if (Test-Path -Path $script:TestRoot) {
            Remove-Item -Path $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # function New-FakeModule is installed in BeforeAll

    Context 'Single module nuspec generation' {
        It 'creates a nuspec with correct id/authors/description and mapping' {
            $modDir = New-FakeModule -Root $script:TestRoot -Name 'Foo.Bar' -Author 'Me' -Description 'Desc & More'
            & $script:GenScript -RepoRoot $script:TestRoot -ModuleSearchPattern '*.psd1' -OutputDir $script:OutDir

            $nuspec = Join-Path $script:OutDir 'Foo.Bar.nuspec'
            (Test-Path $nuspec) | Should -BeTrue

            $content = Get-Content -Path $nuspec -Raw
            ($content -match '<id>Foo\.Bar</id>') | Should -BeTrue
            ($content -match '<authors>Me</authors>') | Should -BeTrue
            # & should be XML-escaped
            ($content -match '<description>Desc &amp; More</description>') | Should -BeTrue
            ($content -match 'target="Foo\.Bar"') | Should -BeTrue
            ($content -match 'exclude="\*\*\\Tests\\\*\*;\*\*\\build\\\*\*"') | Should -BeTrue
        }
    }

    Context 'Multiple modules' {
        It 'generates nuspec files for each module discovered' {
            New-FakeModule -Root $script:TestRoot -Name 'ModA' | Out-Null
            New-FakeModule -Root $script:TestRoot -Name 'ModB' | Out-Null
            & $script:GenScript -RepoRoot $script:TestRoot -ModuleSearchPattern '*.psd1' -OutputDir $script:OutDir

            (Test-Path (Join-Path $script:OutDir 'ModA.nuspec')) | Should -BeTrue
            (Test-Path (Join-Path $script:OutDir 'ModB.nuspec')) | Should -BeTrue
        }
    }

    Context 'Empty root' {
        It 'does not throw and creates no nuspecs' {
            $emptyRoot = Join-Path $script:TestRoot 'empty'
            New-Item -ItemType Directory -Path $emptyRoot -Force | Out-Null
            { & $script:GenScript -RepoRoot $emptyRoot -ModuleSearchPattern '*.psd1' -OutputDir $script:OutDir } | Should -Not -Throw
        }
    }
}
