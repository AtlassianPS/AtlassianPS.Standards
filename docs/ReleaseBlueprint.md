# AtlassianPS Release Blueprint

This document defines the release contract for AtlassianPS PowerShell modules. Repository workflows
implement the contract; this document does not duplicate their YAML.

## Goals

- Release reviewed pull requests without asking contributors to choose a version.
- Keep versions, changelog entries, module metadata, tags, packages, and GitHub releases consistent.
- Build and validate the publishable artifact without release credentials.
- Publish the exact candidate produced by CI without checking out or executing repository code.
- Keep module repositories similar through shared Standards actions and reusable workflows.

## Required Invariants

- Every pull request declares exactly one `release:*` intent before merge.
- Only protected `master` commits can become release candidates.
- Stable metadata commits are promoted only after CI runs triggered by the `atlassianps-release-bot` GitHub App.
- Alpha and beta candidates require manual dispatch from protected `master` and the complete shared CI gate.
- The highest impact among unreleased merged pull requests determines the next version.
- Stable metadata commits contain the final changelog section and source version. Prereleases prepare notes in a disposable CI checkout.
- CI builds, stamps, packages, and validates one final candidate artifact.
- Promotion downloads the immutable candidate from the exact successful CI run.
- Promotion never rebuilds the module or runs repository scripts.
- The tag, PSGallery package, and GitHub release use the same full version. Only stable releases notify the website.
- Annotated `v*` tags are immutable.
- Publishing credentials never enter pull-request validation or candidate CI.

## Version And Changelog Contract

Use one `v`-prefixed three-part version wherever a release is identified.

| Artifact | Format | Example |
|----------|--------|---------|
| Git tag | `vX.Y.Z` | `v3.0.0` |
| Changelog heading | `## vX.Y.Z - YYYY-MM-DD` | `## v3.0.0 - 2026-05-10` |
| Module manifest | `X.Y.Z` | `ModuleVersion = '3.0.0'` |

Alpha and beta tags add a fixed-width label, such as `v0.3.0-alpha0001` or
`v0.3.0-beta0001`. Manifests keep `ModuleVersion = '0.3.0'` and set
`PrivateData.PSData.Prerelease` to the exact label. The full version is numeric version
plus label; numeric equality alone cannot identify a candidate.

Ordering is `0.3.0-alpha0001 < 0.3.0-alpha0002 < 0.3.0-beta0001 < 0.3.0`.
The planner derives the numeric base from the last stable tag and selected impact,
then increments the chosen channel's four-digit sequence from existing tags and
published Gallery versions, including untagged versions from temporary tooling.
After beta starts for a base, continue with beta. Published versions and tags remain immutable.

`CHANGELOG.md` is the only release-note source. The same version section populates the package manifest
and GitHub release body. The committed source manifest keeps `ReleaseNotes` empty.

## Pull Request Release Intent

Each pull request needs exactly one of:

- `release:none`
- `release:patch`
- `release:minor`
- `release:major`

A releasing pull request also needs either one `changelog:*` label or one reviewed fragment named:

```text
.changelog/<pr-number>.<patch|minor|major>.<added|changed|fixed|removed|deprecated|security|breaking>.md
```

Fragment contents should be Markdown list items without a `###` heading. Release preparation groups
them under standard release-note headings based on the filename type and consolidates duplicate
standard headings already present under `## Unreleased`. Existing standard and custom sections keep
their first-seen order; fragment-only headings are appended in standard order.

`release:none` contributes no version impact or public note. It does not remove the merged code from a
future package and does not suppress other releasable changes in the same batch.

Use `release:none` for internal maintenance that does not justify publishing a new package by itself.
For an uncommon coordinated release, maintain the combined notes directly under `## Unreleased`, keep
automatic release disabled while the held pull requests merge, and manually dispatch the final impact.
Do not manufacture extra patch releases solely to distribute workflow-pin or housekeeping changes.

Use `pull_request_target` only to inspect labels, changed-file metadata, and trusted base-branch action
code. Never check out or execute contributor code in that workflow.
Because title and body edits cannot change the validated inputs, release-intent workflows do not
subscribe to the `edited` activity type.

## Major Release Authorization

A major release is a separate product decision and requires fresh, explicit confirmation from a
human maintainer that names both the repository and intended major version.
A `release:major` label, breaking-change notes, a merged pull request, automatic version calculation,
or a general request to continue release work expresses intent but does not authorize the release.

Obtain that confirmation before merging a change with pending major-release intent, enabling
continuous delivery while major intent is pending, or manually dispatching `release_impact: major`.
Until confirmation is given, keep publication disabled and report the proposed major release instead.
Do not push a major release metadata commit, create or push its tag, or publish its package.

## Continuous Release Flow

1. `Release Intent` validates labels and changelog input on the pull request.
2. The protected-branch CI gate validates the reviewed change.
3. After merge, the serialized planner reconciles all merged pull requests since the latest stable tag.
4. If every pending pull request uses `release:none`, planning stops successfully.
5. Otherwise, the planner calculates the next version, folds changelog fragments, stamps the source
   manifest version, and pushes one `Prepare vX.Y.Z release` metadata commit with the release GitHub App.
6. The secretless CI build job stamps release notes into the built module, creates the GitHub archive,
   validates them, and uploads `Release`.
7. Every supported platform test consumes that same built module directory.
8. After CI succeeds, the publishing job downloads GitHub's immutable `Release` artifact from that
   exact run. The official download action verifies the artifact digest.
9. Without checking out the repository, the publisher creates the annotated tag, passes the candidate
   module directory to `Publish-Module`, creates the GitHub release from the candidate notes and archive,
   and notifies the website.

Shared CI and release jobs use explicit timeouts so a hung command cannot consume GitHub's six-hour
default. Candidate and test-result artifacts are retained for 14 days, which leaves time for release
promotion and failure analysis without keeping routine artifacts for the repository-wide default.

GitHub Actions events wake the planner; they are not release work items. GitHub concurrency can replace
a pending event, so the planner must reconcile durable Git and pull-request history rather than rely on
one event payload.

## Candidate Artifact Contract

For a release metadata commit, `Release` must contain:

| Path | Purpose |
|------|---------|
| `<ModuleName>/` | Validated module directory published to PSGallery |
| `<ModuleName>.zip` | GitHub release asset |
| `release-notes.md` | GitHub release body |
| `candidate-ledger.json` | Alpha/beta full version, source/workflow commits, and archive SHA256 |

The alpha/beta build prepares a candidate changelog section only in the disposable
CI checkout. It never pushes metadata or deletes fragments from `master`, so stable
planning retains its notes. CI verifies the full version, exact label, notes, and
every archived file against the built directory before the Windows PS5 and PS7
matrix consumes that artifact. Acquisition checks import the hash-verified archive
in fresh processes and verify the loaded path and full version.

The publishing job may use trusted pinned third-party actions and inline deployment commands. It must not
check out repository contents, invoke the repository build, load local actions, or modify the candidate.
`Publish-Module` packages the validated directory during publication; the pipeline does not prebuild a
`.nupkg`.

## Failure Policy

Use GitHub's failed-job rerun for transient failures while the original CI candidate remains available.
Tag creation and PSGallery detection should remain idempotent so such reruns are safe.

For a lasting failure, fix the problem through a reviewed pull request and release the next version. Do
not delete, move, or recreate an existing tag, and never republish an immutable PSGallery version. If
PSGallery succeeded but a later step failed, a maintainer may repair the GitHub release or website entry
manually.

There is no historical `recovery_tag` workflow or durable release state machine. The small maintainer
team accepts an unpublished version gap in exchange for a simpler pipeline.

## Manual Release Of Existing Changes

Manual dispatch handles an unreleased bucket already on `master`; it is not a recovery mechanism.

1. Run `Continuous Release` from `master`.
2. Choose the highest required `release_impact` for the pending changes.
3. Let the normal metadata-commit, CI-candidate, and promotion flow finish.

Select `release_channel=alpha` or `beta` to test the same pending bucket before stable
release. The shared workflow runs the required build, platform tests and configured
smoke tests, then downloads `Release` from that exact run in the protected publisher.
It uses the existing module name on PSGallery and marks the GitHub release as a
prerelease. Candidate activity does not trigger the stable metadata-commit route.
After publication, fresh Windows PowerShell 5.1 and PowerShell 7 processes acquire
the exact Gallery candidate with prerelease opt-in and check ordinary stable acquisition.

Standards CI also runs these Gallery checks against the published Configuration
`0.3.0-alpha0002` and its latest stable package on both Windows shells.
This tests the acquisition helper before a new candidate is published.

For a major-base release, including an alpha or beta, enter fresh human confirmation
in `major_authorization` as `owner/repository vMAJOR`, for example
`AtlassianPS/JiraPS v3`. Automatic major intent stops at planning until a human
dispatches with that confirmation. Keep JiraPS's existing stable CD guard disabled
until its separately approved stable rollout is ready.

Promote to stable by reviewing candidate results, merging any fixes, and dispatching
the same impact with `release_channel=stable`. Stable CI builds and validates its own
final manifest with an empty prerelease label. It does not rename a candidate package.
For transient failures, rerun only the failed jobs while the original artifact is
retained. A new dispatch calculates a new candidate after a tag was reserved. For a
lasting failure, merge a reviewed fix and use that next version; never reuse a tag or
PSGallery version. Repair a missing GitHub release manually if Gallery already succeeded.

## Exact candidate dependencies

Normal setup uses stable acquisition without prerelease opt-in. Runtime manifests
express numeric compatibility using `ModuleVersion` and `MaximumVersion`. Build
pins use `RequiredVersion`. The shared installer honors both range endpoints and
excludes installed prereleases from stable provisioning.

Explicit candidate provisioning uses a separate full-version selection:

```powershell
$candidate = @{ ModuleName = 'AtlassianPS.Configuration'; RequiredVersion = '0.3.0-alpha0001' }
Install-AtlassianPSDependencyRequirement -BuildRequirementsPath ./Tools/build.requirements.psd1 `
    -ManifestPath ./JiraPS/JiraPS.psd1 -CandidateRequirement $candidate -CandidateRoot ./.tmp/candidates
```

For a reviewed local release archive, add `PackagePath` and `PackageSha256` to that
candidate entry. `Install-AtlassianPSModuleCandidate` saves or extracts into a unique
root, verifies the full version, and imports the exact manifest globally. It adds
the isolated root to the current process's module path for saved dependencies.
An already loaded module requires a fresh process. A stable or another candidate
with the same numeric version cannot satisfy this request. Candidate numeric versions
must still satisfy the manifest's runtime bounds or an exact build pin.

Adopt the new provisioning parameters only with a released Standards version that
exports them. The temporary JiraPS/Configuration alpha helpers remain until the
replacement acquisition and Cloud/Data Center integration tests pass and a compatible
stable Configuration prerequisite is available. Preserve published packages and their
verification ledgers during that cleanup; retain disposable configuration storage.

The operator never enters the final version or source commit.

## Identity And Repository Configuration

The single-maintainer governance policy below follows the
[approved WP5 decision](https://github.com/AtlassianPS/AtlassianPS/issues/13#issuecomment-6034428988).

Required organization or repository variable:

```text
ATLASSIANPS_RELEASE_APP_CLIENT_ID
```

Required organization or repository secrets:

```text
ATLASSIANPS_RELEASE_APP_PRIVATE_KEY
PSGALLERY_API_KEY
HOMEPAGE_PAT
```

Configure a `release` environment restricted to the literal `master` branch, with no mandatory
reviewers or wait timer. The existing environment setting allows administrator bypass; routine
publishing uses the branch restriction and the workflow's release conditions. The release GitHub App
should have only the repository permissions needed to push release metadata and create tags.
Workflows mint short-lived installation tokens with a SHA-pinned `actions/create-github-app-token`;
they do not store installation tokens or use personal access tokens for routine release writes.

Require a pull request and GitHub Actions checks on the default branch. Module repositories require
`CI Result` and `Release Intent`; the `.github` controller requires `test` from its `CI` workflow;
the website requires `build`. Bind these checks to the GitHub Actions App. Keep checks non-strict,
block branch deletion and force pushes, and configure no administrator bypass. The maintainer
reviews the diff and check results before merging. Zero approvals are required, so independent
approval, CODEOWNERS review, review-thread resolution and signed commits are optional.

Only the release App has an always-bypass on module default-branch rulesets, because preparation
pushes release metadata directly. This bypass applies to the whole ruleset; trusted release
workflows constrain its intended use. The dependency-update App has no bypass. Emergency human
recovery requires a documented temporary ruleset edit and restoration of the approved settings.

Protect `refs/tags/v*` with an App-only creation ruleset and a separate update/deletion ruleset
with no bypass actors. Even the release App cannot move or delete an existing release tag.
The publisher must create annotated tags and validate an existing tag without modifying it on retry.

Enable GitHub's full-length commit SHA requirement for actions in each active repository.
Reusable workflows must also use full SHAs, verified through source review and drift tests;
GitHub's native action pinning setting still permits reusable workflows referenced by tags.

The publish job must authenticate `github.event.workflow_run.actor.login` as
`atlassianps-release-bot[bot]`. Commit author and committer names are metadata supplied by Git clients
and must not be used as the release identity boundary.

## Shared Implementation

Keep module-domain behavior in these build tasks:

- `SetSourceVersion` updates the committed source manifest version.
- `SetVersion` stamps changelog-derived release notes into the built candidate.
- `Package` creates the release archive.
- `VerifyReleaseArtifact` validates the module version, release notes, and archive contents.

The shared Standards `module_release.yml` reusable workflow owns the complete prepare and publish
orchestration, including its event conditions. A module repository keeps only the trigger, immutable
Standards workflow pin, module name, and whether publication should notify the website.

```yaml
name: Continuous Release

on:
  workflow_run:
    workflows: [CI]
    types: [completed]
    branches: [master]
  workflow_dispatch:
    inputs:
      release_impact:
        required: true
        type: choice
        options: [patch, minor, major]
      release_channel:
        required: true
        default: stable
        type: choice
        options: [stable, alpha, beta]
      major_authorization:
        required: false
        type: string

permissions:
  actions: read
  contents: read
  issues: read
  pull-requests: read

jobs:
  release:
    uses: AtlassianPS/AtlassianPS.Standards/.github/workflows/module_release.yml@<standards-sha>
    with:
      module-name: ExampleModule
      release-impact: ${{ inputs.release_impact }}
      release-channel: ${{ inputs.release_channel || 'stable' }}
      major-authorization: ${{ inputs.major_authorization }}
    secrets: inherit
```

The caller and the reusable workflow's preparation job both need `issues: read` because GitHub
exposes pull request labels through the issues labels API.

The reusable workflow checks out its own implementation at `job.workflow_sha` during preparation, so
its composite actions and scripts come from the same immutable Standards commit as the workflow. The
publisher does not check out either repository.

Pin all Standards and third-party Actions references to 40-character commit SHAs. Downstream repositories
must pin all Standards actions used by one workflow to the same released Standards commit.

## Downstream Adoption

Adopt this flow only after Standards completes a real automatic release.

For each module repository:

1. Update the pinned Standards module and workflow commit together.
2. Add the required labels and `Release Intent` check.
3. Add candidate creation to CI and make `CI Result` require it.
4. Add the thin continuous-release caller pinned to the released Standards commit.
5. Configure the release environment, App access, PSGallery key, and website token.
6. Apply the branch, tag, review, bypass, environment and Actions pinning policy above.
7. Remove older tag-triggered or rebuild-on-publish workflows.
8. Run a shadow candidate build before enabling publication.
9. Merge one small real patch and verify the complete release path.

Do not copy the release implementation into module repositories. Call the released reusable workflow
at its immutable commit SHA.

## Required Drift Guards

Tests in each module repository should verify that:

- Standards dependencies and action pins agree;
- action references use immutable SHAs;
- pull-request validation never checks out contributor code;
- candidate CI contains no publishing credentials;
- candidate CI stamps, packages, validates, and uploads one immutable artifact;
- continuous release calls the shared workflow at the same immutable Standards commit;
- the source manifest keeps release notes empty;
- no parallel tag-triggered or recovery workflow remains.

Standards tests own the shared workflow's prepare/publish conditions, immutable artifact download,
digest verification, checkout boundary, tag ordering, dependency installation, idempotency, and
publication assertions.

Before merging release changes, run:

```bash
actionlint .github/workflows/ci.yml .github/workflows/release_intent.yml .github/workflows/continuous_release.yml .github/workflows/module_release.yml
git diff --check
```

```powershell
Invoke-Build -Task Lint, Build, Test
```

## Common Mistakes

- Publishing a package rebuilt after CI.
- Making publishing secrets available to candidate build or test jobs.
- Checking out repository code in the publishing job.
- Treating a workflow event as the only record of pending release intent.
- Using `GITHUB_TOKEN` for a metadata push that must trigger follow-up CI.
- Using a personal token as the routine release identity.
- Creating lightweight, mutable, or unprotected release tags.
- Generating GitHub and PSGallery release notes from different sources.
- Adding recovery branches before the repository's operating model needs them.
