#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.9.0"; MaximumVersion = "5.9.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"

    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Invoke-Lint' {
    It 'is exported by the module' {
        $lintCommand = Get-Command -Module 'AtlassianPS.Standards' |
            Where-Object { $_.CommandType -eq 'Function' -and $_.Verb -eq 'Invoke' -and $_.Name -like '*Lint' } |
            Select-Object -First 1

        $lintCommand | Should -Not -BeNullOrEmpty
    }

    It 'runs through the exported prefixed command' {
        $projectPath = Join-Path -Path $TestDrive -ChildPath 'project-exported-command'
        $modulePath = Join-Path -Path $projectPath -ChildPath 'AtlassianPS.Standards'
        $testsPath = Join-Path -Path $projectPath -ChildPath 'Tests'
        $toolsPath = Join-Path -Path $projectPath -ChildPath 'Tools'
        $stylePath = Join-Path -Path $testsPath -ChildPath 'Style.Tests.ps1'
        $settingsPath = Join-Path -Path $modulePath -ChildPath 'PSScriptAnalyzerSettings.psd1'
        $buildScriptPath = Join-Path -Path $projectPath -ChildPath 'AtlassianPS.Standards.build.ps1'

        $null = New-Item -Path $modulePath -ItemType Directory -Force
        $null = New-Item -Path $testsPath -ItemType Directory -Force
        $null = New-Item -Path $toolsPath -ItemType Directory -Force
        Set-Content -LiteralPath $stylePath -Value 'Describe "style" { It "passes" { $true | Should -BeTrue } }'
        Set-Content -LiteralPath $settingsPath -Value '@{ IncludeRules = @() }'
        Set-Content -LiteralPath $buildScriptPath -Value '$null = $true'

        $result = Invoke-AtlassianPSLint `
            -ProjectPath $projectPath `
            -ModulePath $modulePath `
            -BuildScriptPath $buildScriptPath `
            -AnalyzerSettingsPath $settingsPath `
            -AnalyzerPaths @($buildScriptPath) `
            -PesterVerbosity None

        $result.StyleFailedCount | Should -Be 0
        $result.AnalyzerIssueCount | Should -Be 0
    }

    It 'preserves the existing positional parameter order' {
        $projectPath = Join-Path -Path $TestDrive -ChildPath 'project-positional-parameters'
        $modulePath = Join-Path -Path $projectPath -ChildPath 'AtlassianPS.Standards'
        $settingsPath = Join-Path -Path $modulePath -ChildPath 'PSScriptAnalyzerSettings.psd1'
        $buildScriptPath = Join-Path -Path $projectPath -ChildPath 'AtlassianPS.Standards.build.ps1'

        $null = New-Item -Path $modulePath -ItemType Directory -Force
        Set-Content -LiteralPath $settingsPath -Value '@{ IncludeRules = @() }'
        Set-Content -LiteralPath $buildScriptPath -Value '$null = $true'
        $minimumPesterVersion = [Version]'5.9.0'

        $result = Invoke-AtlassianPSLint `
            $projectPath `
            $modulePath `
            $buildScriptPath `
            $null `
            $settingsPath `
            $buildScriptPath `
            'None' `
            $minimumPesterVersion `
            'Error' `
            -SkipStyleTests `
            -SkipScriptAnalyzer

        $result.StyleFailedCount | Should -Be 0
        $result.AnalyzerIssueCount | Should -Be 0
    }

    It 'fails fast when Pester is below the minimum version' {
        $projectPath = Join-Path -Path $TestDrive -ChildPath 'project-old-pester'
        $modulePath = Join-Path -Path $projectPath -ChildPath 'AtlassianPS.Standards'
        $testsPath = Join-Path -Path $projectPath -ChildPath 'Tests'
        $stylePath = Join-Path -Path $testsPath -ChildPath 'Style.Tests.ps1'
        $settingsPath = Join-Path -Path $modulePath -ChildPath 'PSScriptAnalyzerSettings.psd1'
        $buildScriptPath = Join-Path -Path $projectPath -ChildPath 'AtlassianPS.Standards.build.ps1'

        $null = New-Item -Path $modulePath -ItemType Directory -Force
        $null = New-Item -Path $testsPath -ItemType Directory -Force
        Set-Content -LiteralPath $stylePath -Value 'Describe "style" { It "passes" { $true | Should -BeTrue } }'
        Set-Content -LiteralPath $settingsPath -Value '@{ IncludeRules = @() }'
        Set-Content -LiteralPath $buildScriptPath -Value '$null = $true'

        InModuleScope AtlassianPS.Standards -Parameters @{
            ProjectPath     = $projectPath
            ModulePath      = $modulePath
            BuildScriptPath = $buildScriptPath
            SettingsPath    = $settingsPath
        } {
            param($ProjectPath, $ModulePath, $BuildScriptPath, $SettingsPath)

            {
                Invoke-Lint `
                    -ProjectPath $ProjectPath `
                    -ModulePath $ModulePath `
                    -BuildScriptPath $BuildScriptPath `
                    -AnalyzerSettingsPath $SettingsPath `
                    -MinimumPesterVersion ([Version]'99.0.0') `
                    -MaximumPesterVersion ([Version]'99.0.999')
            } | Should -Throw -ExpectedMessage "Pester version between 99.0.0 and 99.0.999 is required*"
        }
    }

    It 'selects the newest installed Pester version within the accepted range' {
        $projectPath = Join-Path -Path $TestDrive -ChildPath 'project-pester-range'
        $modulePath = Join-Path -Path $projectPath -ChildPath 'AtlassianPS.Standards'
        $testsPath = Join-Path -Path $projectPath -ChildPath 'Tests'
        $stylePath = Join-Path -Path $testsPath -ChildPath 'Style.Tests.ps1'
        $settingsPath = Join-Path -Path $modulePath -ChildPath 'PSScriptAnalyzerSettings.psd1'
        $buildScriptPath = Join-Path -Path $projectPath -ChildPath 'AtlassianPS.Standards.build.ps1'

        $null = New-Item -Path $modulePath -ItemType Directory -Force
        $null = New-Item -Path $testsPath -ItemType Directory -Force
        Set-Content -LiteralPath $stylePath -Value 'Describe "style" { It "passes" { $true | Should -BeTrue } }'
        Set-Content -LiteralPath $settingsPath -Value '@{ IncludeRules = @() }'
        Set-Content -LiteralPath $buildScriptPath -Value '$null = $true'

        InModuleScope AtlassianPS.Standards -Parameters @{
            ProjectPath     = $projectPath
            ModulePath      = $modulePath
            BuildScriptPath = $buildScriptPath
            SettingsPath    = $settingsPath
        } {
            param($ProjectPath, $ModulePath, $BuildScriptPath, $SettingsPath)

            Mock -CommandName Get-Module -MockWith {
                @(
                    [PSCustomObject]@{ Version = [Version]'6.0.0' }
                    [PSCustomObject]@{ Version = [Version]'5.9.4' }
                    [PSCustomObject]@{ Version = [Version]'5.9.0' }
                )
            } -ParameterFilter { $Name -eq 'Pester' -and $ListAvailable }
            Mock -CommandName Get-Module -MockWith { $null } -ParameterFilter { $Name -eq 'Pester' -and -not $ListAvailable }
            Mock -CommandName Import-Module -MockWith {}
            Mock -CommandName New-PesterConfiguration -MockWith { param($Hashtable) $Hashtable }
            Mock -CommandName Invoke-Pester -MockWith { [PSCustomObject]@{ FailedCount = 0 } }

            $null = Invoke-Lint `
                -ProjectPath $ProjectPath `
                -ModulePath $ModulePath `
                -BuildScriptPath $BuildScriptPath `
                -AnalyzerSettingsPath $SettingsPath `
                -SkipScriptAnalyzer

            Should -Invoke -CommandName Import-Module -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Pester' -and $RequiredVersion -eq [Version]'5.9.4' -and $ErrorAction -eq 'Stop'
            }
        }
    }

    It 'returns lint counts when style tests and analyzer pass' {
        $projectPath = Join-Path -Path $TestDrive -ChildPath 'project'
        $modulePath = Join-Path -Path $projectPath -ChildPath 'AtlassianPS.Standards'
        $testsPath = Join-Path -Path $projectPath -ChildPath 'Tests'
        $toolsPath = Join-Path -Path $projectPath -ChildPath 'Tools'
        $stylePath = Join-Path -Path $testsPath -ChildPath 'Style.Tests.ps1'
        $settingsPath = Join-Path -Path $modulePath -ChildPath 'PSScriptAnalyzerSettings.psd1'
        $buildScriptPath = Join-Path -Path $projectPath -ChildPath 'AtlassianPS.Standards.build.ps1'

        $null = New-Item -Path $modulePath -ItemType Directory -Force
        $null = New-Item -Path $testsPath -ItemType Directory -Force
        $null = New-Item -Path $toolsPath -ItemType Directory -Force
        Set-Content -LiteralPath $stylePath -Value 'Describe "style" { It "passes" { $true | Should -BeTrue } }'
        Set-Content -LiteralPath $settingsPath -Value '@{ IncludeRules = @() }'
        Set-Content -LiteralPath $buildScriptPath -Value '$null = $true'

        InModuleScope AtlassianPS.Standards -Parameters @{
            ProjectPath     = $projectPath
            ModulePath      = $modulePath
            BuildScriptPath = $buildScriptPath
            SettingsPath    = $settingsPath
        } {
            param($ProjectPath, $ModulePath, $BuildScriptPath, $SettingsPath)

            Mock -CommandName Invoke-Pester -MockWith {
                [PSCustomObject]@{ FailedCount = 0 }
            }
            Mock -CommandName Invoke-ScriptAnalyzer -MockWith { @() }

            $result = Invoke-Lint -ProjectPath $ProjectPath -ModulePath $ModulePath -BuildScriptPath $BuildScriptPath -AnalyzerSettingsPath $SettingsPath

            $result.StyleFailedCount | Should -Be 0
            $result.AnalyzerIssueCount | Should -Be 0
            $result.AnalyzerPathCount | Should -BeGreaterThan 0
        }
    }

    It 'aggregates style and analyzer failures into one error' {
        $originalGitHubActions = $env:GITHUB_ACTIONS
        $projectPath = Join-Path -Path $TestDrive -ChildPath 'project-failure'
        $modulePath = Join-Path -Path $projectPath -ChildPath 'AtlassianPS.Standards'
        $testsPath = Join-Path -Path $projectPath -ChildPath 'Tests'
        $stylePath = Join-Path -Path $testsPath -ChildPath 'Style.Tests.ps1'
        $settingsPath = Join-Path -Path $modulePath -ChildPath 'PSScriptAnalyzerSettings.psd1'
        $buildScriptPath = Join-Path -Path $projectPath -ChildPath 'AtlassianPS.Standards.build.ps1'

        $null = New-Item -Path $modulePath -ItemType Directory -Force
        $null = New-Item -Path $testsPath -ItemType Directory -Force
        Set-Content -LiteralPath $stylePath -Value 'Describe "style" { It "fails" { $false | Should -BeTrue } }'
        Set-Content -LiteralPath $settingsPath -Value '@{ IncludeRules = @() }'
        Set-Content -LiteralPath $buildScriptPath -Value '$null = $true'

        try {
            $env:GITHUB_ACTIONS = $null

            InModuleScope AtlassianPS.Standards -Parameters @{
                ProjectPath     = $projectPath
                ModulePath      = $modulePath
                BuildScriptPath = $buildScriptPath
                SettingsPath    = $settingsPath
            } {
                param($ProjectPath, $ModulePath, $BuildScriptPath, $SettingsPath)

                Mock -CommandName Invoke-Pester -MockWith {
                    [PSCustomObject]@{ FailedCount = 1 }
                }
                Mock -CommandName Invoke-ScriptAnalyzer -MockWith {
                    @(
                        [PSCustomObject]@{
                            Severity   = 'Warning'
                            ScriptName = 'AtlassianPS.Standards.build.ps1'
                            ScriptPath = $BuildScriptPath
                            Line       = 12
                            Column     = 4
                            RuleName   = 'PSRule'
                            Message    = 'Mock warning'
                        }
                    )
                }

                {
                    Invoke-Lint -ProjectPath $ProjectPath -ModulePath $ModulePath -BuildScriptPath $BuildScriptPath -AnalyzerSettingsPath $SettingsPath
                } | Should -Throw -ExpectedMessage "Lint failed:*style test(s) failed.*PSScriptAnalyzer issue(s) found.*"
            }
        }
        finally {
            $env:GITHUB_ACTIONS = $originalGitHubActions
        }
    }
}
