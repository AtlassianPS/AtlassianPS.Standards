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
After CI succeeds on a normal merged pull request with `release:patch`, `release:minor`, or `release:major`, the trusted `workflow_run` workflow should:

1. Check out the repository with full history and tags.
2. Resolve the merged pull request associated with the pushed commit.
3. Read the pull request release and changelog labels.
4. Compute the next `vX.Y.Z` tag from the latest stable semver tag and the release impact.
5. Create a generated `.changelog/<pr>.<impact>.<type>.md` fragment when the PR used a `changelog:*` label.
6. Run `prepare-release-changelog` to fold pending notes and fragments into the new version section.
7. Stamp only the release version into the source module manifest; release notes stay empty in the committed source.
8. Commit the release metadata changes directly to `master`.
9. Let CI build and test the bot-authored release metadata commit (the built artifact inherits the stamped version).
10. Download the CI `Release` artifact from that exact commit.
11. Build release notes from the committed `CHANGELOG.md` section.
12. Run `Invoke-Build -Task SetVersion ... -VerifyPublishedRelease` to populate release notes into the tested artifact and verify its version, without rebuilding the package.
13. Package and validate the final artifact, including manifest version, release notes, and archive contents.
14. Create an annotated tag on the tested release metadata commit.
15. Publish the verified module artifact to PSGallery.
16. Create the GitHub release with the same release notes body.
17. Notify the website to update its module submodule.

`release:none` merges should stop after planning and must not publish.
The workflow should be serialized with concurrency so multiple release-labelled merges do not race the next-version calculation.
Use a GitHub App or fine-grained automation token, for example `ATLASSIANPS_RELEASE_BOT_TOKEN`, when committing release metadata and creating annotated tags. `GITHUB_TOKEN` pushes do not trigger the required follow-up CI workflow, so they cannot drive this CD flow.

`master` must reject direct pushes before enabling release publishing. The publish workflow identifies release metadata by trusted workflow provenance and commit format; without branch protection, a direct writer can imitate that format. Protect `v*` tags from mutation and deletion.

When unreleased changes already exist on `master` without an associated merged release-labelled PR, use the manual `workflow_dispatch` input on `continuous_release.yml` and choose the release impact for the whole bucket.
Manual dispatch must still check out `master`, not the arbitrary ref selected in the GitHub UI.
The manual path does not generate a PR-title changelog fragment; it releases the existing `## Unreleased` body and any existing `.changelog/*.md` fragments.
For prereleases, enter `alpha`, `beta`, `rc`, or a numbered form like `rc-2` in the manual `prerelease` input.
The generated tag and changelog section use forms like `vX.Y.Z-alpha`, `vX.Y.Z-beta`, `vX.Y.Z-rc`, or `vX.Y.Z-rc-2`; `Set-AtlassianPSModuleManifestVersion` writes the manifest `PrivateData.PSData.Prerelease` label, and the GitHub release is marked as a prerelease.

## Release Recovery

Do not keep a separate tag-triggered release workflow unless it is intentionally idempotent across already-created tags, PSGallery packages, GitHub releases, uploaded assets, and website notifications.
The default AtlassianPS release path has one publishing workflow: `continuous_release.yml`.
If a release fails after the metadata commit, rerun `continuous_release.yml` with `recovery_tag` set to the existing release tag. Recovery requires that tag to identify a commit reachable from `master`, locates successful CI for that commit, rebuilds and validates its package, and skips PSGallery only when exact module version already exists. It then reconciles GitHub release asset and website notification.
Do not use recovery for a tag that lacks successful CI or points outside `master`; investigate and repair source state first.

### Recovery Runbook

Use recovery only for a partial release: an existing release-preparation commit and tag, but one or more publish stages did not finish. It is not a replacement for the normal manual release path.

1. Inspect the release tag, its commit, the matching `master` CI run, PSGallery, GitHub release, release asset, and website dispatch state.
2. Confirm the tag is annotated and its commit is reachable from `origin/master`.
3. Confirm successful CI produced the `Release` artifact for that exact commit.
4. Confirm `CHANGELOG.md` has a non-empty section matching the tag and source manifest has matching numeric version.
5. Dispatch `Continuous Release` from `master` with only `recovery_tag` set to that tag, for example `v1.2.3`. Leave `release_impact` and `prerelease` empty.
6. Monitor the run. It rebuilds release notes, validates package version/notes/archive, verifies or creates the tag, publishes only when PSGallery lacks that exact version, then creates or updates GitHub release asset and sends stable-release website notification.
7. Verify PSGallery version, annotated tag target, GitHub release body and asset, and website update. Record any intentionally skipped downstream stage.

Never delete, retag, or republish an existing PSGallery version to recover a release. If provenance checks fail, stop and repair the release metadata through a normal reviewed change.

## Required Shared Actions

Pin all Standards actions to the same released commit SHA and include a version comment. The release
workflow consumes these Standards actions: `setup-powershell`, `plan-merged-release`,
`prepare-release-changelog`, `commit-release-metadata`, `create-release-tag`, `resolve-release-tag`, and
`build-release-notes`.

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
  uses: softprops/action-gh-release@3d0d9888cb7fd7b750713d6e236d1fcb99157228 # v3
  with:
    tag_name: ${{ steps.release_ref.outputs.release_tag }}
    name: ${{ steps.release_ref.outputs.release_tag }}
    body_path: ${{ steps.release_notes.outputs.release_notes_path }}
```

Do not use `MatteoCampinoti94/changelog-to-release` or repo-local changelog formatting configuration.
GitHub release notes and PSGallery manifest release notes should be the same source text, not independently formatted variants.

## Required Build Script Pattern

Release-artifact stamping and verification belong in the local `Invoke-Build` script, not inline in the
workflow YAML. The committed source manifest keeps release notes empty; the `SetVersion` task populates
release notes into the built artifact at publish time and verifies the package before it is published.

The prepare job stamps the source manifest version through `SetSourceVersion`; the publish path runs
`SetVersion` in `-VerifyPublishedRelease` mode so a malformed or unstamped artifact fails before the
immutable PSGallery publish. The workflow only invokes these tasks; it never stamps manifests inline.

```powershell
# Synopsis: Stamp the planned version into the committed source manifest (release notes stay empty here).
Task SetSourceVersion {
    if (-not $script:BuildInfo.VersionToPublish) {
        throw 'VersionToPublish is required for SetSourceVersion. Use -VersionToPublish <semver>.'
    }

    $null = Set-AtlassianPSModuleManifestVersion `
        -BuiltManifestPath $env:BHPSModuleManifest `
        -ModuleName $env:BHProjectName `
        -VersionToPublish $script:BuildInfo.VersionToPublish
}

Task SetVersion {
    if (-not $script:BuildInfo.VersionToPublish) {
        throw 'VersionToPublish is required for SetVersion. Use -VersionToPublish <semver>.'
    }

    $builtManifestPath = $script:BuildInfo.BuiltManifestPath
    $expectedCore = $script:BuildInfo.VersionToPublish -replace '-.*$', ''

    # The CI-tested artifact is built from the already version-stamped source manifest, so in
    # release mode it must already carry the planned version. A mismatch means the prepare step
    # never stamped the source manifest.
    if ($VerifyPublishedRelease) {
        $built = Import-PowerShellDataFile -LiteralPath $builtManifestPath
        if ($built.ModuleVersion -ne $expectedCore) {
            throw "Built artifact ModuleVersion '$($built.ModuleVersion)' does not match release version '$($script:BuildInfo.VersionToPublish)'."
        }
    }

    $releaseNotes = Get-AtlassianPSReleaseNotesFromChangelog `
        -ChangelogPath (Join-Path -Path $env:BHProjectPath -ChildPath 'CHANGELOG.md') `
        -ReleaseVersion $script:BuildInfo.VersionToPublish

    $setVersionParameters = @{
        BuiltManifestPath = $builtManifestPath
        ModuleName        = $env:BHProjectName
        VersionToPublish  = $script:BuildInfo.VersionToPublish
        ReleaseNotes      = $releaseNotes
    }
    if ($VerifyPublishedRelease) {
        $setVersionParameters.EnforceGreaterThanPublished = $true
    }
    $null = Set-AtlassianPSModuleManifestVersion @setVersionParameters

    if ($VerifyPublishedRelease) {
        $stamped = Import-PowerShellDataFile -LiteralPath $builtManifestPath
        if ($stamped.ModuleVersion -ne $expectedCore) {
            throw "Artifact ModuleVersion '$($stamped.ModuleVersion)' does not match expected '$expectedCore' after stamping."
        }
        if ([string]::IsNullOrWhiteSpace($stamped.PrivateData.PSData.ReleaseNotes)) {
            throw 'Artifact PrivateData.PSData.ReleaseNotes is empty after stamping.'
        }
    }
}

# Synopsis: Compress the built module into the publishable release artifact
Task Package {
    $script:PackagePath = New-AtlassianPSModulePackage `
        -BuildOutputPath $env:BHBuildOutput `
        -ModuleName $env:BHProjectName
}
```

Keep repository build orchestration local.
Use Standards for small primitives and shared actions, not for broad module-specific release wrappers.
The continuous release workflow only invokes build tasks (`SetSourceVersion`, `SetVersion`, `Package`) for
module-domain work and Standards composite actions for deployment plumbing; it embeds no manifest-stamping
or packaging logic in the workflow YAML.

## Drift Guards

Each module should include guard tests that enforce the blueprint.
At minimum, test that:

- `Tools/build.requirements.psd1` pins `AtlassianPS.Standards` to the intended version.
- Every `AtlassianPS.Standards/.github/actions/*` workflow reference is pinned to a 40-character commit SHA.
- Every Standards action pin uses the same version comment as `Tools/build.requirements.psd1`.
- The release workflow uses `build-release-notes`.
- The release workflow uses `body_path: ${{ steps.release_notes.outputs.release_notes_path }}`.
- The release workflow builds release notes before publishing.
- The publish job stamps and verifies the artifact through `Invoke-Build -Task SetVersion ... -VerifyPublishedRelease` rather than inline manifest-stamping in the workflow YAML.
- The publish job runs the artifact stamp/verify step before `Publish-Module`.
- Module-domain work runs through build tasks (`SetSourceVersion`, `SetVersion`, `Package`) and deployment plumbing through composite actions (`commit-release-metadata`, `create-release-tag`); the workflow contains no inline manifest stamping or `Compress-Archive` packaging.
- The repository does not keep a non-idempotent `.github/workflows/release.yml` beside `continuous_release.yml`.
- The build script uses `Get-AtlassianPSReleaseNotesFromChangelog` for manifest release notes.
- The `SetVersion` task verifies the built artifact version and non-empty release notes in `-VerifyPublishedRelease` mode.
- The build script keeps publishing secrets and a `Publish` task out (publishing stays in the workflow).
- The committed source manifest keeps `PrivateData.PSData.ReleaseNotes` empty; release notes are populated only into the built artifact.
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
  pull-requests: write
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
3. Remove non-idempotent tag-triggered release workflows such as `.github/workflows/release.yml`.
4. Replace local changelog parsers in build scripts with `Get-AtlassianPSReleaseNotesFromChangelog`.
5. Add or update drift guard tests.
6. Add the `Release Intent` workflow and make it a required check.
7. Add the label-based `Continuous Release` workflow.
8. Configure required labels and secrets.
9. Update the local release runbook to link back to this blueprint.
10. Run local workflow syntax, guard tests, lint, build/test, and release metadata preflight before pushing.

## Implementing Label-Based CD In A Module Repository

Use this section as the implementation order when migrating another AtlassianPS module.
Replace every `<ModuleName>`, `<standards-sha>`, and version comment with the target repository values.

### Required Labels

Create these labels in the repository before making `Release Intent` required:

```text
release:none
release:patch
release:minor
release:major
changelog:added
changelog:changed
changelog:fixed
changelog:removed
changelog:deprecated
changelog:security
changelog:breaking
```

### Required Secrets And Variables

Required secrets:

```text
PSGALLERY_API_KEY
HOMEPAGE_PAT
```

Required secret:

```text
ATLASSIANPS_RELEASE_BOT_TOKEN
```

`ATLASSIANPS_RELEASE_BOT_TOKEN` must be a GitHub App or fine-grained token able to push release metadata and tags. `GITHUB_TOKEN` is insufficient because its pushes do not trigger follow-up CI.

### Release Intent Workflow

Add `.github/workflows/release_intent.yml`:

```yaml
name: Release Intent

on:
  pull_request_target:
    types: [opened, edited, synchronize, reopened, ready_for_review, labeled, unlabeled]

permissions:
  contents: read
  pull-requests: write
  issues: write

jobs:
  validate:
    name: Release Intent
    runs-on: ubuntu-latest
    steps:
      - name: Validate release intent
        uses: AtlassianPS/AtlassianPS.Standards/.github/actions/validate-release-intent@<standards-sha> # vX.Y.Z
```

Do not check out pull request code in this workflow.
Make `Release Intent` a required branch-protection check when the repository uses branch protection.

### Continuous Release Workflow

Add `.github/workflows/continuous_release.yml`:

The full workflow contains security-sensitive recovery and publish logic. Start from the current Standards workflow and replace local action paths with pins for one Standards release; do not copy an older workflow from another module.

```yaml
name: Continuous Release

on:
  workflow_run:
    workflows: [CI]
    types: [completed]
  workflow_dispatch:
    inputs:
      release_impact:
        description: Release impact for unreleased changes already on master
        required: false
        type: choice
        options:
          - patch
          - minor
          - major
      prerelease:
        description: Optional prerelease label for unreleased changes already on master, for example alpha, beta, rc, or rc-2
        required: false
        type: string
      recovery_tag:
        description: Existing release tag to recover after a partial publish, for example v1.2.3
        required: false
        type: string

concurrency:
  group: continuous-release
  cancel-in-progress: false

permissions:
  actions: read
  contents: write
  pull-requests: read

jobs:
  prepare:
    name: Prepare release metadata
    if: >-
      (github.event_name == 'workflow_dispatch' &&
      github.ref == 'refs/heads/master' &&
      inputs.recovery_tag == '') ||
      (github.event.workflow_run.conclusion == 'success' &&
      github.event.workflow_run.event == 'push' &&
      github.event.workflow_run.head_branch == 'master' &&
      !startsWith(github.event.workflow_run.head_commit.message, 'Prepare v'))
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6
        with:
          fetch-depth: 0
          ref: ${{ github.event_name == 'workflow_dispatch' && 'master' || github.event.workflow_run.head_sha }}

      - name: Plan release
        id: plan
        uses: AtlassianPS/AtlassianPS.Standards/.github/actions/plan-merged-release@<standards-sha> # vX.Y.Z
        with:
          commit-sha: ${{ github.event_name == 'workflow_run' && github.event.workflow_run.head_sha || '' }}
          release-impact: ${{ github.event_name == 'workflow_dispatch' && inputs.release_impact || '' }}
          prerelease-label: ${{ github.event_name == 'workflow_dispatch' && inputs.prerelease || '' }}

      - name: Prepare release changelog
        if: steps.plan.outputs.should_release == 'true'
        uses: AtlassianPS/AtlassianPS.Standards/.github/actions/prepare-release-changelog@<standards-sha> # vX.Y.Z
        with:
          release-version: ${{ steps.plan.outputs.release_tag }}

      - uses: AtlassianPS/AtlassianPS.Standards/.github/actions/setup-powershell@<standards-sha> # vX.Y.Z
        if: steps.plan.outputs.should_release == 'true'

      - name: Stamp source manifest version
        if: steps.plan.outputs.should_release == 'true'
        run: Invoke-Build -Task SetSourceVersion -VersionToPublish ${{ steps.plan.outputs.release_tag }}
        shell: pwsh

      - name: Commit release metadata
        if: steps.plan.outputs.should_release == 'true'
        uses: AtlassianPS/AtlassianPS.Standards/.github/actions/commit-release-metadata@<standards-sha> # vX.Y.Z
        with:
          release-tag: ${{ steps.plan.outputs.release_tag }}
          manifest-path: <ModuleName>/<ModuleName>.psd1
          release-bot-token: ${{ secrets.ATLASSIANPS_RELEASE_BOT_TOKEN }}

  publish:
    name: Publish tested release artifact
    if: >-
      (github.event_name == 'workflow_run' &&
      github.event.workflow_run.conclusion == 'success' &&
      github.event.workflow_run.event == 'push' &&
      github.event.workflow_run.head_branch == 'master' &&
      startsWith(github.event.workflow_run.head_commit.message, 'Prepare v') &&
      github.event.workflow_run.head_commit.author.name == 'github-actions[bot]') ||
       (github.event_name == 'workflow_dispatch' &&
       github.ref == 'refs/heads/master' &&
       inputs.recovery_tag != '' &&
       inputs.release_impact == '' &&
       inputs.prerelease == '')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6
        with:
          fetch-depth: 0
          ref: ${{ github.event_name == 'workflow_run' && github.event.workflow_run.head_sha || format('refs/tags/{0}', inputs.recovery_tag) }}

      - name: Resolve prepared release
        id: prepared_release
        shell: pwsh
        env:
          RECOVERY_TAG: ${{ inputs.recovery_tag }}
          PREPARED_COMMIT_MESSAGE: ${{ github.event.workflow_run.head_commit.message }}
        run: |
          if ($env:RECOVERY_TAG) {
            if ($env:RECOVERY_TAG -notmatch '^v\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)(?:-\d+)?)?$') {
              throw "Recovery tag '$env:RECOVERY_TAG' is not a supported release tag."
            }
            git rev-parse --verify --quiet "refs/tags/$env:RECOVERY_TAG^{tag}" | Out-Null
            if ($LASTEXITCODE -ne 0) {
              throw "Recovery tag '$env:RECOVERY_TAG' must be an annotated tag."
            }
            $tagCommit = git rev-parse "refs/tags/$env:RECOVERY_TAG^{commit}"
            git merge-base --is-ancestor $tagCommit origin/master
            if ($LASTEXITCODE -ne 0) {
              throw "Recovery tag '$env:RECOVERY_TAG' does not identify a commit reachable from master."
            }
            "release_tag=$env:RECOVERY_TAG" >> $env:GITHUB_OUTPUT
            "release_commit=$tagCommit" >> $env:GITHUB_OUTPUT
            return
          }

          $message = $env:PREPARED_COMMIT_MESSAGE
          if ($message -notmatch '^Prepare (?<tag>v\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)(?:-\d+)?)?) release$') {
              throw "Commit message '$message' is not a release metadata commit."
          }

          "release_tag=$($Matches.tag)" >> $env:GITHUB_OUTPUT
          "release_commit=${{ github.event.workflow_run.head_sha }}" >> $env:GITHUB_OUTPUT

      - name: Resolve tested CI artifact
        id: ci_run
        shell: pwsh
        env:
          GH_TOKEN: ${{ github.token }}
          WORKFLOW_RUN_ID: ${{ github.event.workflow_run.id }}
          RELEASE_COMMIT: ${{ steps.prepared_release.outputs.release_commit }}
        run: |
          if ($env:WORKFLOW_RUN_ID) {
            "run_id=$env:WORKFLOW_RUN_ID" >> $env:GITHUB_OUTPUT
            return
          }

          $runId = gh api "repos/$env:GITHUB_REPOSITORY/actions/runs?head_sha=$env:RELEASE_COMMIT&status=completed&per_page=100" --jq '.workflow_runs[] | select(.name == "CI" and .conclusion == "success") | .id' |
              Select-Object -First 1
          if (-not $runId) {
            throw "No successful CI run was found for recovery commit '$env:RELEASE_COMMIT'."
          }
          "run_id=$runId" >> $env:GITHUB_OUTPUT

      - name: Download tested release artifact
        uses: dawidd6/action-download-artifact@b6e2e70617bc3265edd6dab6c906732b2f1ae151 # v21
        with:
          run_id: ${{ steps.ci_run.outputs.run_id }}
          name: Release
          path: ./Release/
          if_no_artifact_found: fail

      - uses: AtlassianPS/AtlassianPS.Standards/.github/actions/setup-powershell@<standards-sha> # vX.Y.Z

      - name: Build release notes
        id: release_notes
        uses: AtlassianPS/AtlassianPS.Standards/.github/actions/build-release-notes@<standards-sha> # vX.Y.Z
        with:
          release-version: ${{ steps.prepared_release.outputs.release_tag }}

      - name: Stamp and verify release artifact
        env:
          RECOVERY_TAG: ${{ inputs.recovery_tag }}
        run: |
          if ($env:RECOVERY_TAG) {
            Invoke-Build -Task SetVersion -VersionToPublish ${{ steps.prepared_release.outputs.release_tag }}
          }
          else {
            Invoke-Build -Task SetVersion -VersionToPublish ${{ steps.prepared_release.outputs.release_tag }} -VerifyPublishedRelease
          }
        shell: pwsh

      - name: Package release artifact
        run: Invoke-Build -Task Package
        shell: pwsh

      - name: Verify release artifact
        run: Invoke-Build -Task VerifyReleaseArtifact -VersionToPublish ${{ steps.prepared_release.outputs.release_tag }}
        shell: pwsh

      - name: Create annotated release tag
        uses: AtlassianPS/AtlassianPS.Standards/.github/actions/create-release-tag@<standards-sha> # vX.Y.Z
        with:
          tag: ${{ steps.prepared_release.outputs.release_tag }}
          commit: ${{ steps.prepared_release.outputs.release_commit }}
          github-token: ${{ secrets.ATLASSIANPS_RELEASE_BOT_TOKEN }}

      - name: Resolve release ref
        id: release_ref
        uses: AtlassianPS/AtlassianPS.Standards/.github/actions/resolve-release-tag@<standards-sha> # vX.Y.Z
        with:
          tag: ${{ steps.prepared_release.outputs.release_tag }}

      - name: Publish tested module artifact
        run: |
          $manifest = Test-ModuleManifest -Path ./Release/<ModuleName>/<ModuleName>.psd1 -ErrorAction Stop
          $prerelease = [String]$manifest.PrivateData.PSData.Prerelease
          $expectedGalleryVersion = if ($prerelease) { "$($manifest.Version)-$prerelease" } else { [String]$manifest.Version }
          $published = Find-Module -Name $manifest.Name -AllVersions -AllowPrerelease -ErrorAction Stop |
              Where-Object { $_.Version.ToString() -eq $expectedGalleryVersion } |
              Select-Object -First 1
          if (-not $published) {
            Publish-Module -Path ./Release/<ModuleName> -NuGetApiKey ${{ secrets.PSGALLERY_API_KEY }} -ErrorAction Stop
          }
        shell: pwsh

      - name: Create GitHub release and upload asset
        uses: softprops/action-gh-release@3d0d9888cb7fd7b750713d6e236d1fcb99157228 # v3
        with:
          tag_name: ${{ steps.release_ref.outputs.release_tag }}
          name: ${{ steps.release_ref.outputs.release_tag }}
          body_path: ${{ steps.release_notes.outputs.release_notes_path }}
          files: ./Release/<ModuleName>.zip
          fail_on_unmatched_files: true
          draft: false
          prerelease: ${{ contains(steps.release_ref.outputs.release_tag, '-alpha') || contains(steps.release_ref.outputs.release_tag, '-beta') || contains(steps.release_ref.outputs.release_tag, '-rc') }}
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Notify homepage to update submodule
        if: ${{ !contains(steps.release_ref.outputs.release_tag, '-alpha') && !contains(steps.release_ref.outputs.release_tag, '-beta') && !contains(steps.release_ref.outputs.release_tag, '-rc') }}
        uses: peter-evans/repository-dispatch@28959ce8df70de7be546dd1250a005dd32156697 # v4
        with:
          token: ${{ secrets.HOMEPAGE_PAT }}
          repository: AtlassianPS/AtlassianPS.github.io
          event-type: module-release
          client-payload: '{"module": "<ModuleName>", "version": "${{ steps.release_ref.outputs.release_tag }}"}'
```

Use the exact repository secret name for the website token.
Existing modules use `HOMEPAGE_PAT`; if a repository uses a different name, adjust the snippet instead of creating duplicate secrets.

### Releasing A Bucket Already On Master

If a maintainer asks an agent to release unreleased changes that already exist on `master`, do not create an empty release PR.
Use the manual dispatch path of `continuous_release.yml` from `master` only instead:

1. Inspect `CHANGELOG.md` and `.changelog/*.md` to understand the pending release notes.
2. Choose the highest required impact: `major` beats `minor`, `minor` beats `patch`.
3. Run `continuous_release.yml` with `release_impact` set to that impact; leave `prerelease` empty for a stable release or enter `alpha`, `beta`, `rc`, or a numbered form like `rc-2` for a prerelease.

Do not combine `recovery_tag` with `release_impact` or `prerelease`. Recovery derives its version and commit from the existing annotated tag and uses the successful CI artifact for that exact commit.
4. Monitor the run until the release metadata commit, annotated tag, PSGallery publish, GitHub release, and website dispatch for stable releases complete.

The manual path computes the next version from existing stable `vX.Y.Z` tags and folds the current `## Unreleased` body plus all valid changelog fragments into that version section.
It intentionally does not generate a PR-title fragment because there is no single source PR.

### Module-Specific Substitutions

When copying templates, replace:

| Placeholder | Replace with |
|-------------|--------------|
| `<ModuleName>` | Repository module name, for example `JiraPS` |
| `<standards-sha>` | 40-character `AtlassianPS.Standards` release commit SHA |
| `# vX.Y.Z` | Matching Standards package version comment |
| `./Release/<ModuleName>.zip` | Actual release artifact zip path |
| Website token secret | Existing repository secret, usually `HOMEPAGE_PAT` |

Do not copy the Standards repository's self-import path unless the target repository is `AtlassianPS.Standards` itself.

### Validation Before Opening The Migration PR

Run these checks from the target repository root:

```bash
actionlint .github/workflows/ci.yml .github/workflows/release_intent.yml .github/workflows/continuous_release.yml
git diff --check
```

```powershell
Invoke-Build -Task Lint, Build, Test
```

Optionally use a local throwaway version for a `SetVersion` preflight only after `CHANGELOG.md` has a matching section.
If no release section exists yet, test the parser by preparing a temporary changelog section and revert that temporary change before opening the PR.

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
The same release metadata commit should update the source module manifest so `CHANGELOG.md`, the tag, the repository manifest, the GitHub release body, and PSGallery metadata all describe the same version.
For manual release preparation outside the continuous release workflow, review the generated changelog before tagging the release.

```powershell
Invoke-Build -Task Build, Test
```

Optionally run `Invoke-Build -Task Build, SetVersion -VersionToPublish vX.Y.Z` as a local metadata preflight.
If the preflight cannot find a matching changelog section, do not tag the release.

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
