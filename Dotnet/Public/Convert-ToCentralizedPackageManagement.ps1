function Convert-ToCentralizedPackageManagement {
    <#
    .SYNOPSIS
        Converts a .NET solution to use Centralized Package Management.
    .DESCRIPTION
        Converts a .NET solution to use Centralized Package Management by creating or updating
        Directory.Build.props and Directory.Packages.props files, and stripping version attributes
        from PackageReference elements in project files. Supports -WhatIf/-Confirm.

    .PARAMETER Solution
        The path to the .sln file to process.

    .PARAMETER BuildPropsPath
        Optional path to the Directory.Build.props file to create or update. Defaults to
        <root>/Directory.Build.props.

    .PARAMETER PackagesPropsPath
        Optional path to the Directory.Packages.props file to create or update. Defaults to
        <root>/Directory.Packages.props.

    .PARAMETER PackagesSort
        Optional sorting method for packages in Directory.Packages.props. 'Alpha' sorts
        packages alphabetically by name. 'None' leaves them in the order discovered.
        Default is 'Alpha'.

    .PARAMETER Backup
        If specified, creates a backup copy of each project file before modifying it,
        with a .bak extension.

    .EXAMPLE
        Convert-ToCentralizedPackageManagement -Solution 'C:\path\to\MySolution.sln' -WhatIf
    .EXAMPLE
        Convert-ToCentralizedPackageManagement -Solution 'C:\path\to\MySolution.sln' -Backup
    .EXAMPLE
        Convert-ToCentralizedPackageManagement -Solution 'C:\path\to\MySolution.sln' -BuildPropsPath 'C:\path\to\props\Directory.Build.props' -PackagesPropsPath 'C:\path\to\props\Directory.Packages.props' -PackagesSort 'None'
    .OUTPUTS
        A custom object with details of the operation, including paths used and package summary.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$Solution,

        [Parameter()]
        [string]$BuildPropsPath,

        [Parameter()]
        [string]$PackagesPropsPath,

        [Parameter()]
        [ValidateSet('Alpha','None')]
        [string]$PackagesSort = 'Alpha',

        [switch]$Backup
    )

    #region helpers

    function Resolve-RootAndDefaults {
        param(
            [Parameter(Mandatory)][string]$Solution,
            [string]$BuildPropsPath,
            [string]$PackagesPropsPath
        )
        $solFull = (Resolve-Path -LiteralPath $Solution).ProviderPath
        $root    = Split-Path -Parent $solFull
        if (-not $BuildPropsPath)    { $BuildPropsPath    = Join-Path $root 'Directory.Build.props' }
        if (-not $PackagesPropsPath) { $PackagesPropsPath = Join-Path $root 'Directory.Packages.props' }
        [pscustomobject]@{
            SolutionFull      = $solFull
            Root              = $root
            BuildPropsPath    = $BuildPropsPath
            PackagesPropsPath = $PackagesPropsPath
        }
    }

    function Resolve-SolutionProjects {
        param([Parameter(Mandatory)][string]$SolutionFull, [Parameter(Mandatory)][string]$Root)

        $text = Get-Content -LiteralPath $SolutionFull -Raw
        $rx = [regex]'Project\(".*?"\)\s*=\s*".*?",\s*"(.*?)"\s*,\s*"\{[0-9A-Fa-f\-]+\}"'
        $projMatches = $rx.Matches($text)

        $out = foreach ($m in $projMatches) {
            $rel = $m.Groups[1].Value.Trim()
            $relNorm = $rel -replace '\\','/'
            if ($relNorm -match '\.(csproj|vbproj|fsproj)$') {
                [System.IO.Path]::GetFullPath((Join-Path $Root ($relNorm -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
            }
        }

        # Force array even for one result
        return @($out | Where-Object { $_ } | Select-Object -Unique)
    }

    function Format-Version {
        param([string]$Version)
        $v = ($Version ?? '').Trim()
        if (-not $v) { return '' }
        $pre = $null
        if ($v -match '\+') { $parts = $v.Split('+',2); $v = $parts[0]; }
        if ($v -match '-')  { $parts = $v.Split('-',2); $v = $parts[0]; $pre = $parts[1] }
        $nums = $v.Split('.')
        while ($nums.Count -lt 3) { $nums += '0' }
        $core = ($nums[0..2] -join '.')
        if ($pre) { "$core-$pre" } else { $core }
    }

    function Compare-NuGetVersion {
        param([string]$A, [string]$B)
        $na = Format-Version $A
        $nb = Format-Version $B
        if ($na -eq $nb) { return 0 }

        $splitCore = {
            param($x)
            $pre = $null
            if ($x -match '-') { $p = $x.Split('-',2); $core = $p[0]; $pre = $p[1] } else { $core = $x }
            $nums = $core.Split('.') | ForEach-Object { [int]$_ }
            [pscustomobject]@{ Major=$nums[0]; Minor=$nums[1]; Patch=$nums[2]; Pre=$pre }
        }

        $va = & $splitCore $na
        $vb = & $splitCore $nb

        foreach ($k in 'Major','Minor','Patch') {
            if ($va.$k -lt $vb.$k) { return -1 }
            if ($va.$k -gt $vb.$k) { return 1 }
        }

        if ($va.Pre -and -not $vb.Pre) { return -1 }
        if (-not $va.Pre -and $vb.Pre) { return 1 }
        if (-not $va.Pre -and -not $vb.Pre) { return 0 }

        $aIds = $va.Pre.Split('.')
        $bIds = $vb.Pre.Split('.')
        $len = [Math]::Max($aIds.Count, $bIds.Count)
        for ($i=0; $i -lt $len; $i++) {
            $ai = if ($i -lt $aIds.Count) { $aIds[$i] } else { $null }
            $bi = if ($i -lt $bIds.Count) { $bIds[$i] } else { $null }
            if ($null -eq $ai -and $null -eq $bi) { return 0 }
            if ($null -eq $ai) { return -1 }
            if ($null -eq $bi) { return 1 }

            $ain = 0; $bin = 0
            $aNum = [int]::TryParse($ai, [ref]$ain)
            $bNum = [int]::TryParse($bi, [ref]$bin)
            if ($aNum -and $bNum) {
                if ($ain -lt $bin) { return -1 }
                if ($ain -gt $bin) { return 1 }
            } else {
                $cmp = [string]::Compare($ai, $bi, $true)
                if ($cmp -lt 0) { return -1 }
                if ($cmp -gt 0) { return 1 }
            }
        }
        0
    }

    function Get-PackageReferences {
        param([Parameter(Mandatory)][string]$ProjectPath)
        $xml = [xml](Get-Content -LiteralPath $ProjectPath -Raw)
        $nodes = $xml.SelectNodes("//*[local-name()='PackageReference']")
        foreach ($n in $nodes) {
            $include = $n.Attributes['Include']?.Value
            if (-not $include) { continue }

            $verAttr  = $n.Attributes['Version']?.Value
            # child <Version> under the same node, not global:
            $verChild = $n.SelectSingleNode("*[local-name()='Version']")?.InnerText
            $version  = if ($verAttr) { $verAttr } elseif ($verChild) { $verChild } else { $null }

            [pscustomobject]@{ Include = $include; Version = $version }
        }
    }

    function Test-DirectoryForFile { param([string]$Path)
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    function Write-BuildProps {
        param([string]$Path)
        if (Test-Path -LiteralPath $Path) {
            $xml = [xml](Get-Content -LiteralPath $Path -Raw)
        } else {
            $xml = New-Object System.Xml.XmlDocument
            $proj = $xml.CreateElement('Project'); $null = $xml.AppendChild($proj)
        }
        $proj = $xml.SelectSingleNode("//*[local-name()='Project']")
        $pg   = $proj.SelectSingleNode("*[local-name()='PropertyGroup']")
        if (-not $pg) { $pg = $xml.CreateElement('PropertyGroup'); $null = $proj.AppendChild($pg) }

        $mpvc = $pg.SelectSingleNode("*[local-name()='ManagePackageVersionsCentrally']")
        if (-not $mpvc) { $mpvc = $xml.CreateElement('ManagePackageVersionsCentrally'); $null = $pg.AppendChild($mpvc) }
        $mpvc.InnerText = 'true'

        Test-DirectoryForFile $Path
        $xml.Save($Path)
    }

    function Write-PackagesProps {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][hashtable]$Packages,
            [ValidateSet('Alpha','None')][string]$Sort = 'Alpha'
        )
        $xml = New-Object System.Xml.XmlDocument
        $proj = $xml.CreateElement('Project'); $null = $xml.AppendChild($proj)
        $ig   = $xml.CreateElement('ItemGroup'); $null = $proj.AppendChild($ig)

        $keys = $Packages.Keys
        if ($Sort -eq 'Alpha') { $keys = $keys | Sort-Object }

        foreach ($k in $keys) {
            $ver  = $Packages[$k]
            $node = $xml.CreateElement('PackageVersion')
            $a1 = $xml.CreateAttribute('Include'); $a1.Value = $k
            $a2 = $xml.CreateAttribute('Version'); $a2.Value = $ver
            $null = $node.Attributes.Append($a1)
            $null = $node.Attributes.Append($a2)
            $null = $ig.AppendChild($node)
        }
        Test-DirectoryForFile $Path
        $xml.Save($Path)
    }

    function Remove-VersionsFromProject {
        param([Parameter(Mandatory)][string]$ProjectPath, [switch]$Backup)

        $original = Get-Content -LiteralPath $ProjectPath -Raw
        $xml = [xml]$original
        $changed = $false

        $refs = $xml.SelectNodes("//*[local-name()='PackageReference']")
        foreach ($r in $refs) {
            if ($r.Attributes['Version']) {
                $null = $r.Attributes.RemoveNamedItem('Version'); $changed = $true
            }
            $verNode = $r.SelectSingleNode("*[local-name()='Version']")
            if ($verNode) { $null = $r.RemoveChild($verNode); $changed = $true }
        }

        if ($changed) {
            if ($Backup) { Set-Content -LiteralPath ($ProjectPath + '.bak') -Value $original -Encoding UTF8 }
            $xml.Save($ProjectPath)
        }
        return $changed
    }

    function Read-ExistingPackagesProps {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        try {
            $xml = [xml](Get-Content -LiteralPath $Path -Raw)
            $nodes = $xml.SelectNodes("//*[local-name()='PackageVersion']")
            if (-not $nodes) { return $null }
            $map = [ordered]@{}
            foreach ($n in $nodes) {
                $inc = $n.Attributes['Include']?.Value
                $ver = $n.Attributes['Version']?.Value
                if ($inc -and $ver) { $map[$inc] = $ver }
            }
            if ($map.Count -gt 0) { return $map } else { return $null }
        } catch { return $null }
    }

    #endregion helpers

    #region main

    $paths = Resolve-RootAndDefaults -Solution $Solution -BuildPropsPath $BuildPropsPath -PackagesPropsPath $PackagesPropsPath
    $root  = $paths.Root
    $buildProps    = $paths.BuildPropsPath
    $packagesProps = $paths.PackagesPropsPath

    Write-Verbose ("Solution:           {0}" -f $paths.SolutionFull)
    Write-Verbose ("Root:               {0}" -f $root)
    Write-Verbose ("Build props path:   {0}" -f $buildProps)
    Write-Verbose ("Packages props path:{0}" -f $packagesProps)

    $projects = @(
        Resolve-SolutionProjects -SolutionFull $paths.SolutionFull -Root $root
    )
    if (-not $projects -or @($projects).Count -eq 0) {
        throw "No project files (.csproj/.vbproj/.fsproj) found in solution."
    }

    # Discover packages -> latest versions
    $packageMap = [ordered]@{}
    foreach ($proj in $projects) {
        if (-not (Test-Path -LiteralPath $proj)) { continue }
        foreach ($ref in (Get-PackageReferences -ProjectPath $proj)) {
            if (-not $ref.Include) { continue }
            if ([string]::IsNullOrWhiteSpace($ref.Version)) {
                if (-not $packageMap.Contains($ref.Include)) { $packageMap[$ref.Include] = $null }
                continue
            }
            if (-not $packageMap.Contains($ref.Include)) {
                $packageMap[$ref.Include] = $ref.Version
            } else {
                $existing = $packageMap[$ref.Include]
                if (-not $existing) { $packageMap[$ref.Include] = $ref.Version }
                else {
                    if ((Compare-NuGetVersion $existing $ref.Version) -lt 0) {
                        $packageMap[$ref.Include] = $ref.Version
                    }
                }
            }
        }
    }

    # drop those that never got a version
    $noVersion = @($packageMap.GetEnumerator() | Where-Object { -not $_.Value })
    foreach ($nv in $noVersion) { $packageMap.Remove($nv.Key) }

    # Idempotency: if none found in projects, seed from existing Directory.Packages.props
    if ($packageMap.Count -eq 0) {
        $seed = Read-ExistingPackagesProps -Path $packagesProps
        if ($seed) {
            $packageMap = $seed
        } else {
            throw "No PackageReference versions found in any project."
        }
    }

    # Write props files
    if ($PSCmdlet.ShouldProcess($buildProps, 'Write/Update Directory.Build.props')) {
        Write-BuildProps -Path $buildProps
    }
    if ($PSCmdlet.ShouldProcess($packagesProps, 'Write Directory.Packages.props')) {
        Write-PackagesProps -Path $packagesProps -Packages $packageMap -Sort $PackagesSort
    }

    # Strip versions in projects
    foreach ($proj in $projects) {
        if (-not (Test-Path -LiteralPath $proj)) { continue }
        if ($PSCmdlet.ShouldProcess($proj, 'Remove PackageReference versions')) {
            [void](Remove-VersionsFromProject -ProjectPath $proj -Backup:$Backup)
        }
    }

    [pscustomobject]@{
        Solution          = $paths.SolutionFull
        Root              = $root
        BuildPropsPath    = $buildProps
        PackagesPropsPath = $packagesProps
        ProjectCount      = @($projects).Count
        PackagesCount     = $packageMap.Count
        Packages          = $packageMap
    }

    #endregion main
}
