# AtlassianPS Release Blueprint

This document is the canonical release blueprint for AtlassianPS PowerShell modules.
Module repositories may keep short local runbooks, but cross-repository release strategy belongs here.

## Goals

- Keep release workflows predictable across AtlassianPS modules.
- Reuse shared Standards primitives instead of copying release logic into each repository.
- Keep `CHANGELOG.md`, GitHub release bodies, and PSGallery manifest `PrivateData.PSData.ReleaseNotes` synchronized.
- Fail release-note and tag validation before publishing immutable PSGallery packages.
- Make workflow drift visible in tests.

## Version And Changelog Contract

Use one `v`-prefixed three-part version everywhere a release is identified.

| Artifact | Format | Example |
|----------|--------|---------|
| Git tag | `vX.Y.Z` | `v3.0.0` |
| Changelog heading | `## vX.Y.Z - YYYY-MM-DD` | `## v3.0.0 - 2026-05-10` |
| Module manifest | `X.Y.Z` | `ModuleVersion = '3.0.0'` |

Pre-release tags may append a prerelease label, for example `v3.1.0-beta`.
The module manifest keeps the numeric version in `ModuleVersion` and uses `PrivateData.PSData.Prerelease` for the prerelease label where needed.

The release notes parser preserves the full markdown body under the matching `##` heading until the next `##` heading.
Introductory paragraphs before `###` sections are supported and are included in both PSGallery and GitHub release notes.

## Required Continuous Release Flow

The default path is label-based continuous delivery from merged pull requests.
After a pull request with `release:patch`, `release:minor`, or `release:major` merges to `master`, the trusted `push` workflow should:

1. Check out the repository with full history and tags.
2. Resolve the merged pull request associated with the pushed commit.
3. Read the pull request release and changelog labels.
4. Compute the next `vX.Y.Z` tag from the latest stable semver tag and the release impact.
5. Create a generated `.changelog/<pr>.<impact>.<type>.md` fragment when the PR used a `changelog:*` label.
6. Run `prepare-release-changelog` to fold pending notes and fragments into the new version section.
7. Commit only the release-preparation changes back to `master`.
8. Run the normal build/test gate and `SetVersion` metadata preflight against the exact computed tag.
9. Create an annotated tag on the release-preparation commit and push the commit and tag together.
10. Build release notes from the committed `CHANGELOG.md` section.
11. Publish to PSGallery.
12. Create the GitHub release with the same release notes body.

`release:none` merges should stop after planning and must not publish.
The workflow should be serialized with concurrency so multiple release-labelled merges do not race the next-version calculation.

## Required Tag Release Flow

Keep a tag/manual release workflow as the recovery path for reruns and explicit operator-driven releases.

Release workflows should do these steps in order:

1. Check out the repository with full history.
2. Resolve and validate the annotated release tag with `resolve-release-tag`.
3. Download the CI `Release` artifact built from the tagged commit.
4. Set up PowerShell dependencies with `setup-powershell`.
5. Build `Release/release-notes.md` from `CHANGELOG.md` with `build-release-notes`.
6. Publish the module, with manifest release notes generated from the same changelog section.
7. Create the GitHub release with `body_path` pointing at `Release/release-notes.md`.

Release notes must be built before publishing.
If the changelog section is missing or empty, the workflow must fail before PSGallery receives the package.

## Required Shared Actions

Pin all Standards actions to the same released commit SHA and include a version comment.

```yaml
- name: Validate release tag
  id: release_ref
  uses: AtlassianPS/AtlassianPS.Standards/.github/actions/resolve-release-tag@<standards-sha> # v0.1.11

- uses: AtlassianPS/AtlassianPS.Standards/.github/actions/setup-powershell@<standards-sha> # v0.1.11

- uses: AtlassianPS/AtlassianPS.Standards/.github/actions/build-release-notes@<standards-sha> # v0.1.11
  id: release_notes
  with:
    release-version: ${{ steps.release_ref.outputs.release_tag }}
```

GitHub releases should use the generated file path:

```yaml
- name: Create Release and Upload Asset
  uses: softprops/action-gh-release@v3
  with:
    tag_name: ${{ steps.release_ref.outputs.release_tag }}
    name: ${{ steps.release_ref.outputs.release_tag }}
    body_path: ${{ steps.release_notes.outputs.release_notes_path }}
```

Do not use `MatteoCampinoti94/changelog-to-release` or repo-local changelog formatting configuration.
GitHub release notes and PSGallery manifest release notes should be the same source text, not independently formatted variants.

## Required Build Script Pattern

The publish path should use the Standards parser for manifest release notes.

```powershell
Task SetVersion {
    $releaseNotes = Get-AtlassianPSReleaseNotesFromChangelog `
        -ChangelogPath (Join-Path -Path $env:BHProjectPath -ChildPath 'CHANGELOG.md') `
        -ReleaseVersion $script:BuildInfo.VersionToPublish

    $null = Set-AtlassianPSModuleManifestVersion `
        -BuiltManifestPath $builtManifestPath `
        -ModuleName $env:BHProjectName `
        -VersionToPublish $VersionToPublish `
        -ReleaseNotes $releaseNotes
}
```

Keep repository build orchestration local.
Use Standards for small primitives and shared actions, not for broad module-specific release wrappers.

## Drift Guards

Each module should include guard tests that enforce the blueprint.
At minimum, test that:

- `Tools/build.requirements.psd1` pins `AtlassianPS.Standards` to the intended version.
- Every `AtlassianPS.Standards/.github/actions/*` workflow reference is pinned to a 40-character commit SHA.
- Every Standards action pin uses the same version comment as `Tools/build.requirements.psd1`.
- The release workflow uses `build-release-notes`.
- The release workflow uses `body_path: ${{ steps.release_notes.outputs.release_notes_path }}`.
- The release workflow builds release notes before publishing.
- The build script uses `Get-AtlassianPSReleaseNotesFromChangelog` for manifest release notes.
- The repository does not contain `changelog-to-release`, `.github/changelog.configuration.json`, or copied inline parser/write-file plumbing.

JiraPS is the reference implementation for these guard tests.
Future Standards work may consolidate the checks into a shared `Test-AtlassianPSReleaseBlueprint` command.

## Pull Request Release Intent

Module repositories should require each pull request to declare release intent before merge.
GitHub branch protection cannot require labels directly, so repositories should make a `Release Intent` workflow check required.

Use exactly one release label:

- `release:none` for changes that do not belong in release notes and should not affect release versioning.
- `release:patch` for bug fixes and other patch releases.
- `release:minor` for new backward-compatible functionality.
- `release:major` for breaking changes.

For user-facing changes, use exactly one changelog source: either one changelog label or one valid custom changelog fragment, not both.
Use a changelog label when the standard generated fragment text is enough:

- `changelog:added`
- `changelog:changed`
- `changelog:fixed`
- `changelog:removed`
- `changelog:deprecated`
- `changelog:security`
- `changelog:breaking`

`changelog:breaking` requires `release:major`.

Custom fragments must be named:

```text
.changelog/<pr-number>.<patch|minor|major>.<added|changed|fixed|removed|deprecated|security|breaking>.md
```

Example:

```text
.changelog/701.patch.fixed.md
```

Generated fragments should use this content format:

```markdown
* <PR Title> (#<PR number>, @<PR author>)
```

Example workflow:

```yaml
name: Release Intent

on:
  pull_request_target:
    types: [opened, edited, synchronize, reopened, ready_for_review, labeled, unlabeled]

permissions:
  contents: read
  pull-requests: read
  issues: write

jobs:
  validate:
    name: Release Intent
    runs-on: ubuntu-latest
    steps:
      - uses: AtlassianPS/AtlassianPS.Standards/.github/actions/validate-release-intent@<standards-sha>
```

The workflow intentionally runs on `pull_request_target` and must not check out or execute pull request code.
The shared action reads PR labels and changed file names through the GitHub API, then maintains a sticky PR comment when a human needs to fix labels or fragments.

Make the `Release Intent` job a required branch protection check.

## Migration Checklist

For each existing module repository:

1. Bump `Tools/build.requirements.psd1` to the current `AtlassianPS.Standards` version.
2. Pin all Standards workflow actions to the same release commit SHA.
3. Replace local release-tag scripts with `resolve-release-tag`.
4. Replace third-party or inline GitHub release-note generation with `build-release-notes`.
5. Remove `.github/changelog.configuration.json` when it only served the old changelog action.
6. Update `softprops/action-gh-release` to use `body_path` from the shared action output.
7. Replace local changelog parsers in build scripts with `Get-AtlassianPSReleaseNotesFromChangelog`.
8. Add or update drift guard tests.
9. Add the `Release Intent` workflow and make it a required check.
10. Update the local release runbook to link back to this blueprint.
11. Run local workflow syntax, guard tests, lint, build/test, and release metadata preflight before pushing.

## Release Preparation

Before creating a release tag, prepare the changelog section, run the module's normal build/test gate, and verify release metadata for the exact tag.

```yaml
- uses: AtlassianPS/AtlassianPS.Standards/.github/actions/prepare-release-changelog@<standards-sha>
  with:
    release-version: vX.Y.Z
```

This moves pending `## Unreleased` content and valid `.changelog/*.md` fragments into `## vX.Y.Z - YYYY-MM-DD`, then deletes the consumed fragments.
The generated release-notes file is written outside the repository by default; commit only `CHANGELOG.md` and consumed fragment deletions.
In the continuous release flow, the trusted workflow creates and commits these changes automatically after the labelled PR merges.
For manual/tag releases, review the generated changelog before opening the release-preparation PR.

```powershell
Invoke-Build -Task Build, Test
Invoke-Build -Task Build, SetVersion -VersionToPublish vX.Y.Z
```

If the second command cannot find a matching changelog section, do not tag the release.

## Common Mistakes

- Creating a non-annotated release tag.
- Tagging a commit that is not reachable from `origin/master`.
- Using `## X.Y.Z` in the changelog while tagging `vX.Y.Z`.
- Using two-part tags for one repo and three-part tags for another.
- Publishing with GitHub release notes generated from a different parser than PSGallery release notes.
- Publishing before building release notes from the changelog.
- Fixing GitHub release notes after PSGallery publish and assuming package metadata changed too.

Published PSGallery package metadata is immutable.
The release workflow must get release notes right before publishing.
