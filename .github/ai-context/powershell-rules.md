# AtlassianPS.Standards PowerShell Rules

Practical implementation/build/test guidance shared across AI entry points.

## Build and Test Commands (repo root)

```powershell
./Tools/setup.ps1
Invoke-Build -Task Lint, Build, Test
```

Focused iteration commands are allowed, for example:

```powershell
Invoke-Build -Task Lint
Invoke-Pester -Path 'Tests/Functions/Public/Invoke-Lint.Unit.Tests.ps1'
```

Before finalizing, run the full pipeline: `Invoke-Build -Task Lint, Build, Test`.
Instruction-only changes may be skipped by CI path filters; run local validation and report exact command outcomes.

## Compatibility Targets

- Keep module behavior compatible with both Windows PowerShell 5.1 and PowerShell 7.x.
- Avoid shell-specific assumptions that break in PS 5.1.
- Preserve exported helper contracts consumed by downstream AtlassianPS repositories.

## Versioning and Dependency Guardrails

- Keep dependencies pinned (no floating ranges).
- Keep `RequiredModules` in `AtlassianPS.Standards/AtlassianPS.Standards.psd1` synchronized with `Tools/build.requirements.psd1`.
- Treat breaking helper behavior as a major-version concern.
- Use `vX.Y.Z` tags for release publishing.

## Release Flow Guidance

- Read `docs/ReleaseBlueprint.md` before changing release-related commands, actions, workflows, or documentation.
- Keep release implementation reusable as small Standards primitives/actions; do not copy broad orchestration into module repositories.
- PRs declare release intent with `release:*` labels and, for user-facing changes, `changelog:*` labels or `.changelog` fragments. Contributors should not need to pick the final release version.
- Release notes must come from the same `CHANGELOG.md` section for GitHub release bodies and PSGallery manifest `PrivateData.PSData.ReleaseNotes`.
- If release flow changes, update the blueprint, helper catalog, tests, changelog, and agent instructions together.

## Source Layout

- Public helpers: `AtlassianPS.Standards/Public/*.ps1`
- Private helpers: `AtlassianPS.Standards/Private/*.ps1`
- Build script: `AtlassianPS.Standards.build.ps1`
- Tests: `Tests/**/*.ps1`
- Dependency bootstrap: `Tools/setup.ps1`, `Tools/build.requirements.psd1`

## Helper Design Conventions

- Reuse existing orchestration helpers before introducing new patterns.
- Prefer additive signatures and backward-compatible defaults.
- Keep build/release logic deterministic and CI-friendly.
- Add comments only where constraints or trade-offs are non-obvious.

## Documentation Conventions

- Keep `README.md` usage examples current with exported helper behavior.
- Add `CHANGELOG.md` entries for user-visible behavior changes.
