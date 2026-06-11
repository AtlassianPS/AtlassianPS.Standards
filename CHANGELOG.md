# Changelog

## Unreleased

## v0.1.12 - 2026-06-11

- Added the `validate-release-intent` GitHub Action to validate PR release and changelog labels before module repositories adopt changelog-fragment based releases without expanding the module export surface.
- Added the `prepare-release-changelog` GitHub Action to prepare release changelog sections from Unreleased entries and changelog fragments, then delete consumed fragments without expanding the module export surface.
- Added label-based continuous release automation that plans releases from merged PR labels, prepares changelog entries, creates annotated tags, publishes to PSGallery, and creates GitHub releases without expanding the module export surface.
- Fixed release-intent validation so release-preparation PRs can delete consumed changelog fragments without treating them as active PR fragments.
- Fixed manual prerelease publishing and removed obsolete publish/package tasks from the Standards build script now that continuous release promotes CI-tested artifacts directly.
* Dogfood release-intent fragment handling (#20, @lipkau)
* Resolve merged release workflow conflicts (#34, @lipkau)

## v0.1.11

- Added a shared `resolve-release-tag` GitHub Action for downstream release workflows to validate annotated release tags and expose release metadata without duplicating shell logic.
- Added `Get-AtlassianPSReleaseNotesFromChangelog` so downstream release builds can reuse one changelog parser for PSGallery manifest release notes.
- Added a shared `build-release-notes` GitHub Action so release workflows can create GitHub release bodies from the same changelog parser without copying PowerShell plumbing.

## v0.1.10

- Added shared blueprint primitives for .env loading, release package validation, external help generation/orphan cleanup, and source/release test module import.
- Documented downstream adoption patterns that keep build, integration, Docker, and parallel-test orchestration readable in product repositories.
- Fixed `Invoke-Lint` so downstream modules can call the exported prefixed command without depending on private helper command visibility at runtime.
- Hardened release workflow validation so releases require annotated semver tags that point to commits reachable from `origin/master` before publishing.
- Added pre-publish release-note validation so missing or empty changelog notes fail before immutable package publication.
- Added a release-artifact downstream contract test that imports the built module in a fresh process and runs the exported prefixed lint command.

## v0.1.6

- Added shared dependency setup/update flow (`Install-DependencyRequirement`, `Update-DependencyReference`) and wired `Tools/setup.ps1` / `Tools/update.dependencies.ps1` to shared command delegation.
- Made dependency lookup failures fail fast by default in `Update-DependencyReference`, with explicit `-AllowLookupFailure` opt-out for manual non-blocking runs.
- Added script-level entrypoint tests for setup and dependency update tooling and deduplicated tool-entrypoint test harness bootstrap via shared test helper extraction.
- Added comment-based help coverage for exported dependency commands.
- Aligned source manifest `ModuleVersion` to the repository major/minor convention (`x.y`) to avoid implying manual patch bumps in source.
- Improved README guidance for dependency setup/update behavior and release process expectations.
- Automated release metadata generation by deriving PSGallery `ReleaseNotes` from the matching `CHANGELOG.md` version section during publish, and failing publish when that section is missing or empty.

## v0.1.1

- First public PowerShell Gallery release of `AtlassianPS.Standards`.
- Added shared build/lint/test orchestration helpers.
- Added shared ScriptAnalyzer settings sync helper.
- Hardened module-join path safety and deterministic source merge behavior.
- Added CI/CD parity improvements (artifact-promotion release flow and CI result gate).
