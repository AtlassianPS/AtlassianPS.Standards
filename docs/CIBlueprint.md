# AtlassianPS CI Blueprint

The reusable `.github/workflows/module_ci.yml` workflow owns the common PowerShell module pipeline:

- metadata-only pull request filtering;
- lint and build orchestration;
- release-candidate stamping and validation;
- Windows PowerShell 5.1 and PowerShell 7 matrix tests;
- optional first-party Cloud smoke tests; and
- build and test artifact uploads.

Module repositories keep a small `.github/workflows/ci.yml` caller.
The caller owns triggers, permissions, concurrency, the immutable Standards workflow pin, and the `CI Result` compatibility job required by branch protection.

## Caller

```yaml
jobs:
  module-ci:
    uses: AtlassianPS/AtlassianPS.Standards/.github/workflows/module_ci.yml@<standards-sha>
    with:
      smoke-profile: jira
    secrets: inherit

  ci-required:
    name: CI Result
    if: always()
    needs: module-ci
    runs-on: ubuntu-latest
    steps:
      - name: Require the reusable CI pipeline
        shell: bash
        env:
          PIPELINE_RESULT: ${{ needs.module-ci.result }}
        run: |
          if [[ "$PIPELINE_RESULT" != "success" ]]; then
            echo "::error::Module CI finished with result: $PIPELINE_RESULT"
            exit 1
          fi
```

Keep the caller-side result job named `CI Result` so existing branch protection continues to require `CI / CI Result`.

## Inputs

| Input | Default | Purpose |
|---|---:|---|
| `detect-changes` | `true` | Skip expensive pull-request jobs for metadata-only changes. |
| `build-profile` | `standard` | Use `standard` for blueprint modules or `jiraps` for JiraPS's build and test orchestration. |
| `smoke-profile` | `none` | Use `confluence` or `jira` to enable the matching Cloud smoke environment. |
| `exclude-documentation-tests` | `false` | Exclude `Integration` and `Documentation` tags from PowerShell 7 tests. |
| `release-candidate` | `true` | Stamp and verify `Prepare vX.Y.Z release` builds. |
| `module-manifest-path` | empty | Load Standards from source while the Standards repository tests itself. |

Callers with a smoke profile must use `secrets: inherit` so the workflow can read the organization Cloud test secret.
Fork and Dependabot pull requests skip smoke tests.

## Validation

Validate both the reusable workflow and every changed caller before merging:

```bash
actionlint .github/workflows/ci.yml .github/workflows/module_ci.yml
git diff --check
```

Run the repository's normal `Invoke-Build` validation as well.
