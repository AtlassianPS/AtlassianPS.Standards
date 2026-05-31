# AtlassianPS.Standards

`AtlassianPS.Standards` is a shared toolbag module that ships the AtlassianPS PSScriptAnalyzer baseline and reusable build helpers for AtlassianPS repositories.

Exported helpers cover:

- analyzer settings sync and lint orchestration (`Sync-ScriptAnalyzerSettings`, `Invoke-Lint`)
- build environment bootstrap and diagnostics (`Initialize-BuildEnvironment`, `Write-BuildInfo`)
- build output helpers (`Copy-ModuleArtifacts`, `Join-ModuleSource`)
- manifest and release helpers (`Update-ModuleManifestExports`, `Set-ModuleManifestVersion`, `New-ModulePackage`, `Test-ModulePackage`)
- help generation helpers (`Update-ExternalHelp`, `Remove-OrphanedExternalHelp`)
- Pester orchestration (`Invoke-ModuleTests`)
- test bootstrap helpers (`Resolve-ProjectRoot`, `Resolve-ModuleSource`, `Initialize-ModuleTestEnvironment`)
- integration-test helpers (`Import-DotEnvFile`)
- dependency bootstrap and maintenance (`Install-DependencyRequirement`, `Update-DependencyReference`)

## Usage

```powershell
Import-Module AtlassianPS.Standards
$settingsPath = Sync-AtlassianPSScriptAnalyzerSettings -DestinationPath ./PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path ./MyModule -Settings $settingsPath -Recurse
```

The module manifest sets `DefaultCommandPrefix = 'AtlassianPS'`, so consumers can call prefixed commands without the function names carrying that infix in source.

## Blueprint Primitives

Blueprint primitives are small shared operations behind the JiraPS blueprint build and test workflow.
They cover artifact copy, source merge, package validation, external help generation, test bootstrap, and `.env` loading.
Repository build scripts should keep task orchestration local and readable.

Detailed contracts and examples live in [`docs/BlueprintHelpers.md`](docs/BlueprintHelpers.md).
Downstream migration guidance lives in [`docs/DownstreamAdoption.md`](docs/DownstreamAdoption.md).
Release flow guidance lives in [`docs/ReleaseBlueprint.md`](docs/ReleaseBlueprint.md).

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

Use `Tools/update.dependencies.ps1` to refresh pinned dependency versions in `Tools/build.requirements.psd1` and `AtlassianPS.Standards.psd1`. The default behavior is fail-fast on lookup errors; use `Update-AtlassianPSDependencyReference -AllowLookupFailure` only for explicit non-blocking/manual update runs.

## Build, Lint, Test

```powershell
Invoke-Build -Task Lint, Build, Test
```

## Release

Label-based CD runs after release-labelled pull requests merge to `master`.
It computes the next semantic version from the merged PR's `release:*` label, prepares `CHANGELOG.md`, validates the release metadata, creates an annotated tag, publishes to PowerShell Gallery, and creates the GitHub release from the same changelog section.

Tag-based release remains available on `v*` tags and manual dispatch for recovery or explicit operator-driven reruns.
Both release paths will:

1. Build the module.
2. Publish to PowerShell Gallery (when `PSGALLERY_API_KEY` is configured).
3. Create a GitHub release with a zipped module artifact.

The source manifest intentionally uses a major/minor `ModuleVersion` (`x.y`) as a maintenance baseline. Release tags (`vX.Y.Z`) provide the full semantic version, and the publish pipeline stamps that exact tag version into the built manifest.
Publish derives PSGallery release notes from the matching changelog version section and fails if that section is missing or empty.
