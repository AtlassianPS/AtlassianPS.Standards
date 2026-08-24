#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.9.0"; MaximumVersion = "5.9.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"
    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Invoke-ModuleTests' {
    It 'imports Pester globally for test scripts' {
        InModuleScope AtlassianPS.Standards {
            Mock -CommandName Get-UsablePesterVersion -MockWith { [Version]'5.9.2' }
            Mock -CommandName Get-Module -MockWith { $null } -ParameterFilter { $Name -eq 'Pester' }
            Mock -CommandName Import-Module -MockWith {}

            $null = Import-PesterVersion `
                -MinimumVersion ([Version]'5.9.0') `
                -MaximumVersion ([Version]'5.9.999')

            Should -Invoke -CommandName Get-UsablePesterVersion -Times 1 -Exactly -ParameterFilter {
                $MinimumVersion -eq [Version]'5.9.0' -and $MaximumVersion -eq [Version]'5.9.999'
            }

            Should -Invoke -CommandName Import-Module -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Pester' -and $RequiredVersion -eq [Version]'5.9.2' -and $Global -and $ErrorAction -eq 'Stop'
            }
        }
    }

    It 'selects the newest installed Pester version within the accepted range' {
        InModuleScope AtlassianPS.Standards {
            Mock -CommandName Get-Module -MockWith {
                @(
                    [PSCustomObject]@{ Version = [Version]'6.0.0' }
                    [PSCustomObject]@{ Version = [Version]'5.9.4' }
                    [PSCustomObject]@{ Version = [Version]'5.9.0' }
                    [PSCustomObject]@{ Version = [Version]'5.8.1' }
                )
            } -ParameterFilter { $Name -eq 'Pester' -and $ListAvailable }

            $selectedVersion = Get-UsablePesterVersion `
                -MinimumVersion ([Version]'5.9.0') `
                -MaximumVersion ([Version]'5.9.999')

            $selectedVersion | Should -Be ([Version]'5.9.4')
        }
    }

    It 'passes the accepted Pester range to module test execution' {
        $testsPath = Join-Path -Path $TestDrive -ChildPath 'tests-version-range'
        $null = New-Item -Path $testsPath -ItemType Directory -Force

        InModuleScope AtlassianPS.Standards -Parameters @{ TestPath = $testsPath } {
            param($TestPath)

            Mock -CommandName Import-PesterVersion -MockWith { [Version]'5.9.3' }
            Mock -CommandName New-PesterConfiguration -MockWith { param($Hashtable) $Hashtable }
            Mock -CommandName Invoke-Pester -MockWith {
                [PSCustomObject]@{ FailedCount = 0; ContainersFailedCount = 0 }
            }

            $null = Invoke-ModuleTests -TestPath $TestPath

            Should -Invoke -CommandName Import-PesterVersion -Times 1 -Exactly -ParameterFilter {
                $MinimumVersion -eq [Version]'5.9.0' -and $MaximumVersion -eq [Version]'5.9.999'
            }
        }
    }

    It 'passes the accepted Pester range to style test execution' {
        $styleTestPath = Join-Path -Path $TestDrive -ChildPath 'Style.Tests.ps1'
        Set-Content -LiteralPath $styleTestPath -Value 'Describe "style" { It "passes" { $true | Should -BeTrue } }'

        InModuleScope AtlassianPS.Standards -Parameters @{ StyleTestPath = $styleTestPath } {
            param($StyleTestPath)

            Mock -CommandName Import-PesterVersion -MockWith { [Version]'5.9.3' }
            Mock -CommandName New-PesterConfiguration -MockWith { param($Hashtable) $Hashtable }
            Mock -CommandName Invoke-Pester -MockWith { [PSCustomObject]@{ FailedCount = 0 } }

            $null = Invoke-StyleLintTests -StyleTestPath $StyleTestPath

            Should -Invoke -CommandName Import-PesterVersion -Times 1 -Exactly -ParameterFilter {
                $MinimumVersion -eq [Version]'5.9.0' -and $MaximumVersion -eq [Version]'5.9.999'
            }
        }
    }

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
    BeforeAll {
        # Realistic multi-line manifest fixture mirroring the source manifest shape.
        $script:manifestTemplate = @'
@{
    RootModule           = 'Sample.psm1'
    ModuleVersion        = '0.1'
    GUID                 = 'b558bd8c-dc02-4ff2-96b7-4d2c61d9d103'
    Author               = 'AtlassianPS'
    Description          = 'Sample module.'
    PrivateData          = @{
        PSData = @{
            Prerelease   = ''
            ReleaseNotes = ''
        }
    }
}
'@
    }

    It 'stamps version and prerelease in place without reformatting the rest of the manifest' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-inplace.psd1'
        Set-Content -LiteralPath $manifestPath -Value $script:manifestTemplate

        $version = Set-AtlassianPSModuleManifestVersion `
            -BuiltManifestPath $manifestPath `
            -ModuleName 'Sample' `
            -VersionToPublish 'v1.2.3-rc-2'

        $version | Should -Be '1.2.3'

        $data = Import-PowerShellDataFile -LiteralPath $manifestPath
        $data.ModuleVersion | Should -Be '1.2.3'
        $data.PrivateData.PSData.Prerelease | Should -Be 'rc-2'
        # ReleaseNotes left empty because it was not provided.
        $data.PrivateData.PSData.ReleaseNotes | Should -BeNullOrEmpty

        # Only the version (and prerelease) lines changed; every other line is byte-identical.
        $original = ($script:manifestTemplate -replace "`r`n", "`n").Split("`n")
        $updated = ((Get-Content -LiteralPath $manifestPath -Raw) -replace "`r`n", "`n").TrimEnd("`n").Split("`n")
        $changedLines = (Compare-Object -ReferenceObject $original -DifferenceObject $updated).InputObject |
            Where-Object { $_ -match '\S' }
        $changedText = $changedLines -join "`n"
        $changedText | Should -Match 'ModuleVersion'
        $changedText | Should -Not -Match 'GUID'
        $changedText | Should -Not -Match 'Author'
        $changedText | Should -Not -Match 'Description'
        $changedText | Should -Not -Match 'RootModule'
    }

    It 'clears prerelease metadata for stable versions' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-stable.psd1'
        Set-Content -LiteralPath $manifestPath -Value ($script:manifestTemplate -replace "Prerelease   = ''", "Prerelease   = 'beta'")

        $null = Set-AtlassianPSModuleManifestVersion -BuiltManifestPath $manifestPath -ModuleName 'Sample' -VersionToPublish '1.2.4'

        $data = Import-PowerShellDataFile -LiteralPath $manifestPath
        $data.ModuleVersion | Should -Be '1.2.4'
        $data.PrivateData.PSData.Prerelease | Should -Be ''
    }

    It 'leaves dependency versions untouched' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-with-dependency.psd1'
        $manifest = @'
@{
    RequiredModules      = @(
        @{
            ModuleName    = 'Dependency'
            ModuleVersion = '4.5.6'
        }
    )
    RootModule           = 'Sample.psm1'
    ModuleVersion        = '0.1'
    GUID                 = 'b558bd8c-dc02-4ff2-96b7-4d2c61d9d103'
    Author               = 'AtlassianPS'
    Description          = 'Sample module.'
    PrivateData          = @{
        PSData = @{
            Prerelease   = ''
            ReleaseNotes = ''
        }
    }
}
'@
        Set-Content -LiteralPath $manifestPath -Value $manifest

        $null = Set-AtlassianPSModuleManifestVersion -BuiltManifestPath $manifestPath -ModuleName 'Sample' -VersionToPublish '1.2.4'

        $data = Import-PowerShellDataFile -LiteralPath $manifestPath
        $data.ModuleVersion | Should -Be '1.2.4'
        $data.RequiredModules[0].ModuleVersion | Should -Be '4.5.6'
    }

    It 'leaves release notes untouched when -ReleaseNotes is not provided' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-notes-empty.psd1'
        Set-Content -LiteralPath $manifestPath -Value $script:manifestTemplate

        $null = Set-AtlassianPSModuleManifestVersion -BuiltManifestPath $manifestPath -ModuleName 'Sample' -VersionToPublish '1.2.3'

        (Import-PowerShellDataFile -LiteralPath $manifestPath).PrivateData.PSData.ReleaseNotes | Should -BeNullOrEmpty
    }

    It 'writes multi-line release notes with quotes and dollar signs and round-trips them' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-notes.psd1'
        Set-Content -LiteralPath $manifestPath -Value $script:manifestTemplate

        $notes = "- Fixed don't break on apostrophes`n- Handle `$dollar and 'quoted' words`n- Multi-line notes"
        $null = Set-AtlassianPSModuleManifestVersion `
            -BuiltManifestPath $manifestPath `
            -ModuleName 'Sample' `
            -VersionToPublish '1.2.3' `
            -ReleaseNotes $notes

        $written = (Import-PowerShellDataFile -LiteralPath $manifestPath).PrivateData.PSData.ReleaseNotes
        ($written -replace "`r`n", "`n") | Should -Be $notes
    }

    It 'activates commented prerelease and release-note placeholders' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-commented-metadata.psd1'
        $commentedManifest = $script:manifestTemplate `
            -replace "            Prerelease   = ''", "            # Prerelease   = ''" `
            -replace "            ReleaseNotes = ''", "            # ReleaseNotes = ''"
        Set-Content -LiteralPath $manifestPath -Value $commentedManifest

        $notes = "- Fixed candidate metadata`n- Preserved multi-line notes"
        $null = Set-AtlassianPSModuleManifestVersion `
            -BuiltManifestPath $manifestPath `
            -ModuleName 'Sample' `
            -VersionToPublish '1.2.3-rc-2' `
            -ReleaseNotes $notes

        $written = Import-PowerShellDataFile -LiteralPath $manifestPath
        $written.PrivateData.PSData.Prerelease | Should -Be 'rc-2'
        ($written.PrivateData.PSData.ReleaseNotes -replace "`r`n", "`n") | Should -Be $notes
        (Get-Content -LiteralPath $manifestPath -Raw) | Should -Not -Match '(?m)^\s*#\s*(Prerelease|ReleaseNotes)\s*='
    }

    It 'does not check the published version unless -EnforceGreaterThanPublished is set' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-noenforce.psd1'
        Set-Content -LiteralPath $manifestPath -Value $script:manifestTemplate

        InModuleScope AtlassianPS.Standards -Parameters @{ BuiltManifestPath = $manifestPath } {
            param($BuiltManifestPath)

            Mock -CommandName Find-Module -MockWith { [PSCustomObject]@{ Version = [Version]'9.9.9' } }

            $null = Set-ModuleManifestVersion -BuiltManifestPath $BuiltManifestPath -ModuleName 'Sample' -VersionToPublish '0.0.1'

            Should -Invoke -CommandName Find-Module -Times 0 -Exactly -Scope It
        }
    }

    It 'throws when the version is not higher than published and enforcement is requested' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-enforce.psd1'
        Set-Content -LiteralPath $manifestPath -Value $script:manifestTemplate

        InModuleScope AtlassianPS.Standards -Parameters @{ BuiltManifestPath = $manifestPath } {
            param($BuiltManifestPath)

            Mock -CommandName Find-Module -MockWith { [PSCustomObject]@{ Version = [Version]'1.2.3' } }

            {
                Set-ModuleManifestVersion -BuiltManifestPath $BuiltManifestPath -ModuleName 'Sample' -VersionToPublish '1.2.3' -EnforceGreaterThanPublished
            } | Should -Throw -ExpectedMessage 'Version must be greater than latest published version*'
        }
    }

    It 'normalizes manifest encoding to UTF-8 BOM and CRLF line endings' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-formatting.psd1'
        [System.IO.File]::WriteAllText(
            $manifestPath,
            "@{`n    ModuleVersion = '0.1.0'`n}`n",
            [System.Text.UTF8Encoding]::new($false)
        )

        $null = Set-AtlassianPSModuleManifestVersion -BuiltManifestPath $manifestPath -ModuleName 'Sample' -VersionToPublish '1.2.5'

        $bytes = [System.IO.File]::ReadAllBytes($manifestPath)
        @($bytes[0], $bytes[1], $bytes[2]) | Should -Be @(239, 187, 191)

        $content = [System.IO.File]::ReadAllText($manifestPath)
        $content | Should -Match "`r`n"
        $content.Replace("`r`n", '') | Should -Not -Match "`n"
    }

    It 'throws when release notes are blank' {
        $manifestPath = Join-Path -Path $TestDrive -ChildPath 'module-empty-release-notes.psd1'
        Set-Content -LiteralPath $manifestPath -Value $script:manifestTemplate

        {
            Set-AtlassianPSModuleManifestVersion `
                -BuiltManifestPath $manifestPath `
                -ModuleName 'Sample' `
                -VersionToPublish '1.2.6' `
                -ReleaseNotes '   '
        } | Should -Throw -ExpectedMessage 'ReleaseNotes cannot be empty when provided.'
    }

    It 'throws when the manifest does not exist' {
        {
            Set-AtlassianPSModuleManifestVersion `
                -BuiltManifestPath (Join-Path -Path $TestDrive -ChildPath 'missing.psd1') `
                -ModuleName 'Sample' `
                -VersionToPublish '1.2.3'
        } | Should -Throw -ExpectedMessage "Module manifest*was not found."
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
