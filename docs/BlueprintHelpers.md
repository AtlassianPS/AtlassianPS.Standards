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
| Manifest and package validation | `Update-ModuleManifestExports`, `Set-ModuleManifestVersion`, `Get-ReleaseNotesFromChangelog`, `New-ModulePackage`, `Test-ModulePackage` | Update manifest exports, set release metadata, create a local package zip, and validate it against the built module. |
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

The CI build job creates and validates `Release`, including the module directory and GitHub zip.
Build scripts keep explicit `Package` and `VerifyReleaseArtifact` tasks; they do not contain publishing
tasks or credentials. The trusted publisher passes the validated module directory to `Publish-Module`.

```powershell
Task VerifyReleaseArtifact Package, {
    $null = Test-AtlassianPSModulePackage `
        -BuildOutputPath $env:BHBuildOutput `
        -ModuleName $env:BHProjectName `
        -PackagePath $script:PackagePath
}
```

## Release Notes

Release builds should derive manifest release notes from the same `CHANGELOG.md` section used for the GitHub release body.
Use tag-form headings, for example `## v1.2.3`, and pass the validated release tag through the build.
Use the shared `build-release-notes` action in secretless candidate CI so repositories do not copy PowerShell plumbing. Upload its output with the final candidate for the publishing job.

```yaml
- name: Build release notes from changelog
  id: release_notes
  uses: AtlassianPS/AtlassianPS.Standards/.github/actions/build-release-notes@<standards-sha>
  with:
    release-version: ${{ steps.candidate.outputs.release_tag }}
```

After the publisher downloads the candidate, use the uploaded file directly:

```yaml
- name: Create Release
  uses: softprops/action-gh-release@3d0d9888cb7fd7b750713d6e236d1fcb99157228 # v3
  with:
    body_path: ./Release/release-notes.md
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

Release automation should fold pending changelog entries and custom fragments into the next version section, then delete the consumed fragments.
Use the `prepare-release-changelog` composite action instead of exporting another module helper for GitHub-only release mechanics.
In the continuous release workflow, commit the resulting `CHANGELOG.md` update and `.changelog` deletions directly to `master` after a release-labelled PR merges.
Automatic continuous release runs should listen only for completed `CI` workflows on `master`; keep manual dispatch available for unreleased changes already on `master`.
Commit the source module manifest version in the release metadata commit. Stamp release notes only into the final artifact in secretless candidate CI, then package and validate it before upload; the source manifest keeps release notes empty and the publisher does not rebuild.
For manual release preparation, commit source version and changelog before tagging the release.

```yaml
- uses: AtlassianPS/AtlassianPS.Standards/.github/actions/prepare-release-changelog@<standards-sha>
  with:
    release-version: v1.2.3
```

The action creates `## v1.2.3 - YYYY-MM-DD` immediately after `## Unreleased`, moves any existing Unreleased body plus valid `.changelog/*.md` fragment contents into that section, groups typed fragments under standard release-note headings, consolidates duplicate standard headings, and deletes only the consumed fragments. Fragment files should contain list items without their own `###` heading because the filename type supplies the heading.
By default, the generated release-notes output file is written under the runner temp directory so release-preparation PRs only need to commit `CHANGELOG.md` and `.changelog` deletions.

Use the `plan-merged-release` composite action from trusted `push` workflows to resolve a merged PR's release labels, compute the next stable semver tag, and generate a standard fragment when the PR used a `changelog:*` label.
Grant `issues: read` to the workflow that calls it because GitHub serves pull request labels from the issues labels API.
It does not publish by itself; the shared `module_release.yml` workflow owns metadata commits, release validation, annotated tags, PSGallery publication, and GitHub releases.

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
