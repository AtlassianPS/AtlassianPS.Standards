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
- Keep the end-to-end release process in the shared `module_release.yml` reusable workflow; use small composite actions for its concrete operations.
- Pull requests should declare release intent with exactly one `release:*` label; user-facing changes also need a `changelog:*` label or a valid `.changelog/<pr-number>.<impact>.<type>.md` fragment.
- Keep changelog fragment contents to Markdown list items without `###` headings; release preparation derives and consolidates standard headings from fragment types.
- Preserve the first-seen order of existing standard and custom `Unreleased` sections when merging changelog fragments.
- Keep `issues: read` on continuous-release callers and the reusable workflow's preparation job so merged-PR labels remain readable.
- Do not ask contributors to choose the final release version in normal PRs; release preparation batches merged intent later.
- Use `release:none` for internal maintenance that should ride with a later package instead of creating avoidable Standards version churn.
- Keep release notes sourced from one `CHANGELOG.md` section for both GitHub releases and PSGallery manifest `PrivateData.PSData.ReleaseNotes`.
- Mint short-lived release tokens with `ATLASSIANPS_RELEASE_APP_CLIENT_ID` and `ATLASSIANPS_RELEASE_APP_PRIVATE_KEY`. `GITHUB_TOKEN` cannot start follow-up CI after metadata push.
- Authenticate prepared release workflow runs with the release App actor login; commit author names are not trusted identity.
- Do not enable release publishing on an unprotected `master`; direct pushes can bypass review and imitate release metadata.
- Run manual release dispatches from `master` only; operators choose the impact, never the final version or source commit.
- Candidate CI must create the final validated module directory and release archive without publishing secrets. The publish job downloads the immutable artifact from the exact successful CI run and promotes it without checking out repository code.
- Keep shared CI and release jobs bounded with explicit timeouts, and retain build and test artifacts for 14 days.
- Rerun failed jobs for transient publish failures. For lasting failures, merge a reviewed fix and release the next version; never delete/recreate a tag or republish a PSGallery version.
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
- `.github/workflows/module_ci.yml` owns the reusable module build, platform-test, optional smoke-test, and release-candidate pipeline.
- Keep CI profiles bounded to migration needs. Prefer a common build-task contract over adding product-specific branches to the shared workflow.
- Keep downstream `ci.yml` files limited to triggers, permissions, immutable workflow inputs, and the caller-side `CI Result` compatibility job.
- Continuous release callers listen only for completed `CI` runs on `master`; pull-request CI must not start release orchestration.
- Release-intent callers rerun for label and changed-file events, not title or body edits.
- CI path filters may skip pull request validation for documentation and metadata-only changes. CI always runs for `master` pushes so every merged release-labelled change reaches release planning.
