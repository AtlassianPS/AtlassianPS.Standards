# Gemini/Antigravity Entry Point

Follow canonical guidance in:

- `AGENTS.md`
- `.github/ai-context/powershell-rules.md`

If any rule conflicts, `AGENTS.md` wins.

## Required Checklist

1. Preserve shared-helper compatibility for downstream AtlassianPS repos.
2. Respect versioning/dependency guardrails in `AGENTS.md`.
3. Run from repo root:
   - `./Tools/setup.ps1`
   - `Invoke-Build -Task Lint, Build, Test`
4. Keep tests/docs/changelog aligned with behavior changes.
