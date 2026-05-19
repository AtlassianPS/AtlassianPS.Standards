#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../Helpers/TestTools.ps1"
}

Describe 'Tools/update.dependencies.ps1' {
    AfterEach {
        Get-Module -Name 'AtlassianPS.Standards' |
            Where-Object { $_.ModuleBase -like "$TestDrive*" } |
            Remove-Module -Force -ErrorAction SilentlyContinue
    }

    It 'invokes shared updater with expected default paths and switches' {
        $harness = Initialize-ToolScriptHarness -ScriptRelativePath 'Tools/update.dependencies.ps1' -ModuleContent @'
function Update-DependencyReference {
    [CmdletBinding()]
    param(
        [String]$BuildRequirementsPath,
        [String]$ManifestPath,
        [Switch]$SkipBuildRequirement,
        [Switch]$SkipManifestRequirement
    )

    [PSCustomObject]@{
        BuildRequirementsPath  = $BuildRequirementsPath
        ManifestPath           = $ManifestPath
        SkipBuildRequirement   = [Boolean]$SkipBuildRequirement
        SkipManifestRequirement = [Boolean]$SkipManifestRequirement
    }
}

Export-ModuleMember -Function Update-DependencyReference
'@

        $result = & $harness.ScriptPath -SkipBuildRequirement -SkipManifestRequirement

        $result.BuildRequirementsPath | Should -Be (Join-Path -Path $harness.Root -ChildPath 'Tools/build.requirements.psd1')
        $result.ManifestPath | Should -Be (Join-Path -Path $harness.Root -ChildPath 'AtlassianPS.Standards/AtlassianPS.Standards.psd1')
        $result.SkipBuildRequirement | Should -BeTrue
        $result.SkipManifestRequirement | Should -BeTrue
    }

    It 'fails fast when shared updater emits a non-terminating error' {
        $harness = Initialize-ToolScriptHarness -ScriptRelativePath 'Tools/update.dependencies.ps1' -ModuleContent @'
function Update-DependencyReference {
    [CmdletBinding()]
    param(
        [String]$BuildRequirementsPath,
        [String]$ManifestPath,
        [Switch]$SkipBuildRequirement,
        [Switch]$SkipManifestRequirement
    )

    Write-Error -Message 'simulated updater failure'
}

Export-ModuleMember -Function Update-DependencyReference
'@

        {
            & $harness.ScriptPath -SkipBuildRequirement -SkipManifestRequirement
        } | Should -Throw -ExpectedMessage '*simulated updater failure*'
    }
}
