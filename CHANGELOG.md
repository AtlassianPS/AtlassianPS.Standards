# Changelog

## Unreleased

## v0.1.4

- Backfilled release metadata after v0.1.3 by adding explicit release notes to the GitHub release and packaging corrected release notes metadata for PSGallery.
- Aligned source manifest `ModuleVersion` to the repository major/minor convention (`x.y`) to avoid implying manual patch bumps in source.

## v0.1.3

- Added shared dependency setup/update flow (`Install-DependencyRequirement`, `Update-DependencyReference`) and wired `Tools/setup.ps1` / `Tools/update.dependencies.ps1` to shared command delegation.
- Made dependency lookup failures fail fast by default in `Update-DependencyReference`, with explicit `-AllowLookupFailure` opt-out for manual non-blocking runs.
- Added script-level entrypoint tests for setup and dependency update tooling.
- Added comment-based help coverage for exported dependency commands.
- Deduplicated tool-entrypoint test harness bootstrap via shared test helper extraction.
- Improved README guidance for dependency setup/update behavior.

## v0.1.1

- First public PowerShell Gallery release of `AtlassianPS.Standards`.
- Added shared build/lint/test orchestration helpers.
- Added shared ScriptAnalyzer settings sync helper.
- Hardened module-join path safety and deterministic source merge behavior.
- Added CI/CD parity improvements (artifact-promotion release flow and CI result gate).
