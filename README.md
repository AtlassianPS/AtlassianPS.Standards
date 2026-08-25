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
Reusable CI guidance lives in [`docs/CIBlueprint.md`](docs/CIBlueprint.md).
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

Use `Tools/update.dependencies.ps1` to refresh pinned dependency versions in `Tools/build.requirements.psd1` and `AtlassianPS.Standards.psd1`. Updates stay within the currently pinned major version by default; use `Update-AtlassianPSDependencyReference -AllowMajorVersionUpgrade` for an intentional major upgrade. Lookup errors fail fast unless an explicit non-blocking/manual run uses `-AllowLookupFailure`.

## Build, Lint, Test

```powershell
Invoke-Build -Task Lint, Build, Test
```

## Release

Label-based CD runs after release-labelled pull requests merge to `master`.
It computes the next semantic version from reviewed `release:*` intent, prepares `CHANGELOG.md`, stamps the source manifest version, and pushes one release-metadata commit with a short-lived GitHub App token.
Secretless CI stamps and packages the `Release` artifact before the platform tests consume it. The publishing job downloads that immutable artifact from the exact successful CI run and publishes its module directory with `Publish-Module`, without checking out or rebuilding repository code.
Release workflows read the organization variable `ATLASSIANPS_RELEASE_APP_CLIENT_ID` and the organization secrets `ATLASSIANPS_RELEASE_APP_PRIVATE_KEY`, `PSGALLERY_API_KEY`, and `HOMEPAGE_PAT`.

The continuous release workflow will:

1. Build, test, stamp, package, and validate the release candidate without publishing credentials.
2. Create an immutable annotated tag and publish the candidate module to PowerShell Gallery.
3. Create a GitHub release with the candidate archive and notify the project website.

The source manifest may start a development cycle on a major/minor maintenance baseline, but release-preparation commits stamp the exact `vX.Y.Z` release version before tagging.
Publish derives PSGallery release notes from the matching changelog version section and fails if that section is missing or empty.
Transient failures use GitHub's failed-job rerun. Lasting failures are fixed through a reviewed PR and released as the next version; the pipeline has no historical recovery mode.
