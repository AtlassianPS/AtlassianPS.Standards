# GitHub Copilot Entry Point

Use canonical project guidance from:

- `AGENTS.md`
- `.github/ai-context/powershell-rules.md`
- `.github/instructions/`

If guidance conflicts, `AGENTS.md` is authoritative.

## Required Checklist

1. Keep exported standards helpers compatible for downstream AtlassianPS repositories.
2. Follow compatibility/versioning/dependency guardrails from `AGENTS.md`.
3. During iteration, run focused tests when possible (for example `Invoke-Pester -Path 'Tests/Functions/Public/Invoke-Lint.Unit.Tests.ps1'`).
4. Before finalizing, run from repository root:
   - `./Tools/setup.ps1`
   - `Invoke-Build -Task Lint, Build, Test`
5. Keep tests, `README.md`, and `CHANGELOG.md` aligned with user-visible changes.
6. For release-related work, follow `docs/ReleaseBlueprint.md`: use release-intent labels/fragments, keep release notes synchronized, and prefer shared Standards primitives/actions over copied workflow logic.
7. Instruction-only changes may be skipped by CI path filters; run local validation and report exact command outcomes.
