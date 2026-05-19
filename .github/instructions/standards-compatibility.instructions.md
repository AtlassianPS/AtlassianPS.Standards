---
applyTo: "**/*.ps1"
---

# PowerShell File Rules (GitHub Copilot)

This file applies to all `.ps1` files. It references shared rules.

**Canonical source**: [.github/ai-context/powershell-rules.md](../ai-context/powershell-rules.md)

## Quick Reference

1. **Shared contract stability** — preserve exported helper behavior for downstream AtlassianPS repositories.
2. **Dependency/version guardrails** — keep pinned dependency versions and semver expectations aligned with `AGENTS.md`.
3. **Focused iteration** — run targeted tests when possible (for example `Invoke-Pester -Path 'Tests/Functions/Public/Invoke-Lint.Unit.Tests.ps1'`).
4. **Final validation** — run `./Tools/setup.ps1` and `Invoke-Build -Task Lint, Build, Test` before finalizing.
5. **CI path filters** — instruction-only changes may be skipped by CI; run local validation and report exact command outcomes.

For full rules, read `.github/ai-context/powershell-rules.md`.
