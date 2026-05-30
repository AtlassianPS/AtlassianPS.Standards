# AI Instructions for AtlassianPS.Standards

`AtlassianPS.Standards` is a shared standards module consumed by other AtlassianPS repositories.
Optimize for stable contracts, predictable build behavior, and low-noise changes.

## Instruction Hierarchy (Canonical)

1. `AGENTS.md` (this file) is the canonical policy.
2. `.github/ai-context/powershell-rules.md` defines implementation/build/test specifics.
3. Tool entry points (`CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`, `.github/instructions/*.instructions.md`, `.cursor/rules/*.mdc`) must mirror this guidance and not introduce conflicting rules.

If guidance conflicts, follow this file first.

## Critical Shared-Standards Contract

- Treat exported helper behavior as a compatibility contract for downstream repos.
- Prefer additive changes (new optional parameters/new helpers) over breaking changes.
- Do not rename/remove exported commands or alter output/side effects without explicit migration intent.
- Keep build and test orchestration centralized in standards helpers instead of duplicating logic in downstream repos.

## Compatibility and Versioning Guardrails

- Maintain compatibility with `PowerShellVersion = '5.1'` in the module manifest.
- Keep cross-shell behavior safe for both Windows PowerShell 5.1 and PowerShell 7.x (CI validates both).
- Keep dependency versions pinned and synchronized between:
  - `AtlassianPS.Standards/AtlassianPS.Standards.psd1` (`RequiredModules`)
  - `Tools/build.requirements.psd1`
- Use semver tags (`vX.Y.Z`) for releases; treat any intentional breaking change as a major-version event.

## Release Flow

- `docs/ReleaseBlueprint.md` is the canonical cross-repository release flow for AtlassianPS PowerShell modules.
- Prefer small Standards primitives and composite actions over copied release workflow logic in downstream repositories.
- Pull requests should declare release intent with exactly one `release:*` label; user-facing changes also need a `changelog:*` label or a valid `.changelog/<pr-number>.<impact>.<type>.md` fragment.
- Do not ask contributors to choose the final release version in normal PRs; release preparation batches merged intent later.
- Keep release notes sourced from one `CHANGELOG.md` section for both GitHub releases and PSGallery manifest `PrivateData.PSData.ReleaseNotes`.
- When changing release behavior, update `docs/ReleaseBlueprint.md`, `docs/BlueprintHelpers.md`, tests, and these agent instructions together.

## Build, Lint, Test (run from repo root)

```powershell
./Tools/setup.ps1
Invoke-Build -Task Lint, Build, Test
```

During iteration, run focused validation (for example `Invoke-Pester -Path 'Tests/Functions/Public/Invoke-Lint.Unit.Tests.ps1'`).
Before finalizing, always run the full pipeline: `Invoke-Build -Task Lint, Build, Test`.

## Change Scope and Quality Bar

- Keep each change focused and avoid unrelated refactors.
- Add or update tests in `Tests/` for behavior changes.
- Update `README.md` and `CHANGELOG.md` for user-visible changes.
- Do not finalize with a red build.

## Repository Map

- Module source: `AtlassianPS.Standards/Public/`, `AtlassianPS.Standards/Private/`
- Build entrypoint: `AtlassianPS.Standards.build.ps1`
- Tests: `Tests/`
- Dependency bootstrap: `Tools/setup.ps1`
- CI workflows: `.github/workflows/`

## AI Tool Compatibility

| Tool | Entry point | Canonical references |
|------|-------------|----------------------|
| GitHub Copilot | `.github/copilot-instructions.md` | `AGENTS.md`, `.github/ai-context/powershell-rules.md` |
| GitHub Copilot (file rules) | `.github/instructions/standards-compatibility.instructions.md` | `.github/ai-context/powershell-rules.md` |
| Cursor | `.cursor/rules/atlassianps-standards.mdc` | `AGENTS.md`, `.github/ai-context/powershell-rules.md` |
| Claude Code | `CLAUDE.md` | `AGENTS.md`, `.github/ai-context/powershell-rules.md` |
| Gemini/Antigravity | `GEMINI.md` | `AGENTS.md`, `.github/ai-context/powershell-rules.md` |

## CI/CD Notes

- `.github/workflows/ci.yml` is the required quality gate for runtime/code changes.
- Instruction-only changes can be skipped by CI path filters; run local validation and report exact command outcomes.
