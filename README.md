# AtlassianPS.Standards

`AtlassianPS.Standards` is a shared toolbag module that ships the AtlassianPS PSScriptAnalyzer baseline and reusable build helpers for AtlassianPS repositories.

Exported helpers cover:

- analyzer settings lookup, sync, and lint orchestration (`Get-ScriptAnalyzerSettingsPath`, `Sync-ScriptAnalyzerSettings`, `Invoke-Lint`)
- build environment bootstrap/info (`Initialize-BuildEnvironment`, `Get-BuildEnvironmentInfo`, `Write-BuildInfo`)
- build output orchestration (`Copy-ModuleArtifacts`, `Join-ModuleSource`)
- manifest and release helpers (`Update-ModuleManifestExports`, `Set-ModuleManifestVersion`, `New-ModulePackage`, `Publish-ModuleRelease`)
- Pester orchestration (`Invoke-ModuleTests`)

## Usage

```powershell
Import-Module AtlassianPS.Standards
$settingsPath = Sync-AtlassianPSScriptAnalyzerSettings -DestinationPath ./PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path ./MyModule -Settings $settingsPath -Recurse
```

The module manifest sets `DefaultCommandPrefix = 'AtlassianPS'`, so consumers can call prefixed commands without the function names carrying that infix in source.
Compatibility helpers (`Get-BuildEnvironmentInfo`, `Get-ScriptAnalyzerSettingsPath`) remain exported for downstream build scripts.

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

`setup.ps1` installs the union of runtime dependencies from `AtlassianPS.Standards.psd1` (`RequiredModules`) and build-only dependencies from `Tools/build.requirements.psd1`.

## Build, Lint, Test

```powershell
Invoke-Build -Task Lint, Build, Test
```

## Release

Tag-based CD runs on `v*` tags and will:

1. Build the module.
2. Publish to PowerShell Gallery (when `PSGALLERY_API_KEY` is configured).
3. Create a GitHub release with a zipped module artifact.
