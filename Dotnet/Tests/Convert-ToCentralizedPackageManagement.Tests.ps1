Describe 'Convert-ToCentralizedPackageManagement (psm1 import + behaviors)' -Tag 'cpmmigration' {

  BeforeAll {
    # Resolve and import module one level up from /Tests
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $psmPath     = Join-Path $projectRoot 'JerrettDavis.Dotnet.psm1'
    if (-not (Test-Path -Path $psmPath)) {
      throw "Could not find module psm1 at '$psmPath'. Adjust the relative path if your module moved."
    }

    $mod = Import-Module -Name $psmPath -Force -PassThru -ErrorAction Stop
    $ModuleName = $mod.Name

    # Sanity check: exported function exists
    $fn = Get-Command -Module $ModuleName -Name Convert-ToCentralizedPackageManagement -ErrorAction SilentlyContinue
    if (-not $fn) {
      throw "Function 'Convert-ToCentralizedPackageManagement' is not exported/visible from '$psmPath'. Ensure it is defined and exported by the module."
    }
  }

  Context 'End-to-end migration in TestDrive' {
    BeforeEach {
      # Build all paths under $TestDrive
      $srcA           = Join-Path $TestDrive 'src\ProjA'
      $srcB           = Join-Path $TestDrive 'src\ProjB'
      $srcC           = Join-Path $TestDrive 'tools\ProjC'
      $ProjAPath      = Join-Path $srcA 'ProjA.csproj'
      $ProjBPath      = Join-Path $srcB 'ProjB.csproj'
      $ProjCPath      = Join-Path $srcC 'ProjC.csproj'
      $SolutionPath   = Join-Path $TestDrive 'MySolution.sln'
      $BuildPropsPath = Join-Path $TestDrive 'Directory.Build.props'
      $PackagesProps  = Join-Path $TestDrive 'Directory.Packages.props'

      # Ensure directories
      New-Item -ItemType Directory -Path $srcA -Force | Out-Null
      New-Item -ItemType Directory -Path $srcB -Force | Out-Null
      New-Item -ItemType Directory -Path $srcC -Force | Out-Null

      # Project contents
      $csprojA = @'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
    <PackageReference Include="FluentAssertions" Version="6.12.0" />
    <PackageReference Include="SameAcrossProjects" Version="1.2.3" />
    <PackageReference Include="AlreadyCentralized" />
  </ItemGroup>
</Project>
'@

      $csprojB = @'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="Newtonsoft.Json">
      <Version>13.0.2</Version>
    </PackageReference>
    <PackageReference Include="xunit" Version="2.7.1" />
    <PackageReference Include="SameAcrossProjects">
      <Version>1.2.4</Version>
    </PackageReference>
    <PackageReference Include="PreReleaseTest" Version="2.0.0-beta.1" />
  </ItemGroup>
</Project>
'@

      $csprojC = @'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="FluentAssertions" Version="6.11.0" />
    <PackageReference Include="xunit" Version="2.8.0" />
    <PackageReference Include="PreReleaseTest" Version="2.0.0" />
    <PackageReference Include="WeirdVersion" Version="1.0" />
    <PackageReference Include="WeirdVersion" Version="1.0.0" />
  </ItemGroup>
</Project>
'@

      Set-Content -LiteralPath $ProjAPath -Value $csprojA -Encoding UTF8
      Set-Content -LiteralPath $ProjBPath -Value $csprojB -Encoding UTF8
      Set-Content -LiteralPath $ProjCPath -Value $csprojC -Encoding UTF8

      # Solution referencing the projects (use forward slashes to be parser-friendly)
      $sln = @'
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "ProjA", "src/ProjA/ProjA.csproj", "{11111111-1111-1111-1111-111111111111}"
EndProject
Project("{F184B08F-C81C-45F6-A57F-5ABD9991F28F}") = "ProjB", "src/ProjB/ProjB.csproj", "{22222222-2222-2222-2222-222222222222}"
EndProject
Project("{F2A71F9B-5D33-465A-A702-920D77279786}") = "ProjC", "tools/ProjC/ProjC.csproj", "{33333333-3333-3333-3333-333333333333}"
EndProject
Global
EndGlobal
'@
      Set-Content -LiteralPath $SolutionPath -Value $sln -Encoding UTF8

      # Expose to Its
      Set-Variable SolutionPath,$BuildPropsPath,$PackagesProps,$ProjAPath,$ProjBPath,$ProjCPath -Option None -Scope Local
    }

    It 'Creates props files; centralizes latest versions; strips versions in projects' {
      Convert-ToCentralizedPackageManagement -Solution $SolutionPath -BuildPropsPath $BuildPropsPath -PackagesPropsPath $PackagesProps -Verbose | Out-Null

      $BuildPropsPath | Should -Exist
      $PackagesProps  | Should -Exist

      (Get-Content -Raw -LiteralPath $BuildPropsPath) |
        Should -Match '<ManagePackageVersionsCentrally>\s*true\s*</ManagePackageVersionsCentrally>'

      $pp = Get-Content -Raw -LiteralPath $PackagesProps
      $pp | Should -Match '<PackageVersion Include="Newtonsoft\.Json" Version="13\.0\.2" />'
      $pp | Should -Match '<PackageVersion Include="FluentAssertions" Version="6\.12\.0" />'
      $pp | Should -Match '<PackageVersion Include="xunit" Version="2\.8\.0" />'
      $pp | Should -Match '<PackageVersion Include="SameAcrossProjects" Version="1\.2\.4" />'
      $pp | Should -Match '<PackageVersion Include="PreReleaseTest" Version="2\.0\.0" />'
      ($pp -match '<PackageVersion Include="WeirdVersion" Version="1\.0(\.0)?" />') | Should -BeTrue

      (Get-Content -Raw -LiteralPath $ProjAPath) | Should -Not -Match '<PackageReference[^>]+Version='
      (Get-Content -Raw -LiteralPath $ProjBPath) | Should -Not -Match '<Version>\s*[\d\w\.-]+\s*</Version>'
      (Get-Content -Raw -LiteralPath $ProjCPath) | Should -Not -Match '<PackageReference[^>]+Version='
      (Get-Content -Raw -LiteralPath $ProjAPath) | Should -Match '<PackageReference Include="AlreadyCentralized"\s*/?>'
    }

    It 'Supports -Backup and writes .bak files when changes occur' {
      Convert-ToCentralizedPackageManagement -Solution $SolutionPath -BuildPropsPath $BuildPropsPath -PackagesPropsPath $PackagesProps -Backup -Verbose | Out-Null

      ($ProjAPath + '.bak') | Should -Exist
      ($ProjBPath + '.bak') | Should -Exist
      ($ProjCPath + '.bak') | Should -Exist
    }

    It 'Is idempotent across runs' {
      Convert-ToCentralizedPackageManagement -Solution $SolutionPath -BuildPropsPath $BuildPropsPath -PackagesPropsPath $PackagesProps -Verbose | Out-Null

      $pp1 = Get-Content -Raw -LiteralPath $PackagesProps
      $a1  = Get-Content -Raw -LiteralPath $ProjAPath
      $b1  = Get-Content -Raw -LiteralPath $ProjBPath
      $c1  = Get-Content -Raw -LiteralPath $ProjCPath

      Start-Sleep -Milliseconds 50

      Convert-ToCentralizedPackageManagement -Solution $SolutionPath -BuildPropsPath $BuildPropsPath -PackagesPropsPath $PackagesProps -Verbose | Out-Null

      $pp2 = Get-Content -Raw -LiteralPath $PackagesProps
      $a2  = Get-Content -Raw -LiteralPath $ProjAPath
      $b2  = Get-Content -Raw -LiteralPath $ProjBPath
      $c2  = Get-Content -Raw -LiteralPath $ProjCPath

      $pp2 | Should -Be $pp1
      $a2  | Should -Be $a1
      $b2  | Should -Be $b1
      $c2  | Should -Be $c1
    }

    It 'Honors -WhatIf (no files are created or changed)' {
      # Use unique output paths so prior tests can't create these
      $whatIfBuild    = Join-Path $TestDrive 'whatif\Directory.Build.props'
      $whatIfPackages = Join-Path $TestDrive 'whatif\Directory.Packages.props'
      New-Item -ItemType Directory -Path (Split-Path $whatIfBuild -Parent) -Force | Out-Null

      Test-Path $whatIfBuild    | Should -BeFalse
      Test-Path $whatIfPackages | Should -BeFalse

      Convert-ToCentralizedPackageManagement -Solution $SolutionPath -BuildPropsPath $whatIfBuild -PackagesPropsPath $whatIfPackages -WhatIf -Verbose | Out-Null

      Test-Path $whatIfBuild    | Should -BeFalse
      Test-Path $whatIfPackages | Should -BeFalse

      (Get-Content -Raw -LiteralPath $ProjAPath) | Should -Match 'Version="13\.0\.1"'
      (Get-Content -Raw -LiteralPath $ProjBPath) | Should -Match '<Version>\s*13\.0\.2\s*</Version>'
    }

    It 'Updates Directory.Build.props if it exists but lacks ManagePackageVersionsCentrally' {
      Set-Content -LiteralPath $BuildPropsPath -Value @'
<Project>
  <PropertyGroup>
    <Company>Sample</Company>
  </PropertyGroup>
</Project>
'@ -Encoding UTF8

      Convert-ToCentralizedPackageManagement -Solution $SolutionPath -BuildPropsPath $BuildPropsPath -PackagesPropsPath $PackagesProps -Verbose | Out-Null

      $bp = Get-Content -Raw -LiteralPath $BuildPropsPath
      $bp | Should -Match '<ManagePackageVersionsCentrally>\s*true\s*</ManagePackageVersionsCentrally>'
      $bp | Should -Match '<Company>Sample</Company>'
    }

    It 'Respects -PackagesSort None (retains discovery order in our dataset)' {
      Convert-ToCentralizedPackageManagement -Solution $SolutionPath -BuildPropsPath $BuildPropsPath -PackagesPropsPath $PackagesProps -PackagesSort None -Verbose | Out-Null

      $pp = Get-Content -Raw -LiteralPath $PackagesProps
      $idxNewton = $pp.IndexOf('Include="Newtonsoft.Json"')
      $idxFluent = $pp.IndexOf('Include="FluentAssertions"')
      $idxXunit  = $pp.IndexOf('Include="xunit"')

      ($idxNewton -ge 0) | Should -BeTrue
      ($idxFluent -ge 0) | Should -BeTrue
      ($idxXunit  -ge 0) | Should -BeTrue
      ($idxNewton -lt $idxFluent) | Should -BeTrue
    }

    It 'Allows custom paths for props files' {
      $customBuild    = Join-Path $TestDrive 'eng\custom\Build.props'
      $customPackages = Join-Path $TestDrive 'eng\custom\Packages.props'
      New-Item -ItemType Directory -Path (Split-Path $customBuild -Parent) -Force | Out-Null

      Convert-ToCentralizedPackageManagement -Solution $SolutionPath -BuildPropsPath $customBuild -PackagesPropsPath $customPackages -Verbose | Out-Null

      $customBuild    | Should -Exist
      $customPackages | Should -Exist
    }

    It 'Handles projects already versionless without reintroducing versions' {
      $content = (Get-Content -Raw -LiteralPath $ProjAPath) `
        -replace ' Version="[^"]+"','' `
        -replace '<Version>[^<]+</Version>',''
      Set-Content -LiteralPath $ProjAPath -Value $content -Encoding UTF8

      Convert-ToCentralizedPackageManagement -Solution $SolutionPath -BuildPropsPath $BuildPropsPath -PackagesPropsPath $PackagesProps -Verbose | Out-Null

      (Get-Content -Raw -LiteralPath $ProjAPath) | Should -Not -Match 'Version='
    }

    It 'Pre-release is less than release (2.0.0-beta.1 < 2.0.0)' {
      Convert-ToCentralizedPackageManagement -Solution $SolutionPath -BuildPropsPath $BuildPropsPath -PackagesPropsPath $PackagesProps -Verbose | Out-Null

      $pp = Get-Content -Raw -LiteralPath $PackagesProps
      $pp | Should -Match '<PackageVersion Include="PreReleaseTest" Version="2\.0\.0" />'
      $pp | Should -Not -Match '<PackageVersion Include="PreReleaseTest" Version="2\.0\.0-beta\.1" />'
    }

    It 'Removes both Version attribute and <Version> child nodes' {
      Convert-ToCentralizedPackageManagement -Solution $SolutionPath -BuildPropsPath $BuildPropsPath -PackagesPropsPath $PackagesProps -Verbose | Out-Null

      $projAxml = [xml](Get-Content -Raw -LiteralPath $ProjAPath)
      $projBxml = [xml](Get-Content -Raw -LiteralPath $ProjBPath)

      $nodesA = $projAxml.SelectNodes("//*[local-name()='PackageReference']")
      foreach ($n in $nodesA) { $n.Attributes['Version'] | Should -BeNullOrEmpty }

      $nodesB = $projBxml.SelectNodes("//*[local-name()='PackageReference']/*[local-name()='Version']")
      @($nodesB).Count | Should -Be 0
    }
  }

  Context 'Edge cases' {

    It 'Throws when solution references no project files' {
      $emptySln = Join-Path $TestDrive 'Empty.sln'
      Set-Content -LiteralPath $emptySln -Value @'
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
Global
EndGlobal
'@ -Encoding UTF8

      { Convert-ToCentralizedPackageManagement -Solution $emptySln } | Should -Throw
    }

    It 'Handles csproj with default XML namespace (xmlns) via local-name() XPath' {
      $nsDir   = Join-Path $TestDrive 'ns\ProjNs'
      New-Item -ItemType Directory -Path $nsDir -Force | Out-Null
      $nsProj  = Join-Path $nsDir 'ProjNs.csproj'
      $nsSln   = Join-Path $TestDrive 'Ns.sln'
      $nsBuild = Join-Path $TestDrive 'Directory.Build.props'
      $nsPack  = Join-Path $TestDrive 'Directory.Packages.props'

      Set-Content -LiteralPath $nsProj -Value @'
<Project Sdk="Microsoft.NET.Sdk" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup>
    <PackageReference Include="NsAware" Version="1.0.0" />
  </ItemGroup>
</Project>
'@ -Encoding UTF8

      Set-Content -LiteralPath $nsSln -Value @'
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "ProjNs", "ns/ProjNs/ProjNs.csproj", "{44444444-4444-4444-4444-444444444444}"
EndProject
Global
EndGlobal
'@ -Encoding UTF8

      Convert-ToCentralizedPackageManagement -Solution $nsSln -BuildPropsPath $nsBuild -PackagesPropsPath $nsPack -Verbose | Out-Null

      (Get-Content -Raw -LiteralPath $nsProj) | Should -Not -Match 'Version='
      (Get-Content -Raw -LiteralPath $nsPack) | Should -Match 'Include="NsAware"'
    }
  }
}
