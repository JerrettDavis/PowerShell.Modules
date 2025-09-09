# PowerShell Modules

Custom PowerShell modules to make day‑to‑day tasks easier. This repo currently includes an XML utility module with safe, test‑backed helpers and a simple CI/CD pipeline.

## Modules

- Xml (module name: `JerrettDavis.Xml`)
	- Public functions:
		- `Add-XmlNode` – add a new node at an XPath.
		- `Update-XmlNode` – update node value/attributes (supports -All/-SingleNode/-PassThru).
		- `Remove-XmlNode` – remove node(s) by XPath (supports -SingleNode).
	- Private helpers:
		- `Get-JDXmlDocument` – robust XML loading.
		- `Save-JDXmlDocument` – gated save with ShouldProcess.
	- All public functions support ShouldProcess (-WhatIf/-Confirm).

## Quick start

Import the XML module directly from source:

```powershell
Import-Module -Force (Resolve-Path .\Xml\JerrettDavis.Xml.psm1)
```

Or, after publishing to your feed (see CI/CD below), install like any module:

```powershell
# Example for a private Azure Artifacts feed you’ve registered as 'MyFeed'
Install-Module -Name JerrettDavis.Xml -Repository MyFeed -Scope CurrentUser
```

## Usage examples

Add a node with value and attributes:

```powershell
Add-XmlNode -XmlFilePath '.\example.xml' -XPath '/root/parent' -NewNodeName 'child' `
						-NewNodeValue 'value' -Attributes @{ id = '1'; type = 'example' } -Confirm:$false
```

Update the first matching node’s value and attributes (default behavior):

```powershell
Update-XmlNode -FilePath '.\example.xml' -XPath '/root/parent/child' `
							 -NewValue 'updated' -NewAttributes @{ state = 'active' } -Confirm:$false
```

Update all matching nodes and verify expected current state first:

```powershell
Update-XmlNode -FilePath '.\example.xml' -XPath "//child[@type='example']" `
							 -TestAttributes @{ state = 'inactive' } -NewAttributes @{ state = 'active' } -All -Confirm:$false
```

Remove one node (enforce single match):

```powershell
Remove-XmlNode -XmlFilePath '.\example.xml' -XPath "/root/parent/child[@id='1']" -SingleNode -Confirm:$false
```

Tip: Use `-WhatIf` on any command to preview changes.

## Development

### Prerequisites

- PowerShell 5.1+ or PowerShell 7+
- Pester (tests are v5‑friendly)

### Run all tests from repo root

```powershell
./Run-Tests.ps1 -CI
```

By default this runs tests in `Xml/Tests` and `build/Tests`. Pass `-Paths` to customize.

### Build the module manifest (version and exports)

`build/build.ps1` updates a module’s manifest (ModuleVersion and FunctionsToExport) using the Public folder content:

```powershell
# Example for the XML module
./build/build.ps1 -ModuleName 'Xml\JerrettDavis.Xml' -BuildVersion '1.2.3'
```

Manifest placeholders expected and replaced during build:

```powershell
ModuleVersion     = '<ModuleVersion>'
FunctionsToExport = @('<FunctionsToExport>')
```

### CI/CD (Azure Pipelines)

- Pipeline: `azure-pipelines.yml`
- Helper script: `build/ci-discover-and-build.ps1`

The CI stage discovers modules (by `*.psd1`), builds them (per‑module `build/build.ps1` if present), and runs tests. The Publish stage (main/release branches) builds and publishes modules to an Azure Artifacts feed.

Key parameters/variables:

- `BuildVersion` – version propagated to module build (defaults to `$(Build.BuildNumber)`).
- `ModuleSearchPattern` – discovery pattern (default `*.psd1`).
- `PesterPath` – optional custom tests path (otherwise defaults to `Xml/Tests`).
- `FeedName`/`FeedUrl` – target feed; when only `FeedName` is provided, the script constructs the feed URL from the build env.

Requirements for publish:

- Enable “Allow scripts to access OAuth token” on the pipeline.
- Pass `$(System.AccessToken)` to the script environment (the pipeline YAML already wires this).

Local CI helper usage:

```powershell
# Discover, build, and run tests
./build/ci-discover-and-build.ps1 -RepoRoot (Get-Location).Path -RunTests -Version '1.2.3'

# Build and publish (requires Azure DevOps build env or PAT wiring)
./build/ci-discover-and-build.ps1 -RepoRoot (Get-Location).Path -Publish -FeedName 'YourFeed' -Version '1.2.3'
```

### Code coverage

You can collect Pester v5 code coverage via the CI helper:

```powershell
# Run tests with coverage for common paths and write artifacts to TestResults/Coverage
./build/ci-discover-and-build.ps1 -RunTests -CodeCoverage

# Customize coverage paths and output directory
./build/ci-discover-and-build.ps1 -RunTests -CodeCoverage `
	-CoveragePaths @('.\Xml\Public\*.ps1','.\Xml\Private\*.ps1') `
	-CoverageOutputDir '.\out\coverage'
```

Artifacts produced:
- `summary.txt` – human‑readable coverage info
- `pester-coverage.json` – raw coverage object
- `coveragePercent.txt` – numeric percentage (useful for gates/badges)

## Repository layout

```
PowerShell.Modules/
├─ Xml/
│  ├─ JerrettDavis.Xml.psd1            # Manifest (tokens replaced at build)
│  ├─ JerrettDavis.Xml.psm1            # Module loader (exports Public/*.ps1)
│  ├─ Public/                          # Public cmdlets
│  ├─ Private/                         # Private helpers
│  └─ Tests/                           # Pester tests for the Xml module
├─ build/
│  ├─ build.ps1                        # Manifest updater (version/exports)
│  └─ Tests/                           # Pester tests for build/CI
├─ azure-pipelines.yml                 # CI/CD pipeline
└─ Run-Tests.ps1                       # Root test runner
```

## Contributing

Pull requests welcome. Please include or update tests for any changes to public behavior. Use `./Run-Tests.ps1 -CI` to validate before submitting.
