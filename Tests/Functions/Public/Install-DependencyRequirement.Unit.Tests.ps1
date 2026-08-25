#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"
    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Install-DependencyRequirement' {
    It 'is exported by the module' {
        $command = Get-Command -Name 'Install-AtlassianPSDependencyRequirement' -ErrorAction SilentlyContinue
        $command | Should -Not -BeNullOrEmpty
    }

    It 'provides comment-based help' {
        $help = Get-Help -Name 'Install-AtlassianPSDependencyRequirement' -ErrorAction Stop
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description.Text | Should -Not -BeNullOrEmpty
    }

    It 'installs missing requirements and skips already installed versions' {
        $buildRequirementsPath = Join-Path -Path $TestDrive -ChildPath 'build.requirements.psd1'
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module.psd1'

        Set-Content -LiteralPath $buildRequirementsPath -Value @'
@(
    @{ ModuleName = "InvokeBuild"; RequiredVersion = "5.14.23" }
    @{ ModuleName = "Pester"; RequiredVersion = "5.7.1" }
)
'@
        Set-Content -LiteralPath $manifestPath -Value @'
@{
    RequiredModules = @(
        @{ ModuleName = 'PSScriptAnalyzer'; RequiredVersion = '1.25.0' }
        @{ ModuleName = 'Pester'; RequiredVersion = '5.7.1' }
    )
}
'@

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuildRequirementsPath = $buildRequirementsPath
            ManifestPath          = $manifestPath
        } {
            param($BuildRequirementsPath, $ManifestPath)

            Mock -CommandName Get-PSRepository -MockWith { [PSCustomObject]@{ Name = 'PSGallery' } }
            Mock -CommandName Get-Module -MockWith {
                param([String]$Name)
                if ($Name -eq 'Pester') {
                    return [PSCustomObject]@{ Version = [Version]'5.7.1' }
                }

                return @()
            }
            Mock -CommandName Install-Module -MockWith { }

            $result = Install-DependencyRequirement -BuildRequirementsPath $BuildRequirementsPath -ManifestPath $ManifestPath

            $result.TotalRequirementCount | Should -Be 3
            $result.InstalledCount | Should -Be 2
            $result.AlreadyPresentCount | Should -Be 1

            Should -Invoke -CommandName Install-Module -Scope It -Times 2 -Exactly
            Should -Invoke -CommandName Install-Module -Scope It -ParameterFilter {
                $Name -eq 'InvokeBuild' -and $RequiredVersion -eq '5.14.23' -and $SkipPublisherCheck
            }
            Should -Invoke -CommandName Install-Module -Scope It -ParameterFilter {
                $Name -eq 'PSScriptAnalyzer' -and $RequiredVersion -eq '1.25.0' -and $SkipPublisherCheck
            }
        }
    }

    It 'throws for PSDepend hashtable build requirements' {
        $buildRequirementsPath = Join-Path -Path $TestDrive -ChildPath 'build-hashtable.requirements.psd1'
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module.psd1'

        Set-Content -LiteralPath $buildRequirementsPath -Value @'
@{
    PSDependOptions = @{
        Target = 'CurrentUser'
    }
}
'@
        Set-Content -LiteralPath $manifestPath -Value @'
@{
    RequiredModules = @()
}
'@

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuildRequirementsPath = $buildRequirementsPath
            ManifestPath          = $manifestPath
        } {
            param($BuildRequirementsPath, $ManifestPath)

            {
                Install-DependencyRequirement -BuildRequirementsPath $BuildRequirementsPath -ManifestPath $ManifestPath
            } | Should -Throw -ExpectedMessage '*Unsupported build requirements format*'
        }
    }

    It 'supports array requirements with comments and reordered keys' {
        $buildRequirementsPath = Join-Path -Path $TestDrive -ChildPath 'build-commented.requirements.psd1'
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-commented.psd1'

        Set-Content -LiteralPath $buildRequirementsPath -Value @'
@(
    # comment before requirement
    @{
        RequiredVersion = "5.14.23"
        ModuleName = "InvokeBuild"
    }
)
'@
        Set-Content -LiteralPath $manifestPath -Value @'
@{
    RequiredModules = @()
}
'@

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuildRequirementsPath = $buildRequirementsPath
            ManifestPath          = $manifestPath
        } {
            param($BuildRequirementsPath, $ManifestPath)

            Mock -CommandName Get-PSRepository -MockWith { [PSCustomObject]@{ Name = 'PSGallery' } }
            Mock -CommandName Get-Module -MockWith { @() }
            Mock -CommandName Install-Module -MockWith { }

            $result = Install-DependencyRequirement -BuildRequirementsPath $BuildRequirementsPath -ManifestPath $ManifestPath

            $result.TotalRequirementCount | Should -Be 1
            $result.InstalledCount | Should -Be 1
            Should -Invoke -CommandName Install-Module -Scope It -Times 1 -Exactly
        }
    }
}
