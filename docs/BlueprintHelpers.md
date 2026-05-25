# Blueprint Helpers

The blueprint helpers centralize repeatable build, test, release, and integration-test orchestration used by AtlassianPS module repositories.
Downstream repositories should keep their Invoke-Build task declarations local, then delegate repeated task bodies to these commands.

## Helper Contracts

| Area | Helpers | Contract |
|------|---------|----------|
| Module build | `Invoke-ModuleBuild` | Runs the common build sequence: optional clean, optional external help generation, artifact copy, source merge, and manifest export update. |
| Publish validation | `Invoke-ModulePublishDryRun`, `Test-ModulePackage` | Creates or validates a package without publishing and verifies the package archive contains the expected manifest. |
| External help | `Update-ExternalHelp`, `Remove-OrphanedExternalHelp` | Generates PlatyPS external help and removes generated help files that no longer have markdown sources. |
| Parallel tests | `Invoke-ParallelPester` | Runs test files in parallel on PowerShell 7, sequentially on Windows PowerShell 5.1, and optionally merges NUnit XML results. |
| Test bootstrap | `Resolve-ProjectRoot`, `Resolve-ModuleSource`, `Initialize-ModuleTestEnvironment` | Resolves repository/module paths and imports the module under test only when source files changed. |
| Integration environment | `Import-DotEnvFile`, `Initialize-IntegrationEnvironment` | Loads `.env`, selects an integration track, validates required variables, and avoids emitting secret values. |
| Docker integration | `Invoke-DockerIntegrationTrack` | Owns Docker Compose lifecycle, wait/provisioning script invocation, failure log capture, and teardown. |

The module manifest sets `DefaultCommandPrefix = 'AtlassianPS'`.
Consumers call these commands with the prefixed names, for example `Invoke-AtlassianPSModuleBuild`.

## Module Build

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

## Publish Dry Run

Use `Invoke-AtlassianPSModulePublishDryRun` in CI to validate the release package path without publishing to PowerShell Gallery.
The helper packages the built module when no package path is supplied and validates the release directory, manifest, package archive, manifest name, and manifest version.

```powershell
Task TestPublish Build, {
    $null = Invoke-AtlassianPSModulePublishDryRun `
        -BuildOutputPath $env:BHBuildOutput `
        -ModuleName $env:BHProjectName
}
```

## External Help

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

## Integration Environment

Use `Initialize-AtlassianPSIntegrationEnvironment` to centralize `.env` loading, deployment-track selection, and required variable validation.
Repository-specific helpers should read validated environment variables directly and map them into product-specific test context objects.
The helper intentionally does not return secret values.

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

## Parallel Pester

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

If a repository keeps a compatibility script at `Tests/Invoke-ParallelPester.ps1`, reduce it to a wrapper.

```powershell
#requires -Module AtlassianPS.Standards
[CmdletBinding()]
param(
    [string[]]$Path = './Tests/Integration/',
    [int]$ThrottleLimit = 4,
    [string[]]$Tag,
    [string[]]$ExcludeTag,
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Normal',
    [string]$OutputPath
)

$projectRoot = Resolve-AtlassianPSProjectRoot -StartPath $PSScriptRoot

Invoke-AtlassianPSParallelPester @PSBoundParameters `
    -ProjectRoot $projectRoot `
    -EnvironmentFilePath (Join-Path -Path $projectRoot -ChildPath '.env')
```

## Test Bootstrap

Use `Initialize-AtlassianPSModuleTestEnvironment` from Pester `BeforeAll` blocks instead of carrying repo-local copies of module import/cache helpers.
It resolves the source or release manifest, computes a source fingerprint, and reloads the module only when the on-disk module changed.

```powershell
BeforeAll {
    Import-Module AtlassianPS.Standards
    $script:moduleToTest = Initialize-AtlassianPSModuleTestEnvironment `
        -ModuleName 'JiraPS' `
        -StartPath $PSScriptRoot
}
```

Use `Resolve-AtlassianPSProjectRoot` and `Resolve-AtlassianPSModuleSource` directly when a test needs only path resolution.

## Docker Integration Track

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
