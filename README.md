# AtlassianPS.Standards

`AtlassianPS.Standards` is a shared toolbag module that ships the AtlassianPS PSScriptAnalyzer baseline and reusable build helpers for AtlassianPS repositories.

Exported helpers cover:

- analyzer settings sync and lint orchestration (`Sync-ScriptAnalyzerSettings`, `Invoke-Lint`)
- build environment bootstrap and diagnostics (`Initialize-BuildEnvironment`, `Write-BuildInfo`)
- build output orchestration (`Copy-ModuleArtifacts`, `Join-ModuleSource`, `Invoke-ModuleBuild`)
- manifest and release helpers (`Update-ModuleManifestExports`, `Set-ModuleManifestVersion`, `New-ModulePackage`, `Test-ModulePackage`, `Invoke-ModulePublishDryRun`, `Publish-ModuleRelease`)
- help generation helpers (`Update-ExternalHelp`, `Remove-OrphanedExternalHelp`)
- Pester orchestration (`Invoke-ModuleTests`, `Invoke-ParallelPester`)
- integration-test helpers (`Import-DotEnvFile`, `Initialize-IntegrationEnvironment`, `Invoke-DockerIntegrationTrack`)
- dependency bootstrap and maintenance (`Install-DependencyRequirement`, `Update-DependencyReference`)

## Usage

```powershell
Import-Module AtlassianPS.Standards
$settingsPath = Sync-AtlassianPSScriptAnalyzerSettings -DestinationPath ./PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path ./MyModule -Settings $settingsPath -Recurse
```

The module manifest sets `DefaultCommandPrefix = 'AtlassianPS'`, so consumers can call prefixed commands without the function names carrying that infix in source.

## Blueprint Helpers

These helpers are the shared implementation behind the JiraPS blueprint build and test workflow.
Downstream repositories should keep their Invoke-Build task names local, then delegate repeated task bodies to these commands.

### Module Build

Use `Invoke-AtlassianPSModuleBuild` inside a repository `Build` task to run the common build sequence.
It can clean output, generate external help, remove stale generated help, copy module artifacts, compile `Public/` and `Private/` source into the release `.psm1`, and update manifest exports.

```powershell
Task Build {
    $null = Invoke-AtlassianPSModuleBuild `
        -ProjectPath $env:BHProjectPath `
        -ModuleName $env:BHProjectName `
        -BuildOutputPath $env:BHBuildOutput `
        -BuiltManifestPath $script:BuildInfo.BuiltManifestPath `
        -AdditionalFiles @('CHANGELOG.md', 'README.md', 'LICENSE') `
        -IncludeTests `
        -GenerateExternalHelp `
        -Clean
}
```

Keep product-specific build steps before or after this call in the repository build file.
For repositories with unusual help layouts, pass `-AboutTopicRelativePath` or `-CommandHelpRelativePath` instead of copying the whole help-generation block.

### Publish Dry Run

Use `Invoke-AtlassianPSModulePublishDryRun` in CI to validate the release package path without publishing to PowerShell Gallery.
The helper packages the built module when no package path is supplied and validates the release directory, manifest, package archive, manifest name, and manifest version.

```powershell
Task TestPublish Build, {
    $null = Invoke-AtlassianPSModulePublishDryRun `
        -BuildOutputPath $env:BHBuildOutput `
        -ModuleName $env:BHProjectName
}
```

### External Help

Use `Update-AtlassianPSExternalHelp` and `Remove-AtlassianPSOrphanedExternalHelp` directly when a repository cannot use the full module build helper.
The help generator wraps the PlatyPS v1 behavior expected by AtlassianPS modules, including nested MAML flattening and MAML metadata repair for aliases, pipeline input, default values, and examples.

```powershell
Update-AtlassianPSExternalHelp `
    -DocsPath "$env:BHProjectPath/docs" `
    -ModulePath $env:BHModulePath `
    -ModuleName $env:BHProjectName

Remove-AtlassianPSOrphanedExternalHelp `
    -DocsPath "$env:BHProjectPath/docs" `
    -ModulePath $env:BHModulePath `
    -ModuleName $env:BHProjectName
```

### Integration Environment

Use `Initialize-AtlassianPSIntegrationEnvironment` to centralize `.env` loading, deployment-track selection, and required variable validation.
Repository-specific helpers should map the returned values into product-specific test context objects.

```powershell
$testEnv = Initialize-AtlassianPSIntegrationEnvironment `
    -TrackEnvironmentVariableName 'CI_JIRA_TYPE' `
    -DefaultTrack 'Cloud' `
    -DotEnvPath (Join-Path $env:BHProjectPath '.env') `
    -DotEnvExcludeName @('JIRA_TEST_PROJECT', 'JIRA_TEST_ISSUE') `
    -RequiredVariableByTrack @{
        Cloud  = @('JIRA_CLOUD_URL', 'JIRA_CLOUD_USERNAME', 'JIRA_CLOUD_PASSWORD')
        Server = @('CI_JIRA_URL', 'CI_JIRA_ADMIN', 'CI_JIRA_ADMIN_PASSWORD')
    }
```

Use `-WarnOnly` in Pester discovery helpers that should self-skip when local credentials are absent.
Use strict mode in build tasks that should fail fast when CI configuration is incomplete.

### Parallel Pester

Use `Invoke-AtlassianPSParallelPester` for file-level integration test parallelism.
It uses `Start-ThreadJob` on PowerShell 7 with per-file timeouts, falls back to sequential execution on Windows PowerShell 5.1, prints failed and skipped test details, and can merge per-file NUnit XML into one result file.

```powershell
Invoke-AtlassianPSParallelPester `
    -Path './Tests/Integration' `
    -Tag 'Integration' `
    -ThrottleLimit 4 `
    -Output Detailed `
    -OutputPath 'Test-Integration.xml' `
    -SuiteName 'JiraPS Integration Tests'
```

### Docker Integration Track

Use `Invoke-AtlassianPSDockerIntegrationTrack` for Docker Compose-backed Data Center or Server integration tracks.
Product-specific wait/provisioning remains in repo scripts such as `Wait-JiraServer.ps1` or `Wait-ConfluenceServer.ps1`.

```powershell
Invoke-AtlassianPSDockerIntegrationTrack `
    -ComposeFile (Join-Path $env:BHProjectPath 'docker-compose.yml') `
    -ServiceName 'jira' `
    -WaitScriptPath (Join-Path $env:BHProjectPath 'Tools/Wait-JiraServer.ps1') `
    -EnvironmentDefault @{
        CI_JIRA_TYPE = 'Server'
        CI_JIRA_URL  = 'http://localhost:2990/jira'
    } `
    -TestScriptBlock {
        Invoke-AtlassianPSParallelPester `
            -Path './Tests/Integration' `
            -Tag 'Server' `
            -ThrottleLimit 2 `
            -OutputPath 'Test-Integration.xml'
    }
```

The helper captures service logs on failure and tears the stack down with `docker compose down -v` unless `-SkipTeardown` is supplied.

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

Tag-based CD runs on `v*` tags and will:

1. Build the module.
2. Publish to PowerShell Gallery (when `PSGALLERY_API_KEY` is configured).
3. Create a GitHub release with a zipped module artifact.

The source manifest intentionally uses a major/minor `ModuleVersion` (`x.y`) as a maintenance baseline. Release tags (`vX.Y.Z`) provide the full semantic version, and the publish pipeline stamps that exact tag version into the built manifest.
Update `CHANGELOG.md` before cutting a release tag so both GitHub and PSGallery release metadata reflect the shipped changes. Publish now derives PSGallery release notes from the matching changelog version section and fails if that section is missing or empty.
