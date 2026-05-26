# Changelog

## Unreleased

## v0.1.9

- Fixed `Invoke-Lint` so downstream modules can call the exported prefixed command without depending on private helper command visibility at runtime.

## v0.1.8

- Fixed `Invoke-Lint` so downstream modules can call the exported prefixed command without losing access to lint output helpers at runtime.

## v0.1.7

- Added shared blueprint primitives for .env loading, release package validation, external help generation/orphan cleanup, and source/release test module import.
- Documented downstream adoption patterns that keep build, integration, Docker, and parallel-test orchestration readable in product repositories.

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
