# Downstream Adoption

Use this guide when moving a JiraPS-style module repository onto shared `AtlassianPS.Standards` primitives.

## Migration Order

1. Release a Standards version that contains the helper needed by the downstream repository.
2. Bump the downstream repository's `AtlassianPS.Standards` requirement to that released version.
3. Replace local helper implementations with calls to Standards helpers.
4. Keep product-specific setup, provisioning, and fixtures in the product repository.
5. Run the downstream repository's local build, package dry-run, and integration checks.

Do not wire a downstream repository to unreleased Standards helpers.

## Replace Local Implementations

| Local pattern | Replace with | Notes |
|---------------|--------------|-------|
| Build artifact copy | `Copy-AtlassianPSModuleArtifacts` | Keep task orchestration in the repository build script. |
| Module source compilation | `Join-AtlassianPSModuleSource` | Keep the `CompileModule` task local and readable. |
| Manifest export update | `Update-AtlassianPSModuleManifestExports` | Keep the `UpdateManifest` task local and readable. |
| Local publish dry-run checks | `New-AtlassianPSModulePackage`, `Test-AtlassianPSModulePackage` | Keep package creation and validation as visible steps. |
| Local `.env` parser | `Import-AtlassianPSDotEnvFile` | The helper emits names only, not secret values. |
| Local test module import/cache bootstrap | `Initialize-AtlassianPSModuleTestEnvironment` | Keep product-specific test fixtures local. |

## Keep Local

Keep behavior local when it knows product semantics or test fixture details.

- Jira session creation and Jira Cloud/Data Center credential mapping.
- Jira issue, filter, version, user, or group fixture creation and cleanup.
- Confluence space/page fixture creation and cleanup.
- Product-specific wait/provisioning scripts such as `Wait-JiraServer.ps1` or `Wait-ConfluenceServer.ps1`.
- Repository-specific smoke tags, integration track names, and throttling decisions.
- File-level parallel Pester orchestration, unless it is later extracted as a separately reviewed, proven primitive.
- Docker Compose lifecycle orchestration.
- Required integration variable validation when the variables describe product-specific Cloud/Data Center semantics.

Tiny local assertion modules such as `Tools/BuildTools.psm1` should usually be removed during adoption rather than standardized.
Use direct `throw` statements or Standards validation helpers where possible.

## JiraPS Adoption Checklist

1. Bump `AtlassianPS.Standards` in `Tools/build.requirements.psd1` after the Standards release.
2. Replace duplicated build task internals with `Copy-AtlassianPSModuleArtifacts`, `Join-AtlassianPSModuleSource`, and `Update-AtlassianPSModuleManifestExports`, while keeping task dependencies explicit.
3. Replace publish dry-run internals with `New-AtlassianPSModulePackage` followed by `Test-AtlassianPSModulePackage`.
4. Replace generic portions of `Tests/Helpers/TestTools.ps1` with `Initialize-AtlassianPSModuleTestEnvironment`, `Resolve-AtlassianPSModuleSource`, and `Resolve-AtlassianPSProjectRoot` only if the result is simpler than the local helper.
5. Keep Jira-specific helpers in `Tests/Helpers/IntegrationTestTools.ps1`, but replace only its `.env` parser with `Import-AtlassianPSDotEnvFile` if doing so reduces code.
6. Keep `Tests/Invoke-ParallelPester.ps1` and `Tools/Wait-JiraServer.ps1` local.
7. Run `Invoke-Build -Task Build, Test`.
8. Run `Invoke-Build -Task Clean, TestPublish`.
9. Run Cloud and Server integration tracks before broadening adoption to other repositories.

## Validation Commands

Use the downstream repository's standard validation commands after adoption.

```powershell
Invoke-Build -Task Build, Test
Invoke-Build -Task Clean, TestPublish
Invoke-Build -Task TestIntegration
Invoke-Build -Task TestIntegrationServer
```

The exact integration commands can differ by product repository.
Use the product repository's `AGENTS.md` and workflow documentation as the source of truth.
