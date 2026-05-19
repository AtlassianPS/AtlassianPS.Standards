#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../Helpers/TestTools.ps1"
    $script:projectRoot = Resolve-ProjectRoot
    $script:sourceScriptPath = Join-Path -Path $script:projectRoot -ChildPath 'Tools/setup.ps1'

    function Initialize-SetupHarness {
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

        $scriptPath = Join-Path -Path $toolsPath -ChildPath 'setup.ps1'
        $moduleSourcePath = Join-Path -Path $modulePath -ChildPath 'AtlassianPS.Standards.psm1'

        Set-Content -LiteralPath $scriptPath -Value (Get-Content -LiteralPath $script:sourceScriptPath -Raw)
        Set-Content -LiteralPath $moduleSourcePath -Value $ModuleContent

        return [PSCustomObject]@{
            Root       = $harnessRoot
            ScriptPath = $scriptPath
        }
    }
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
        $harness = Initialize-SetupHarness -ModuleContent @"
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
        $harness = Initialize-SetupHarness -ModuleContent @'
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
