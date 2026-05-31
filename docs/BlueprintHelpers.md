# Blueprint Primitives

`AtlassianPS.Standards` provides small helpers for repeated JiraPS-style build and test details.
Repository build scripts should stay readable: keep task orchestration in the repository and call these commands only for concrete operations.
For the cross-repository release strategy, see [ReleaseBlueprint.md](ReleaseBlueprint.md).

The module manifest sets `DefaultCommandPrefix = 'AtlassianPS'`.
Consumers call commands with the prefixed names, for example `Test-AtlassianPSModulePackage`.

## Helper Contracts

| Area | Helpers | Contract |
|------|---------|----------|
| Build output | `Copy-ModuleArtifacts`, `Join-ModuleSource` | Copy release artifacts and merge module source folders into the release `.psm1`. |
| Manifest and package validation | `Update-ModuleManifestExports`, `Set-ModuleManifestVersion`, `Get-ReleaseNotesFromChangelog`, `Update-ReleaseChangelog`, `New-ModulePackage`, `Test-ModulePackage` | Update manifest exports, set publish-time version and release notes, prepare changelog release sections, create the release zip, and validate the package contains the expected manifest. |
| Release intent | `Test-ReleaseIntent` | Validate PR release labels and changelog labels/fragments before merge. |
| External help | `Update-ExternalHelp`, `Remove-OrphanedExternalHelp` | Generate PlatyPS external help and remove generated help files that no longer have markdown sources. |
| Test bootstrap | `Resolve-ProjectRoot`, `Resolve-ModuleSource`, `Initialize-ModuleTestEnvironment` | Resolve repository/module paths and import the module under test for Pester. |
| Environment loading | `Import-DotEnvFile` | Load `.env` values into process-scoped environment variables without emitting secret values. |

## Readable Build Task Example

Prefer explicit task dependencies and concrete helper calls over a generic build wrapper.

```powershell
Task Build Clean, CopyBuildArtifacts, CompileModule, UpdateManifest

Task CopyBuildArtifacts {
    $null = Copy-AtlassianPSModuleArtifacts `
        -ProjectPath $env:BHProjectPath `
        -ModuleName $env:BHProjectName `
        -BuildOutputPath $env:BHBuildOutput `
        -AdditionalFiles @('CHANGELOG.md', 'README.md', 'LICENSE') `
        -IncludeTests
}

Task CompileModule {
    $releaseModulePath = Join-Path -Path $env:BHBuildOutput -ChildPath $env:BHProjectName
    $null = Join-AtlassianPSModuleSource -ReleaseModulePath $releaseModulePath
}

Task UpdateManifest {
    $null = Update-AtlassianPSModuleManifestExports `
        -SourceModulePath $env:BHModulePath `
        -BuiltManifestPath $script:BuildInfo.BuiltManifestPath `
        -ModuleName $env:BHProjectName
}
```

## Publish Dry Run

Package validation is intentionally two visible steps: create the package, then validate it.

```powershell
Task TestPublish Build, {
    $packagePath = New-AtlassianPSModulePackage `
        -BuildOutputPath $env:BHBuildOutput `
        -ModuleName $env:BHProjectName

    $null = Test-AtlassianPSModulePackage `
        -BuildOutputPath $env:BHBuildOutput `
        -ModuleName $env:BHProjectName `
        -PackagePath $packagePath
}
```

## Release Notes

Release builds should derive manifest release notes from the same `CHANGELOG.md` section used for the GitHub release body.
Use tag-form headings, for example `## v1.2.3`, and pass the validated release tag through the build.
Use the shared `build-release-notes` action in GitHub workflows so repositories do not copy PowerShell plumbing.

```yaml
- name: Build release notes from changelog
  id: release_notes
  uses: AtlassianPS/AtlassianPS.Standards/.github/actions/build-release-notes@<standards-sha>
  with:
    release-version: ${{ steps.release_ref.outputs.release_tag }}

- name: Create Release
  uses: softprops/action-gh-release@v3
  with:
    body_path: ${{ steps.release_notes.outputs.release_notes_path }}
```

```powershell
Task SetVersion {
    $releaseNotes = Get-AtlassianPSReleaseNotesFromChangelog `
        -ChangelogPath (Join-Path -Path $env:BHProjectPath -ChildPath 'CHANGELOG.md') `
        -ReleaseVersion $script:BuildInfo.VersionToPublish

    $null = Set-AtlassianPSModuleManifestVersion `
        -BuiltManifestPath $script:BuildInfo.BuiltManifestPath `
        -ModuleName $env:BHProjectName `
        -VersionToPublish $VersionToPublish `
        -ReleaseNotes $releaseNotes
}
```

`Get-AtlassianPSReleaseNotesFromChangelog` also accepts historical headings without the `v` prefix and dated headings like `## 1.2.3 - 2026-05-10`, so repositories can migrate existing changelogs without local parser code.

## Release Changelog Preparation

Release-preparation PRs should fold pending changelog entries and custom fragments into the next version section, then delete the consumed fragments.
Use `Update-AtlassianPSReleaseChangelog` instead of manually editing fragment files.

```powershell
Update-AtlassianPSReleaseChangelog `
    -ChangelogPath ./CHANGELOG.md `
    -ReleaseVersion v1.2.3
```

The helper creates `## v1.2.3 - YYYY-MM-DD` immediately after `## Unreleased`, moves any existing Unreleased body plus valid `.changelog/*.md` fragment contents into that section, and deletes only the consumed fragments.

Workflow-based preparation can use the matching composite action after checkout and dependency setup.
Commit the resulting `CHANGELOG.md` update and `.changelog` deletions in the release-preparation PR.

```yaml
- uses: AtlassianPS/AtlassianPS.Standards/.github/actions/prepare-release-changelog@<standards-sha>
  with:
    release-version: v1.2.3
```

## External Help

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

## Test Bootstrap

Use `Initialize-AtlassianPSModuleTestEnvironment` from Pester `BeforeAll` blocks when a repository only needs the standard source/release manifest resolution and module import.

```powershell
BeforeAll {
    Import-Module AtlassianPS.Standards
    $script:moduleToTest = Initialize-AtlassianPSModuleTestEnvironment `
        -ModuleName 'JiraPS' `
        -StartPath $PSScriptRoot
}
```

Use `Resolve-AtlassianPSProjectRoot` and `Resolve-AtlassianPSModuleSource` directly when a test needs only path resolution.

## Integration Tests

Keep integration orchestration local when it knows product semantics: Cloud/Data Center variable names, typed test contexts, Docker Compose service names, provisioning, fixture setup, and cleanup.

Use `Import-AtlassianPSDotEnvFile` as the shared primitive for local `.env` loading, then validate product-specific environment variables in the repository helper.
