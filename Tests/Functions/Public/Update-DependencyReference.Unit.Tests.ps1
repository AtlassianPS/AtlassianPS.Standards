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

    It 'provides comment-based help' {
        $help = Get-Help -Name 'Update-AtlassianPSDependencyReference' -ErrorAction Stop
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description.Text | Should -Not -BeNullOrEmpty
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
            $null = $BuildRequirementsPath

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
        @{ ModuleName = 'PSScriptAnalyzer'; RequiredVersion = '1.25.2' }
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
                    'PSScriptAnalyzer' { [PSCustomObject]@{ Version = [Version]'1.25.2' } }
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

    It 'does not cross a major-version boundary by default' {
        $buildRequirementsPath = Join-Path -Path $TestDrive -ChildPath 'build-major.requirements.psd1'
        Set-Content -LiteralPath $buildRequirementsPath -Value @'
@(
    @{ ModuleName = "Pester"; RequiredVersion = "5.7.1" }
)
'@

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuildRequirementsPath = $buildRequirementsPath
        } {
            param($BuildRequirementsPath)

            Mock -CommandName Find-Module -MockWith {
                @(
                    [PSCustomObject]@{ Version = '6.1.0' }
                    [PSCustomObject]@{ Version = '5.10.0' }
                    [PSCustomObject]@{ Version = '5.9.0' }
                )
            }

            $result = Update-DependencyReference `
                -BuildRequirementsPath $BuildRequirementsPath `
                -SkipManifestRequirement

            $result.BuildRequirementUpdated | Should -BeTrue
        }

        (Get-Content -LiteralPath $buildRequirementsPath -Raw) |
            Should -Match 'Pester"; RequiredVersion = "5.10.0"'
    }

    It 'can cross a major-version boundary when explicitly requested' {
        $buildRequirementsPath = Join-Path -Path $TestDrive -ChildPath 'build-major-opt-in.requirements.psd1'
        Set-Content -LiteralPath $buildRequirementsPath -Value @'
@(
    @{ ModuleName = "Pester"; RequiredVersion = "5.7.1" }
)
'@

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuildRequirementsPath = $buildRequirementsPath
        } {
            param($BuildRequirementsPath)

            Mock -CommandName Find-Module -MockWith {
                @(
                    [PSCustomObject]@{ Version = '6.1.0' }
                    [PSCustomObject]@{ Version = '5.10.0' }
                )
            }

            $result = Update-DependencyReference `
                -BuildRequirementsPath $BuildRequirementsPath `
                -SkipManifestRequirement `
                -AllowMajorVersionUpgrade

            $result.BuildRequirementUpdated | Should -BeTrue
        }

        (Get-Content -LiteralPath $buildRequirementsPath -Raw) |
            Should -Match 'Pester"; RequiredVersion = "6.1.0"'
    }

    It 'updates Standards workflow and consistency-test pins together' {
        $projectPath = Join-Path -Path $TestDrive -ChildPath 'project'
        $toolsPath = Join-Path -Path $projectPath -ChildPath 'Tools'
        $workflowPath = Join-Path -Path $projectPath -ChildPath '.github/workflows'
        $testsPath = Join-Path -Path $projectPath -ChildPath 'Tests/Tools'
        $null = New-Item -Path $toolsPath, $workflowPath, $testsPath -ItemType Directory -Force

        $buildRequirementsPath = Join-Path -Path $toolsPath -ChildPath 'build.requirements.psd1'
        $workflowFile = Join-Path -Path $workflowPath -ChildPath 'ci.yml'
        $buildFile = Join-Path -Path $projectPath -ChildPath 'Sample.build.ps1'
        $consistencyTest = Join-Path -Path $testsPath -ChildPath 'StandardsVersionConsistency.Unit.Tests.ps1'
        Set-Content -LiteralPath $buildRequirementsPath -Value @'
@(
    @{ ModuleName = "AtlassianPS.Standards"; RequiredVersion = "0.1.19" }
)
'@
        Set-Content -LiteralPath $workflowFile -Value 'uses: AtlassianPS/AtlassianPS.Standards/.github/actions/setup@1111111111111111111111111111111111111111 # v0.1.19'
        Set-Content -LiteralPath $buildFile -Value "#requires -modules @{ ModuleName = 'AtlassianPS.Standards'; ModuleVersion = '0.1.19'; MaximumVersion = '0.1.19' }"
        Set-Content -LiteralPath $consistencyTest -Value '$script:standardsActionSha = ''1111111111111111111111111111111111111111'''

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuildRequirementsPath = $buildRequirementsPath
        } {
            param($BuildRequirementsPath)

            Mock -CommandName Find-Module -MockWith {
                [PSCustomObject]@{ Version = '0.1.20' }
            }
            Mock -CommandName Invoke-RestMethod -MockWith {
                [PSCustomObject]@{ sha = '2222222222222222222222222222222222222222' }
            }

            $result = Update-DependencyReference `
                -BuildRequirementsPath $BuildRequirementsPath `
                -SkipManifestRequirement

            $result.StandardsReferenceUpdated | Should -BeTrue
        }

        Get-Content -LiteralPath $workflowFile -Raw |
            Should -Match '@2222222222222222222222222222222222222222 # v0\.1\.20'
        Get-Content -LiteralPath $buildFile -Raw |
            Should -Match "ModuleVersion = '0\.1\.20'; MaximumVersion = '0\.1\.20'"
        Get-Content -LiteralPath $consistencyTest -Raw |
            Should -Match "standardsActionSha = '2222222222222222222222222222222222222222'"
    }

    It 'repairs drifted Standards references when the dependency version is current' {
        $projectPath = Join-Path -Path $TestDrive -ChildPath 'drift-project'
        $toolsPath = Join-Path -Path $projectPath -ChildPath 'Tools'
        $workflowPath = Join-Path -Path $projectPath -ChildPath '.github/workflows'
        $null = New-Item -Path $toolsPath, $workflowPath -ItemType Directory -Force

        $buildRequirementsPath = Join-Path -Path $toolsPath -ChildPath 'build.requirements.psd1'
        $workflowFile = Join-Path -Path $workflowPath -ChildPath 'ci.yml'
        Set-Content -LiteralPath $buildRequirementsPath -Value '@(@{ ModuleName = "AtlassianPS.Standards"; RequiredVersion = "0.1.20" })'
        Set-Content -LiteralPath $workflowFile -Value 'uses: AtlassianPS/AtlassianPS.Standards/.github/actions/setup@1111111111111111111111111111111111111111 # v0.1.19'

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuildRequirementsPath = $buildRequirementsPath
        } {
            param($BuildRequirementsPath)

            Mock -CommandName Find-Module -MockWith {
                [PSCustomObject]@{ Version = '0.1.20' }
            }
            Mock -CommandName Invoke-RestMethod -MockWith {
                [PSCustomObject]@{ sha = '2222222222222222222222222222222222222222' }
            }

            $result = Update-DependencyReference `
                -BuildRequirementsPath $BuildRequirementsPath `
                -SkipManifestRequirement

            $result.BuildRequirementUpdated | Should -BeFalse
            $result.StandardsReferenceUpdated | Should -BeTrue
        }

        Get-Content -LiteralPath $workflowFile -Raw |
            Should -Match '@2222222222222222222222222222222222222222 # v0\.1\.20'
    }

    It 'does not update Standards references with WhatIf' {
        $projectPath = Join-Path -Path $TestDrive -ChildPath 'whatif-project'
        $toolsPath = Join-Path -Path $projectPath -ChildPath 'Tools'
        $workflowPath = Join-Path -Path $projectPath -ChildPath '.github/workflows'
        $testsPath = Join-Path -Path $projectPath -ChildPath 'Tests/Tools'
        $null = New-Item -Path $toolsPath, $workflowPath, $testsPath -ItemType Directory -Force

        $buildRequirementsPath = Join-Path -Path $toolsPath -ChildPath 'build.requirements.psd1'
        $manifestPath = Join-Path -Path $projectPath -ChildPath 'Sample.psd1'
        $workflowFile = Join-Path -Path $workflowPath -ChildPath 'ci.yml'
        $buildFile = Join-Path -Path $projectPath -ChildPath 'Sample.build.ps1'
        $consistencyTest = Join-Path -Path $testsPath -ChildPath 'StandardsVersionConsistency.Unit.Tests.ps1'
        Set-Content -LiteralPath $buildRequirementsPath -Value '@(@{ ModuleName = "AtlassianPS.Standards"; RequiredVersion = "0.1.19" })'
        Set-Content -LiteralPath $manifestPath -Value '@{ RequiredModules = @(@{ ModuleName = "PSScriptAnalyzer"; RequiredVersion = "1.25.0" }) }'
        Set-Content -LiteralPath $workflowFile -Value 'uses: AtlassianPS/AtlassianPS.Standards/.github/actions/setup@1111111111111111111111111111111111111111 # v0.1.19'
        Set-Content -LiteralPath $buildFile -Value "#requires -modules @{ ModuleName = 'AtlassianPS.Standards'; ModuleVersion = '0.1.19'; MaximumVersion = '0.1.19' }"
        Set-Content -LiteralPath $consistencyTest -Value '$script:standardsActionSha = ''1111111111111111111111111111111111111111'''

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuildRequirementsPath = $buildRequirementsPath
            ManifestPath          = $manifestPath
        } {
            param($BuildRequirementsPath, $ManifestPath)

            Mock -CommandName Find-Module -MockWith {
                param([String]$Name)
                switch ($Name) {
                    'AtlassianPS.Standards' { [PSCustomObject]@{ Version = '0.1.20' } }
                    'PSScriptAnalyzer' { [PSCustomObject]@{ Version = '1.25.2' } }
                    default { throw "Unexpected module lookup: $Name" }
                }
            }
            Mock -CommandName Invoke-RestMethod -MockWith {
                [PSCustomObject]@{ sha = '2222222222222222222222222222222222222222' }
            }

            $result = Update-DependencyReference `
                -BuildRequirementsPath $BuildRequirementsPath `
                -ManifestPath $ManifestPath `
                -WhatIf

            $result.BuildRequirementUpdated | Should -BeFalse
            $result.ManifestUpdated | Should -BeFalse
            $result.StandardsReferenceUpdated | Should -BeFalse
            $result.UpdatedModuleCount | Should -Be 0
            $result.UpdatedModuleName | Should -BeNullOrEmpty
            $result.UpdateDetail | Should -BeNullOrEmpty
        }

        Get-Content -LiteralPath $workflowFile -Raw |
            Should -Match '@1111111111111111111111111111111111111111 # v0\.1\.19'
        Get-Content -LiteralPath $buildFile -Raw |
            Should -Match "ModuleVersion = '0\.1\.19'; MaximumVersion = '0\.1\.19'"
        Get-Content -LiteralPath $consistencyTest -Raw |
            Should -Match "standardsActionSha = '1111111111111111111111111111111111111111'"
        Get-Content -LiteralPath $buildRequirementsPath -Raw |
            Should -Match 'RequiredVersion = "0\.1\.19"'
        Get-Content -LiteralPath $manifestPath -Raw |
            Should -Match 'RequiredVersion = "1\.25\.0"'
    }

    It 'throws when module lookup fails by default' {
        $buildRequirementsPath = Join-Path -Path $TestDrive -ChildPath 'build-lookup-error.requirements.psd1'
        Set-Content -LiteralPath $buildRequirementsPath -Value @'
@(
    @{ ModuleName = "InvokeBuild"; RequiredVersion = "5.14.23" }
)
'@

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuildRequirementsPath = $buildRequirementsPath
        } {
            param($BuildRequirementsPath)
            $null = $BuildRequirementsPath

            Mock -CommandName Find-Module -MockWith {
                throw 'network lookup failed'
            }

            {
                Update-DependencyReference `
                    -BuildRequirementsPath $BuildRequirementsPath `
                    -SkipManifestRequirement
            } | Should -Throw -ExpectedMessage '*Unable to resolve latest version for module ''InvokeBuild''*'
        }
    }

    It 'can continue when lookup fails with explicit opt-out' {
        $buildRequirementsPath = Join-Path -Path $TestDrive -ChildPath 'build-lookup-warning.requirements.psd1'
        Set-Content -LiteralPath $buildRequirementsPath -Value @'
@(
    @{ ModuleName = "InvokeBuild"; RequiredVersion = "5.14.23" }
)
'@

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuildRequirementsPath = $buildRequirementsPath
        } {
            param($BuildRequirementsPath)

            Mock -CommandName Find-Module -MockWith {
                throw 'network lookup failed'
            }

            $result = Update-DependencyReference `
                -BuildRequirementsPath $BuildRequirementsPath `
                -SkipManifestRequirement `
                -AllowLookupFailure

            $result.BuildRequirementUpdated | Should -BeFalse
            $result.UpdatedModuleCount | Should -Be 0
        }
    }

    It 'keeps the Standards version when its release SHA lookup fails with explicit opt-out' {
        $projectPath = Join-Path -Path $TestDrive -ChildPath 'lookup-warning-project'
        $toolsPath = Join-Path -Path $projectPath -ChildPath 'Tools'
        $workflowPath = Join-Path -Path $projectPath -ChildPath '.github/workflows'
        $null = New-Item -Path $toolsPath, $workflowPath -ItemType Directory -Force

        $buildRequirementsPath = Join-Path -Path $toolsPath -ChildPath 'build.requirements.psd1'
        $workflowFile = Join-Path -Path $workflowPath -ChildPath 'ci.yml'
        Set-Content -LiteralPath $buildRequirementsPath -Value '@(@{ ModuleName = "AtlassianPS.Standards"; RequiredVersion = "0.1.19" })'
        Set-Content -LiteralPath $workflowFile -Value 'uses: AtlassianPS/AtlassianPS.Standards/.github/actions/setup@1111111111111111111111111111111111111111 # v0.1.19'

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuildRequirementsPath = $buildRequirementsPath
        } {
            param($BuildRequirementsPath)

            Mock -CommandName Find-Module -MockWith {
                [PSCustomObject]@{ Version = '0.1.20' }
            }
            Mock -CommandName Invoke-RestMethod -MockWith {
                throw 'release tag is unavailable'
            }

            $result = Update-DependencyReference `
                -BuildRequirementsPath $BuildRequirementsPath `
                -SkipManifestRequirement `
                -AllowLookupFailure

            $result.BuildRequirementUpdated | Should -BeFalse
            $result.StandardsReferenceUpdated | Should -BeFalse
            $result.UpdatedModuleCount | Should -Be 0
        }

        Get-Content -LiteralPath $buildRequirementsPath -Raw |
            Should -Match 'RequiredVersion = "0\.1\.19"'
        Get-Content -LiteralPath $workflowFile -Raw |
            Should -Match '@1111111111111111111111111111111111111111 # v0\.1\.19'
    }

    It 'keeps a ModuleVersion Standards pin when SHA lookup fails and another dependency updates' {
        $projectPath = Join-Path -Path $TestDrive -ChildPath 'module-version-rollback-project'
        $toolsPath = Join-Path -Path $projectPath -ChildPath 'Tools'
        $workflowPath = Join-Path -Path $projectPath -ChildPath '.github/workflows'
        $null = New-Item -Path $toolsPath, $workflowPath -ItemType Directory -Force

        $buildRequirementsPath = Join-Path -Path $toolsPath -ChildPath 'build.requirements.psd1'
        $workflowFile = Join-Path -Path $workflowPath -ChildPath 'ci.yml'
        Set-Content -LiteralPath $buildRequirementsPath -Value @'
@(
    @{ ModuleName = "AtlassianPS.Standards"; ModuleVersion = "0.1.19" }
    @{ ModuleName = "InvokeBuild"; RequiredVersion = "5.14.23" }
)
'@
        Set-Content -LiteralPath $workflowFile -Value 'uses: AtlassianPS/AtlassianPS.Standards/.github/actions/setup@1111111111111111111111111111111111111111 # v0.1.19'

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuildRequirementsPath = $buildRequirementsPath
        } {
            param($BuildRequirementsPath)

            Mock -CommandName Find-Module -MockWith {
                param([String]$Name)
                switch ($Name) {
                    'AtlassianPS.Standards' { [PSCustomObject]@{ Version = '0.1.20' } }
                    'InvokeBuild' { [PSCustomObject]@{ Version = '5.14.30' } }
                    default { throw "Unexpected module lookup: $Name" }
                }
            }
            Mock -CommandName Invoke-RestMethod -MockWith {
                throw 'release tag is unavailable'
            }

            $result = Update-DependencyReference `
                -BuildRequirementsPath $BuildRequirementsPath `
                -SkipManifestRequirement `
                -AllowLookupFailure

            $result.BuildRequirementUpdated | Should -BeTrue
            $result.UpdatedModuleName | Should -Contain 'InvokeBuild'
            $result.UpdatedModuleName | Should -Not -Contain 'AtlassianPS.Standards'
        }

        Get-Content -LiteralPath $buildRequirementsPath -Raw |
            Should -Match 'AtlassianPS\.Standards"; RequiredVersion = "0\.1\.19"'
        Get-Content -LiteralPath $buildRequirementsPath -Raw |
            Should -Match 'InvokeBuild"; RequiredVersion = "5\.14\.30"'
        Get-Content -LiteralPath $workflowFile -Raw |
            Should -Match '@1111111111111111111111111111111111111111 # v0\.1\.19'
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
