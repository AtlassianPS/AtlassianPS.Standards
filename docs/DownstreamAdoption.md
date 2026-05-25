# Downstream Adoption

Use this guide when moving a JiraPS-style module repository onto shared `AtlassianPS.Standards` blueprint helpers.

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
| Build task body that cleans, copies artifacts, compiles source, and updates exports | `Invoke-AtlassianPSModuleBuild` | Keep the Invoke-Build task declaration local. |
| Local publish dry-run checks | `Invoke-AtlassianPSModulePublishDryRun` | The helper validates the package archive contents. |
| Local `.env` parser | `Import-AtlassianPSDotEnvFile` | The helper emits names only, not secret values. |
| Local required integration variable validation | `Initialize-AtlassianPSIntegrationEnvironment` | Product-specific helpers should map environment variables into typed context objects. |
| Local file-level parallel Pester runner | `Invoke-AtlassianPSParallelPester` | Keep only a thin compatibility wrapper if existing workflows call the old script path. |
| Local test module import/cache bootstrap | `Initialize-AtlassianPSModuleTestEnvironment` | Keep product-specific test fixtures local. |
| Docker Compose integration lifecycle | `Invoke-AtlassianPSDockerIntegrationTrack` | Product-specific wait/provisioning scripts stay local. |

## Keep Local

Keep behavior local when it knows product semantics or test fixture details.

- Jira session creation and Jira Cloud/Data Center credential mapping.
- Jira issue, filter, version, user, or group fixture creation and cleanup.
- Confluence space/page fixture creation and cleanup.
- Product-specific wait/provisioning scripts such as `Wait-JiraServer.ps1` or `Wait-ConfluenceServer.ps1`.
- Repository-specific smoke tags, integration track names, and throttling decisions.

Tiny local assertion modules such as `Tools/BuildTools.psm1` should usually be removed during adoption rather than standardized.
Use direct `throw` statements or Standards validation helpers where possible.

## JiraPS Adoption Checklist

1. Bump `AtlassianPS.Standards` in `Tools/build.requirements.psd1` after the Standards release.
2. Replace duplicated build task bodies in `JiraPS.build.ps1` with `Invoke-AtlassianPSModuleBuild` and `Invoke-AtlassianPSModulePublishDryRun`.
3. Replace `Tests/Invoke-ParallelPester.ps1` with a wrapper around `Invoke-AtlassianPSParallelPester`, or update build tasks to call the Standards helper directly.
4. Replace generic portions of `Tests/Helpers/TestTools.ps1` with `Initialize-AtlassianPSModuleTestEnvironment`, `Resolve-AtlassianPSModuleSource`, and `Resolve-AtlassianPSProjectRoot`.
5. Keep Jira-specific helpers in `Tests/Helpers/IntegrationTestTools.ps1`, but replace its `.env` parsing and required-variable validation with Standards helpers.
6. Keep `Tools/Wait-JiraServer.ps1` local.
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
