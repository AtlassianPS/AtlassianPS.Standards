# AtlassianPS.Standards

`AtlassianPS.Standards` is a minimal shared module that ships the AtlassianPS PSScriptAnalyzer baseline and exposes a single helper function:

- `Get-AtlassianPSScriptAnalyzerSettingsPath`

## Usage

```powershell
Import-Module AtlassianPS.Standards
$settingsPath = Get-AtlassianPSScriptAnalyzerSettingsPath
Invoke-ScriptAnalyzer -Path ./MyModule -Settings $settingsPath -Recurse
```

## Repository Layout

- `AtlassianPS.Standards/` module source
- `Tests/` Pester tests
- `Tools/` dependency bootstrap scripts
- `.github/workflows/` CI/CD pipelines
- `AtlassianPS.Standards.build.ps1` Invoke-Build entrypoint

## Setup

```powershell
./Tools/setup.ps1
```

## Build, Lint, Test

```powershell
Invoke-Build -Task Lint, Build, Test
```

## Release

Tag-based CD runs on `v*` tags and will:

1. Build the module.
2. Publish to PowerShell Gallery (when `PSGALLERY_API_KEY` is configured).
3. Create a GitHub release with a zipped module artifact.
