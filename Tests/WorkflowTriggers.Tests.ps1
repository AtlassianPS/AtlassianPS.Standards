#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.9.0"; MaximumVersion = "5.9.999" }

Describe 'GitHub Actions workflow triggers' -Tag 'Lint', 'Unit' {
    It 'starts continuous release only for completed CI runs on master' {
        $workflow = Get-Content "$PSScriptRoot/../.github/workflows/continuous_release.yml" -Raw

        $workflow | Should -Match '(?ms)workflow_run:.*?workflows:\s*\[CI\].*?types:\s*\[completed\].*?branches:\s*\[master\]'
    }
}
