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

            Mock -CommandName Find-Module -MockWith { $null }
            Mock -CommandName Update-ModuleManifest -MockWith {}

            $version = Set-ModuleManifestVersion `
                -BuiltManifestPath $BuiltManifestPath `
                -ModuleName 'AtlassianPS.Standards' `
                -VersionToPublish 'v1.2.3-rc-2' `
                -ReleaseNotes '- Added dependency flow'

            $version | Should -Be '1.2.3'
            Should -Invoke -CommandName Update-ModuleManifest -Times 1 -Exactly -Scope It -ParameterFilter {
                $ModuleVersion -eq '1.2.3' -and $Prerelease -eq 'rc-2' -and $ReleaseNotes -eq '- Added dependency flow'
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

            Mock -CommandName Find-Module -MockWith { $null }
            Mock -CommandName Update-ModuleManifest -MockWith {}

            $null = Set-ModuleManifestVersion -BuiltManifestPath $BuiltManifestPath -ModuleName 'AtlassianPS.Standards' -VersionToPublish '1.2.4'

            Should -Invoke -CommandName Update-ModuleManifest -Scope It -ParameterFilter {
                $ModuleVersion -eq '1.2.4' -and $Prerelease -eq ''
            }
        }
    }

    It 'normalizes manifest encoding and line endings after update' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-formatting.psd1'
        [System.IO.File]::WriteAllText(
            $manifestPath,
            "@{`n    ModuleVersion = '0.1.0'`n}`n",
            [System.Text.UTF8Encoding]::new($false)
        )

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuiltManifestPath = $manifestPath
        } {
            param($BuiltManifestPath)

            Mock -CommandName Find-Module -MockWith { $null }
            Mock -CommandName Update-ModuleManifest -MockWith {
                param([string]$Path, [string]$ModuleVersion)

                [System.IO.File]::WriteAllText(
                    $Path,
                    "@{`nModuleVersion = '$ModuleVersion'`n}`n",
                    [System.Text.UTF8Encoding]::new($false)
                )
            }

            $null = Set-ModuleManifestVersion `
                -BuiltManifestPath $BuiltManifestPath `
                -ModuleName 'AtlassianPS.Standards' `
                -VersionToPublish '1.2.5'

            $bytes = [System.IO.File]::ReadAllBytes($BuiltManifestPath)
            @($bytes[0], $bytes[1], $bytes[2]) | Should -Be @(239, 187, 191)

            $content = [System.IO.File]::ReadAllText($BuiltManifestPath)
            $content | Should -Match "`r`n"
            $content.Replace("`r`n", '') | Should -Not -Match "`n"
        }
    }

    It 'throws when release notes are blank' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-empty-release-notes.psd1'
        Set-Content -LiteralPath $manifestPath -Value "@{ ModuleVersion = '0.1.0' }"

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuiltManifestPath = $manifestPath
        } {
            param($BuiltManifestPath)

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

            Mock -CommandName Test-ModuleManifest -MockWith {
                [PSCustomObject]@{
                    ExportedAliases = @{
                        gt = 'Get-Thing'
                    }
                }
            }
            Mock -CommandName Update-ModuleManifest -MockWith {}

            $result = Update-ModuleManifestExports `
                -SourceModulePath $SourceModulePath `
                -BuiltManifestPath $BuiltManifestPath `
                -ModuleName 'AtlassianPS.Standards'

            $result.FunctionsToExport | Should -Contain 'Get-Thing'
            $result.FunctionsToExport | Should -Contain 'Set-Thing'
            $result.AliasesToExport | Should -Contain 'gt'
            Should -Invoke -CommandName Update-ModuleManifest -Times 1 -Exactly -Scope It -ParameterFilter {
                @($FunctionsToExport) -contains 'Get-Thing' -and @($AliasesToExport) -contains 'gt'
            }
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

            {
                Update-ModuleManifestExports -SourceModulePath $SourceModulePath -BuiltManifestPath $BuiltManifestPath -ModuleName 'AtlassianPS.Standards'
            } | Should -Throw -ExpectedMessage "Source module manifest*was not found."
        }
    }
}
