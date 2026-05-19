#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../Helpers/TestTools.ps1"
}

Describe 'Tools/setup.ps1' {
    AfterEach {
        Get-Module -Name 'AtlassianPS.Standards' |
            Where-Object { $_.ModuleBase -like "$TestDrive*" } |
            Remove-Module -Force -ErrorAction SilentlyContinue
    }

    It 'invokes shared installer with expected default paths' {
        $capturePath = Join-Path -Path $TestDrive -ChildPath 'setup-args.json'
        $escapedCapturePath = $capturePath.Replace("'", "''")
        $harness = Initialize-ToolScriptHarness -ScriptRelativePath 'Tools/setup.ps1' -ModuleContent @"
function Install-DependencyRequirement {
    [CmdletBinding()]
    param(
        [String]`$BuildRequirementsPath,
        [String]`$ManifestPath
    )

    [PSCustomObject]@{
        BuildRequirementsPath = `$BuildRequirementsPath
        ManifestPath          = `$ManifestPath
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath '$escapedCapturePath'
}

Export-ModuleMember -Function Install-DependencyRequirement
"@

        & $harness.ScriptPath

        $captured = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json
        $captured.BuildRequirementsPath | Should -Be (Join-Path -Path $harness.Root -ChildPath 'Tools/build.requirements.psd1')
        $captured.ManifestPath | Should -Be (Join-Path -Path $harness.Root -ChildPath 'AtlassianPS.Standards/AtlassianPS.Standards.psd1')
    }

    It 'fails fast when shared installer emits a non-terminating error' {
        $harness = Initialize-ToolScriptHarness -ScriptRelativePath 'Tools/setup.ps1' -ModuleContent @'
function Install-DependencyRequirement {
    [CmdletBinding()]
    param(
        [String]$BuildRequirementsPath,
        [String]$ManifestPath
    )

    Write-Error -Message 'simulated setup failure'
}

Export-ModuleMember -Function Install-DependencyRequirement
'@

        {
            & $harness.ScriptPath
        } | Should -Throw -ExpectedMessage '*simulated setup failure*'
    }
}
