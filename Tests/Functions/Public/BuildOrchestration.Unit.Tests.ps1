#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"
    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Invoke-ModuleTests' {
    It 'merges tag filters and clears excluded paths for Integration runs' {
        $testsPath = Join-Path -Path $TestDrive -ChildPath 'tests'
        $null = New-Item -Path $testsPath -ItemType Directory -Force

        InModuleScope AtlassianPS.Standards -Parameters @{
            TestPath = $testsPath
        } {
            param($TestPath)

            Mock -CommandName Import-PesterVersion -MockWith {}
            Mock -CommandName New-PesterConfiguration -MockWith {
                param($Hashtable)
                $script:capturedPesterConfig = $Hashtable
                return $Hashtable
            }
            Mock -CommandName Invoke-Pester -MockWith {
                [PSCustomObject]@{
                    FailedCount           = 0
                    ContainersFailedCount = 0
                }
            }

            $null = Invoke-ModuleTests `
                -TestPath $TestPath `
                -Tag @('Integration') `
                -ExcludeTag @('Unit') `
                -ExcludePath @('Tests/Integration')

            $script:capturedPesterConfig.Filter.Tag | Should -Contain 'Integration'
            $script:capturedPesterConfig.Filter.ExcludeTag | Should -Contain 'Unit'
            $script:capturedPesterConfig.Filter.ExcludeTag | Should -Not -Contain 'Integration'
            @($script:capturedPesterConfig.Run.ExcludePath).Count | Should -Be 0
        }
    }

    It 'throws when pester returns failures' {
        $testsPath = Join-Path -Path $TestDrive -ChildPath 'tests-failure'
        $null = New-Item -Path $testsPath -ItemType Directory -Force

        InModuleScope AtlassianPS.Standards -Parameters @{
            TestPath = $testsPath
        } {
            param($TestPath)

            Mock -CommandName Import-PesterVersion -MockWith {}
            Mock -CommandName New-PesterConfiguration -MockWith { param($Hashtable) $Hashtable }
            Mock -CommandName Invoke-Pester -MockWith {
                [PSCustomObject]@{
                    FailedCount           = 1
                    ContainersFailedCount = 0
                }
            }

            { Invoke-ModuleTests -TestPath $TestPath } | Should -Throw -ExpectedMessage 'Pester reported failures*'
        }
    }

    It 'computes default output path when BHProjectPath is not set' {
        $testsPath = Join-Path -Path $TestDrive -ChildPath 'tests-default-output'
        $null = New-Item -Path $testsPath -ItemType Directory -Force

        InModuleScope AtlassianPS.Standards -Parameters @{
            TestPath = $testsPath
        } {
            param($TestPath)

            $env:BHProjectPath = $null

            Mock -CommandName Import-PesterVersion -MockWith {}
            Mock -CommandName Get-HostPlatformInfo -MockWith {
                [PSCustomObject]@{
                    OS        = 'Linux'
                    OSVersion = '1.0'
                }
            }
            Mock -CommandName New-PesterConfiguration -MockWith {
                param($Hashtable)
                $script:capturedPesterConfig = $Hashtable
                return $Hashtable
            }
            Mock -CommandName Invoke-Pester -MockWith {
                [PSCustomObject]@{
                    FailedCount = 0
                }
            }

            $null = Invoke-ModuleTests -TestPath $TestPath

            $script:capturedPesterConfig.TestResult.OutputPath | Should -Match 'Test-Linux-'
            $script:capturedPesterConfig.TestResult.OutputPath | Should -Match ([regex]::Escape($TestDrive))
        }
    }
}

Describe 'Set-ModuleManifestVersion' {
    It 'updates module version, prerelease metadata, and release notes' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module.psd1'
        Set-Content -LiteralPath $manifestPath -Value "@{ ModuleVersion = '0.1.0' }"

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuiltManifestPath = $manifestPath
        } {
            param($BuiltManifestPath)

            Mock -CommandName Get-Command -MockWith {
                [PSCustomObject]@{ Name = 'Metadata\Update-Metadata' }
            } -ParameterFilter { $Name -eq 'Metadata\Update-Metadata' }
            Mock -CommandName Find-Module -MockWith { $null }
            Mock -CommandName 'Metadata\Update-Metadata' -MockWith {}

            $version = Set-ModuleManifestVersion `
                -BuiltManifestPath $BuiltManifestPath `
                -ModuleName 'AtlassianPS.Standards' `
                -VersionToPublish 'v1.2.3-alpha' `
                -ReleaseNotes '- Added dependency flow'

            $version | Should -Be '1.2.3'
            Should -Invoke -CommandName 'Metadata\Update-Metadata' -Times 3 -Exactly -Scope It
            Should -Invoke -CommandName 'Metadata\Update-Metadata' -Scope It -ParameterFilter {
                $PropertyName -eq 'ModuleVersion' -and $Value -eq '1.2.3'
            }
            Should -Invoke -CommandName 'Metadata\Update-Metadata' -Scope It -ParameterFilter {
                $PropertyName -eq 'Prerelease' -and $Value -eq 'alpha'
            }
            Should -Invoke -CommandName 'Metadata\Update-Metadata' -Scope It -ParameterFilter {
                $PropertyName -eq 'ReleaseNotes' -and $Value -eq '- Added dependency flow'
            }
        }
    }

    It 'throws when the version is not higher than published' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-published.psd1'
        Set-Content -LiteralPath $manifestPath -Value "@{ ModuleVersion = '0.1.0' }"

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuiltManifestPath = $manifestPath
        } {
            param($BuiltManifestPath)

            Mock -CommandName Get-Command -MockWith {
                [PSCustomObject]@{ Name = 'Metadata\Update-Metadata' }
            } -ParameterFilter { $Name -eq 'Metadata\Update-Metadata' }
            Mock -CommandName Find-Module -MockWith {
                [PSCustomObject]@{
                    Version = [Version]'1.2.3'
                }
            }

            {
                Set-ModuleManifestVersion -BuiltManifestPath $BuiltManifestPath -ModuleName 'AtlassianPS.Standards' -VersionToPublish '1.2.3'
            } | Should -Throw -ExpectedMessage 'Version must be greater than latest published version*'
        }
    }

    It 'clears prerelease metadata for stable versions' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-stable.psd1'
        Set-Content -LiteralPath $manifestPath -Value "@{ ModuleVersion = '0.1.0' }"

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuiltManifestPath = $manifestPath
        } {
            param($BuiltManifestPath)

            Mock -CommandName Get-Command -MockWith {
                [PSCustomObject]@{ Name = 'Metadata\Update-Metadata' }
            } -ParameterFilter { $Name -eq 'Metadata\Update-Metadata' }
            Mock -CommandName Find-Module -MockWith { $null }
            Mock -CommandName 'Metadata\Update-Metadata' -MockWith {}

            $null = Set-ModuleManifestVersion -BuiltManifestPath $BuiltManifestPath -ModuleName 'AtlassianPS.Standards' -VersionToPublish '1.2.4'

            Should -Invoke -CommandName 'Metadata\Update-Metadata' -Scope It -ParameterFilter {
                $PropertyName -eq 'Prerelease' -and $Value -eq ''
            }
        }
    }

    It 'throws when metadata tooling command is missing' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-no-metadata-cmd.psd1'
        Set-Content -LiteralPath $manifestPath -Value "@{ ModuleVersion = '0.1.0' }"

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuiltManifestPath = $manifestPath
        } {
            param($BuiltManifestPath)

            Mock -CommandName Get-Command -MockWith { $null } -ParameterFilter { $Name -eq 'Metadata\Update-Metadata' }

            {
                Set-ModuleManifestVersion -BuiltManifestPath $BuiltManifestPath -ModuleName 'AtlassianPS.Standards' -VersionToPublish '1.2.5'
            } | Should -Throw -ExpectedMessage 'Metadata\Update-Metadata is not available*'
        }
    }

    It 'throws when release notes are blank' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-empty-release-notes.psd1'
        Set-Content -LiteralPath $manifestPath -Value "@{ ModuleVersion = '0.1.0' }"

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuiltManifestPath = $manifestPath
        } {
            param($BuiltManifestPath)

            Mock -CommandName Get-Command -MockWith {
                [PSCustomObject]@{ Name = 'Metadata\Update-Metadata' }
            } -ParameterFilter { $Name -eq 'Metadata\Update-Metadata' }
            Mock -CommandName Find-Module -MockWith { $null }

            {
                Set-ModuleManifestVersion `
                    -BuiltManifestPath $BuiltManifestPath `
                    -ModuleName 'AtlassianPS.Standards' `
                    -VersionToPublish '1.2.6' `
                    -ReleaseNotes '   '
            } | Should -Throw -ExpectedMessage 'ReleaseNotes cannot be empty when provided.'
        }
    }
}

Describe 'Update-ModuleManifestExports' {
    It 'updates functions and aliases in the built manifest' {
        $sourceModulePath = Join-Path -Path $TestDrive -ChildPath 'AtlassianPS.Standards'
        $publicPath = Join-Path -Path $sourceModulePath -ChildPath 'Public'
        $builtManifestPath = Join-Path -Path $TestDrive -ChildPath 'built.psd1'
        $sourceManifestPath = Join-Path -Path $sourceModulePath -ChildPath 'AtlassianPS.Standards.psd1'

        $null = New-Item -Path $publicPath -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path -Path $publicPath -ChildPath 'Get-Thing.ps1') -Value 'function Get-Thing { }'
        Set-Content -LiteralPath (Join-Path -Path $publicPath -ChildPath 'Set-Thing.ps1') -Value 'function Set-Thing { }'
        Set-Content -LiteralPath $sourceManifestPath -Value "@{ RootModule = 'AtlassianPS.Standards.psm1' }"
        Set-Content -LiteralPath $builtManifestPath -Value "@{ ModuleVersion = '0.1.0' }"

        InModuleScope AtlassianPS.Standards -Parameters @{
            SourceModulePath  = $sourceModulePath
            BuiltManifestPath = $builtManifestPath
        } {
            param($SourceModulePath, $BuiltManifestPath)

            Mock -CommandName Get-Command -MockWith {
                [PSCustomObject]@{ Name = 'Metadata\Update-Metadata' }
            } -ParameterFilter { $Name -eq 'Metadata\Update-Metadata' }
            Mock -CommandName Test-ModuleManifest -MockWith {
                [PSCustomObject]@{
                    ExportedAliases = @{
                        gt = 'Get-Thing'
                    }
                }
            }
            Mock -CommandName 'Metadata\Update-Metadata' -MockWith {}

            $result = Update-ModuleManifestExports `
                -SourceModulePath $SourceModulePath `
                -BuiltManifestPath $BuiltManifestPath `
                -ModuleName 'AtlassianPS.Standards'

            $result.FunctionsToExport | Should -Contain 'Get-Thing'
            $result.FunctionsToExport | Should -Contain 'Set-Thing'
            $result.AliasesToExport | Should -Contain 'gt'
            Should -Invoke -CommandName 'Metadata\Update-Metadata' -Times 3 -Exactly -Scope It
        }
    }

    It 'throws when metadata tooling is not available' {
        $sourceModulePath = Join-Path -Path $TestDrive -ChildPath 'AtlassianPS.Standards-no-metadata'
        $builtManifestPath = Join-Path -Path $TestDrive -ChildPath 'built-no-metadata.psd1'
        $null = New-Item -Path (Join-Path -Path $sourceModulePath -ChildPath 'Public') -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path -Path $sourceModulePath -ChildPath 'AtlassianPS.Standards.psd1') -Value "@{ RootModule = 'AtlassianPS.Standards.psm1' }"
        Set-Content -LiteralPath $builtManifestPath -Value "@{ ModuleVersion = '0.1.0' }"

        InModuleScope AtlassianPS.Standards -Parameters @{
            SourceModulePath  = $sourceModulePath
            BuiltManifestPath = $builtManifestPath
        } {
            param($SourceModulePath, $BuiltManifestPath)

            Mock -CommandName Get-Command -MockWith { $null } -ParameterFilter { $Name -eq 'Metadata\Update-Metadata' }

            {
                Update-ModuleManifestExports -SourceModulePath $SourceModulePath -BuiltManifestPath $BuiltManifestPath -ModuleName 'AtlassianPS.Standards'
            } | Should -Throw -ExpectedMessage 'Metadata\Update-Metadata is not available*'
        }
    }

    It 'throws when source module manifest is missing' {
        $sourceModulePath = Join-Path -Path $TestDrive -ChildPath 'AtlassianPS.Standards-no-source-manifest'
        $builtManifestPath = Join-Path -Path $TestDrive -ChildPath 'built-source-missing.psd1'
        $null = New-Item -Path (Join-Path -Path $sourceModulePath -ChildPath 'Public') -ItemType Directory -Force
        Set-Content -LiteralPath $builtManifestPath -Value "@{ ModuleVersion = '0.1.0' }"

        InModuleScope AtlassianPS.Standards -Parameters @{
            SourceModulePath  = $sourceModulePath
            BuiltManifestPath = $builtManifestPath
        } {
            param($SourceModulePath, $BuiltManifestPath)

            Mock -CommandName Get-Command -MockWith {
                [PSCustomObject]@{ Name = 'Metadata\Update-Metadata' }
            } -ParameterFilter { $Name -eq 'Metadata\Update-Metadata' }

            {
                Update-ModuleManifestExports -SourceModulePath $SourceModulePath -BuiltManifestPath $BuiltManifestPath -ModuleName 'AtlassianPS.Standards'
            } | Should -Throw -ExpectedMessage "Source module manifest*was not found."
        }
    }
}
