# Changelog

## Unreleased

- Reduced exported command surface by keeping `Get-BuildEnvironmentInfo` and `Get-ScriptAnalyzerSettingsPath` internal-only.
- Removed public availability of `Get-AtlassianPSBuildEnvironmentInfo` and `Get-AtlassianPSScriptAnalyzerSettingsPath`.
- Use public alternatives instead: `Initialize-AtlassianPSBuildEnvironment`, `Write-AtlassianPSBuildInfo`, and `Sync-AtlassianPSScriptAnalyzerSettings`.

## v0.1.1

- First public PowerShell Gallery release of `AtlassianPS.Standards`.
- Added shared build/lint/test orchestration helpers.
- Added shared ScriptAnalyzer settings sync helper.
- Hardened module-join path safety and deterministic source merge behavior.
- Added CI/CD parity improvements (artifact-promotion release flow and CI result gate).
