# Changelog

## Unreleased

- Reduced exported command surface by keeping `Get-BuildEnvironmentInfo` and `Get-ScriptAnalyzerSettingsPath` internal-only.
- Removed public availability of `Get-AtlassianPSBuildEnvironmentInfo` and `Get-AtlassianPSScriptAnalyzerSettingsPath`.
- Use public alternatives instead: `Initialize-AtlassianPSBuildEnvironment`, `Write-AtlassianPSBuildInfo`, and `Sync-AtlassianPSScriptAnalyzerSettings`.
- Made `Update-DependencyReference` fail fast on module version lookup errors by default, with explicit `-AllowLookupFailure` opt-out.
- Added script-level tests for `Tools/setup.ps1` entrypoint wiring and fail-fast behavior.
- Added comment-based help to dependency setup/update commands and test coverage for help availability.
- Aligned source manifest `ModuleVersion` to the repository major/minor convention (`x.y`) and documented tag-stamped release versioning.

## v0.1.1

- First public PowerShell Gallery release of `AtlassianPS.Standards`.
- Added shared build/lint/test orchestration helpers.
- Added shared ScriptAnalyzer settings sync helper.
- Hardened module-join path safety and deterministic source merge behavior.
- Added CI/CD parity improvements (artifact-promotion release flow and CI result gate).
