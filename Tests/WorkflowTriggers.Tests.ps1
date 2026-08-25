#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.9.0"; MaximumVersion = "5.9.999" }

Describe 'GitHub Actions workflow triggers' -Tag 'Lint', 'Unit' {
    BeforeAll {
        $script:workflowRoot = "$PSScriptRoot/../.github/workflows"
    }

    It 'starts continuous release only for completed CI runs on master' {
        $workflow = Get-Content (Join-Path $script:workflowRoot 'continuous_release.yml') -Raw

        $workflow | Should -Match '(?ms)workflow_run:.*?workflows:\s*\[CI\].*?types:\s*\[completed\].*?branches:\s*\[master\]'
    }

    It 'does not rerun release intent validation for title or body edits' {
        $workflow = Get-Content (Join-Path $script:workflowRoot 'release_intent.yml') -Raw

        $workflow | Should -Not -Match 'types:\s*\[[^\]]*\bedited\b'
        $workflow | Should -Match 'types:\s*\[[^\]]*\bsynchronize\b'
        $workflow | Should -Match 'types:\s*\[[^\]]*\blabeled\b'
        $workflow | Should -Match 'types:\s*\[[^\]]*\bunlabeled\b'
    }

    It 'sets bounded shared job runtimes and artifact retention' {
        $ci = Get-Content (Join-Path $script:workflowRoot 'module_ci.yml') -Raw
        $release = Get-Content (Join-Path $script:workflowRoot 'module_release.yml') -Raw

        $ci | Should -Match '(?ms)^  changes:.*?^    timeout-minutes:\s+10\r?$'
        $ci | Should -Match '(?ms)^  build:.*?^    timeout-minutes:\s+45\r?$'
        $ci | Should -Match '(?ms)^  test_windows_ps5:.*?^    timeout-minutes:\s+45\r?$'
        $ci | Should -Match '(?ms)^  test_pwsh:.*?^    timeout-minutes:\s+45\r?$'
        $ci | Should -Match '(?ms)^  smoke_tests:.*?^    timeout-minutes:\s+60\r?$'
        ([regex]::Matches($ci, 'retention-days:\s+14')).Count | Should -Be 4
        $release | Should -Match '(?ms)^  prepare:.*?^    timeout-minutes:\s+30\r?$'
        $release | Should -Match '(?ms)^  publish:.*?^    timeout-minutes:\s+45\r?$'
    }
}
