#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"
    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Update-DependencyReference' {
    It 'is exported by the module' {
        $command = Get-Command -Name 'Update-AtlassianPSDependencyReference' -ErrorAction SilentlyContinue
        $command | Should -Not -BeNullOrEmpty
    }

    It 'updates array build requirements and manifest requirements' {
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
        @{ ModuleName = 'Metadata'; RequiredVersion = '1.5.7' }
        @{ ModuleName = 'PSScriptAnalyzer'; RequiredVersion = '1.25.0' }
    )
}
'@
        InModuleScope AtlassianPS.Standards -Parameters @{
            BuildRequirementsPath = $buildRequirementsPath
            ManifestPath          = $manifestPath
        } {
            param($BuildRequirementsPath, $ManifestPath)

            Mock -CommandName Find-Module -MockWith {
                param([String]$Name)
                switch ($Name) {
                    'InvokeBuild' { [PSCustomObject]@{ Version = [Version]'5.14.30' } }
                    'Pester' { [PSCustomObject]@{ Version = [Version]'5.7.2' } }
                    'Metadata' { [PSCustomObject]@{ Version = [Version]'1.5.8' } }
                    'PSScriptAnalyzer' { [PSCustomObject]@{ Version = [Version]'1.25.2' } }
                    default { throw "Unexpected module lookup: $Name" }
                }
            }
            $result = Update-DependencyReference `
                -BuildRequirementsPath $BuildRequirementsPath `
                -ManifestPath $ManifestPath

            $result.BuildRequirementUpdated | Should -BeTrue
            $result.ManifestUpdated | Should -BeTrue
            $result.UpdatedModuleName | Should -Contain 'InvokeBuild'
            $result.UpdatedModuleName | Should -Contain 'PSScriptAnalyzer'
        }

        (Get-Content -LiteralPath $buildRequirementsPath -Raw) | Should -Match 'InvokeBuild"; RequiredVersion = "5.14.30"'
        (Get-Content -LiteralPath $buildRequirementsPath -Raw) | Should -Match 'Pester"; RequiredVersion = "5.7.2"'
        (Get-Content -LiteralPath $manifestPath -Raw) | Should -Match "Metadata'; RequiredVersion = '1.5.8'"
        (Get-Content -LiteralPath $manifestPath -Raw) | Should -Match "PSScriptAnalyzer'; RequiredVersion = '1.25.2'"
    }

    It 'throws for PSDepend hashtable build requirements' {
        $buildRequirementsPath = Join-Path -Path $TestDrive -ChildPath 'build-hashtable.requirements.psd1'
        Set-Content -LiteralPath $buildRequirementsPath -Value @'
@{
    PSDependOptions = @{
        Target = 'CurrentUser'
    }
    InvokeBuild = @{
        Version = "5.14.20"
    }
    Pester = "latest"
}
'@

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuildRequirementsPath = $buildRequirementsPath
        } {
            param($BuildRequirementsPath)

            {
                Update-DependencyReference `
                    -BuildRequirementsPath $BuildRequirementsPath `
                    -SkipManifestRequirement
            } | Should -Throw -ExpectedMessage '*PSDepend hashtable format is no longer supported*'
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

            Mock -CommandName Find-Module -MockWith {
                [PSCustomObject]@{ Version = [Version]'5.14.30' }
            }

            $result = Update-DependencyReference `
                -BuildRequirementsPath $BuildRequirementsPath `
                -ManifestPath $ManifestPath

            $result.BuildRequirementUpdated | Should -BeTrue
        }

        (Get-Content -LiteralPath $buildRequirementsPath -Raw) | Should -Match 'ModuleName = "InvokeBuild"; RequiredVersion = "5.14.30"'
    }

    It 'returns no updates when all versions are already current' {
        $buildRequirementsPath = Join-Path -Path $TestDrive -ChildPath 'build-current.requirements.psd1'
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'manifest-current.psd1'

        Set-Content -LiteralPath $buildRequirementsPath -Value @'
@(
    @{ ModuleName = "InvokeBuild"; RequiredVersion = "5.14.30" }
)
'@
        Set-Content -LiteralPath $manifestPath -Value @'
@{
    RequiredModules = @(
        @{ ModuleName = 'Metadata'; RequiredVersion = '1.5.8' }
    )
}
'@
        InModuleScope AtlassianPS.Standards -Parameters @{
            BuildRequirementsPath = $buildRequirementsPath
            ManifestPath          = $manifestPath
        } {
            param($BuildRequirementsPath, $ManifestPath)

            Mock -CommandName Find-Module -MockWith {
                param([String]$Name)
                switch ($Name) {
                    'InvokeBuild' { [PSCustomObject]@{ Version = [Version]'5.14.30' } }
                    'Metadata' { [PSCustomObject]@{ Version = [Version]'1.5.8' } }
                    default { throw "Unexpected module lookup: $Name" }
                }
            }
            $result = Update-DependencyReference `
                -BuildRequirementsPath $BuildRequirementsPath `
                -ManifestPath $ManifestPath

            $result.BuildRequirementUpdated | Should -BeFalse
            $result.ManifestUpdated | Should -BeFalse
            $result.UpdatedModuleCount | Should -Be 0
        }
    }

    It 'uses default repository paths when explicit paths are omitted' {
        InModuleScope AtlassianPS.Standards {
            Mock -CommandName Find-Module -MockWith {
                [PSCustomObject]@{ Version = [Version]'0.0.0' }
            }

            $result = Update-DependencyReference

            $result.BuildRequirementUpdated | Should -BeFalse
            $result.ManifestUpdated | Should -BeFalse
        }
    }
}
