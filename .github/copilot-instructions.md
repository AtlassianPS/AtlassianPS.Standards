# GitHub Copilot Entry Point

Use canonical project guidance from:

- `AGENTS.md`
- `.github/ai-context/powershell-rules.md`

If guidance conflicts, `AGENTS.md` is authoritative.

## Required Checklist

1. Keep exported standards helpers compatible for downstream AtlassianPS repositories.
2. Follow compatibility/versioning/dependency guardrails from `AGENTS.md`.
3. Run from repository root:
   - `./Tools/setup.ps1`
   - `Invoke-Build -Task Lint, Build, Test`
4. Keep tests, `README.md`, and `CHANGELOG.md` aligned with user-visible changes.
