#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../Helpers/TestTools.ps1"
    $script:projectRoot = Resolve-ProjectRoot
    $script:sourceScriptPath = Join-Path -Path $script:projectRoot -ChildPath 'Tools/update.dependencies.ps1'

    function Initialize-UpdateDependencyHarness {
        [CmdletBinding()]
        [OutputType([PSCustomObject])]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [String]
            $ModuleContent
        )

        $harnessRoot = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString())
        $toolsPath = Join-Path -Path $harnessRoot -ChildPath 'Tools'
        $modulePath = Join-Path -Path $harnessRoot -ChildPath 'AtlassianPS.Standards'

        $null = New-Item -Path $toolsPath -ItemType Directory -Force
        $null = New-Item -Path $modulePath -ItemType Directory -Force

        $scriptPath = Join-Path -Path $toolsPath -ChildPath 'update.dependencies.ps1'
        $moduleSourcePath = Join-Path -Path $modulePath -ChildPath 'AtlassianPS.Standards.psm1'

        Set-Content -LiteralPath $scriptPath -Value (Get-Content -LiteralPath $script:sourceScriptPath -Raw)
        Set-Content -LiteralPath $moduleSourcePath -Value $ModuleContent

        return [PSCustomObject]@{
            Root       = $harnessRoot
            ScriptPath = $scriptPath
        }
    }
}

Describe 'Tools/update.dependencies.ps1' {
    AfterEach {
        Get-Module -Name 'AtlassianPS.Standards' |
            Where-Object { $_.ModuleBase -like "$TestDrive*" } |
            Remove-Module -Force -ErrorAction SilentlyContinue
    }

    It 'invokes shared updater with expected default paths and switches' {
        $harness = Initialize-UpdateDependencyHarness -ModuleContent @'
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
        $harness = Initialize-UpdateDependencyHarness -ModuleContent @'
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
