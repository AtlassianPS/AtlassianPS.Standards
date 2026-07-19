# Continuous Delivery Status

## Goal

Automated, safe release after reviewed PR merge. `release:none` is only normal skip path.

## Current State

✅ Label validation exists in trusted `pull_request_target` workflow.

✅ Continuous release creates metadata commit, waits for CI, tags, publishes PSGallery, creates GitHub release, notifies website.

✅ Latest source baseline is `v0.1.12` at `b95fd4d`.

⚠️ `v0.1.12` annotated tag exists; PSGallery package and GitHub release do not. Existing workflow cannot resume same version.

❌ `master` has no branch protection or ruleset. Direct pushes bypass review, CI, release intent, and CODEOWNERS.

❌ CI path filters can suppress `workflow_run`; labelled documentation or metadata PRs then never release.

❌ Publish job modifies package after CI without validating final package.

✅ Third-party workflow Actions are SHA-pinned. Repository SHA pinning is required; default workflow token permission is read-only.

## Implementation Plan

1. ✅ Removed CI path filters. Every merged PR triggers release planning.
2. ✅ Added final archive validation after manifest stamp and packaging, before tag/publish.
3. ✅ Added `recovery_tag` dispatch. Recovery verifies tagged master commit and successful CI artifact, then safely skips only existing PSGallery version.
4. ✅ Made merged-PR resolution deterministic: exact `merge_commit_sha`, exactly one match.
5. ✅ Added regression tests for planner ambiguity and final package version/notes validation.
6. ✅ Pinned third-party Actions; CI token now read-only.
7. ⏳ Configure GitHub `master` ruleset and `v*` tag protection. Required checks: `CI Result`, `Release Intent`; one approval; stale-review dismissal; CODEOWNERS; no force push/deletion. Blocked only on selecting release bot bypass identity: GitHub App preferred, or existing `ATLASSIANPS_RELEASE_BOT_TOKEN` owner.
8. ⏳ Repair stalled `v0.1.12` with `recovery_tag: v0.1.12` after merge. PSGallery publish is irreversible; inspect exact release state first.

## Definition Of Done

- Reviewed, labelled PR merges trigger one release or explicit `release:none` skip.
- Final PSGallery package has CI-equivalent validation and matching tag/changelog/version/notes.
- Safe rerun completes partial release without duplicate immutable package or tag drift.
- `master` requires approval, CI Result, Release Intent, and CODEOWNERS review.
- Third-party Actions immutable-pinned; tokens least-privilege.
- Focused tests, full build/test, workflow lint, and release-state preflight pass.

## Verified

✅ `actionlint` passed all workflows.

✅ Focused pipeline/package tests: 25 passed.

✅ Full `Invoke-Build -Task Lint, Build, Test`: 81 passed, 0 failed.
