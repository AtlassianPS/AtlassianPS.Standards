# Gemini/Antigravity Entry Point

Follow canonical guidance in:

- `AGENTS.md`
- `.github/ai-context/powershell-rules.md`

If any rule conflicts, `AGENTS.md` wins.

## Required Checklist

1. Preserve shared-helper compatibility for downstream AtlassianPS repos.
2. Respect versioning/dependency guardrails in `AGENTS.md`.
3. During iteration, run focused tests when possible (for example `Invoke-Pester -Path 'Tests/Functions/Public/Invoke-Lint.Unit.Tests.ps1'`).
4. Before finalizing, run from repo root:
   - `./Tools/setup.ps1`
   - `Invoke-Build -Task Lint, Build, Test`
5. Keep tests/docs/changelog aligned with behavior changes.
6. Instruction-only changes may be skipped by CI path filters; run local validation and report exact command outcomes.
