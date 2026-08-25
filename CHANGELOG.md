# Changelog

## Unreleased

## v0.3.3 - 2026-08-25

### Fixed

* Preserve changelog section order (#58, @lipkau)

## v0.3.2 - 2026-08-25

### Changed

* Bound shared CI and release resource usage (#57, @lipkau)

## v0.3.1 - 2026-08-25

### Changed

- Allowed the JiraPS reusable CI profile to build and verify continuous-release candidates when the repository implements the shared artifact contract.
* Enable JiraPS release candidate validation (#55, @lipkau)

## v0.3.0 - 2026-08-25

### Changed

* Constrain automated dependency updates (#53, @lipkau)

### Fixed

* Keep automated dependency updates within the currently pinned major version unless a major upgrade is explicitly requested, and keep shared test orchestration on the supported Pester 5 range.

## v0.2.0 - 2026-08-25

### Added

* Centralize module CI orchestration (#54, @lipkau)

## v0.1.19 - 2026-08-24

### Fixed

* Allowed manual releases to commit metadata when no `.changelog` directory exists.

## v0.1.18 - 2026-08-24

### Fixed

* Grouped typed changelog fragments under standard release-note headings and consolidated duplicate headings during release preparation (#51, @lipkau).

## v0.1.17 - 2026-08-24

* Fix release planner label permissions (#50, @lipkau)

## v0.1.16 - 2026-08-21

* Centralize module release orchestration (#47, @lipkau)

## v0.1.15 - 2026-08-21

* Fixed module version stamping to preserve nested dependency versions.

## v0.1.14 - 2026-08-19

* fix(cd): pass App token to release action (#41, @lipkau)

## v0.1.13 - 2026-08-18

* Fixed continuous delivery to build and validate one release candidate in secretless CI, then publish its validated module directory without checking out or rebuilding repository code. `v0.1.12` was not published; its changes are included in this release.

## v0.1.12 - 2026-06-18

- Fixed continuous release version stamping so the source manifest version is updated in place without reformatting the manifest, release notes stay empty in source and are populated into the built artifact at publish time, and the publish step verifies the artifact version and release notes before publishing.
- Added the `validate-release-intent` GitHub Action to validate PR release and changelog labels before module repositories adopt changelog-fragment based releases without expanding the module export surface.
- Added the `prepare-release-changelog` GitHub Action to prepare release changelog sections from Unreleased entries and changelog fragments, then delete consumed fragments without expanding the module export surface.
- Added label-based continuous release automation that plans releases from merged PR labels, prepares changelog entries, creates annotated tags, publishes to PSGallery, and creates GitHub releases without expanding the module export surface.
- Fixed release-intent validation so release-preparation PRs can delete consumed changelog fragments without treating them as active PR fragments.
- Fixed release-intent comment handling after dogfooding the workflow against Standards pull requests.
- Dogfood release-intent fragment handling (#20, @lipkau)
- Fixed manual prerelease publishing and removed obsolete publish/package tasks from the Standards build script now that continuous release promotes CI-tested artifacts directly.
- Resolve merged release workflow conflicts (#34, @lipkau)
* Fix continuous release version stamping and reconcile release metadata (#38, @lipkau)

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
