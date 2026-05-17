#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"
    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Get-BuildEnvironmentInfo' {
    It 'normalizes version input and builds manifest path from BH env vars' {
        InModuleScope AtlassianPS.Standards {
            $env:BHBuildSystem = 'Local'
            $env:BHProjectName = 'AtlassianPS.Standards'
            $env:BHProjectPath = '/tmp/project'
            $env:BHModulePath = '/tmp/project/AtlassianPS.Standards'
            $env:BHPSModuleManifest = '/tmp/project/AtlassianPS.Standards/AtlassianPS.Standards.psd1'
            $env:BHBuildOutput = '/tmp/project/Release'
            $env:BHBranchName = 'feature/test'
            $env:BHCommitHash = 'abc123'
            $env:BHCommitMessage = 'test'
            $env:BHBuildNumber = '1'

            Mock -CommandName Get-HostPlatformInfo -MockWith {
                [PSCustomObject]@{
                    OS        = 'Linux'
                    OSVersion = '1.0'
                }
            }

            $info = Get-BuildEnvironmentInfo -VersionToPublish 'v1.2.3'

            $info.VersionToPublish | Should -Be '1.2.3'
            $expectedBuiltManifestPath = Join-Path -Path (Join-Path -Path $env:BHBuildOutput -ChildPath $env:BHProjectName) -ChildPath "$($env:BHProjectName).psd1"
            $info.BuiltManifestPath | Should -Be $expectedBuiltManifestPath
            $info.OS | Should -Be 'Linux'
        }
    }

    It 'returns null built manifest path when build output data is missing' {
        InModuleScope AtlassianPS.Standards {
            $env:BHBuildOutput = $null
            $env:BHProjectName = $null

            Mock -CommandName Get-HostPlatformInfo -MockWith {
                [PSCustomObject]@{
                    OS        = 'Linux'
                    OSVersion = '1.0'
                }
            }

            $info = Get-BuildEnvironmentInfo

            $info.BuiltManifestPath | Should -Be $null
        }
    }
}

Describe 'Initialize-BuildEnvironment' {
    It 'sets BH environment variables and returns build info' {
        $projectRoot = Join-Path -Path $TestDrive -ChildPath 'project'
        $null = New-Item -Path $projectRoot -ItemType Directory -Force

        InModuleScope AtlassianPS.Standards -Parameters @{
            ProjectName = 'AtlassianPS.Standards'
            ProjectPath = $projectRoot
        } {
            param($ProjectName, $ProjectPath)

            Mock -CommandName Get-BuildEnvironmentMetadata -MockWith {
                [PSCustomObject]@{
                    BuildSystem   = 'Unknown'
                    BranchName    = 'main'
                    CommitHash    = 'deadbeef'
                    BuildNumber   = '0'
                    CommitMessage = 'msg'
                }
            }

            Mock -CommandName Get-BuildEnvironmentInfo -MockWith {
                [PSCustomObject]@{
                    ProjectName     = $env:BHProjectName
                    BuildOutputPath = $env:BHBuildOutput
                }
            }

            $result = Initialize-BuildEnvironment -ProjectName $ProjectName -ProjectPath $ProjectPath -BuildOutputFolder 'out'

            $env:BHProjectName | Should -Be 'AtlassianPS.Standards'
            $env:BHProjectPath | Should -Be (Resolve-Path -LiteralPath $ProjectPath).ProviderPath
            $env:BHBuildOutput | Should -Be (Join-Path -Path $env:BHProjectPath -ChildPath 'out')
            $result.ProjectName | Should -Be 'AtlassianPS.Standards'
        }
    }

    It 'resets pre-existing BH variables when requested' {
        $projectRoot = Join-Path -Path $TestDrive -ChildPath 'project-reset'
        $null = New-Item -Path $projectRoot -ItemType Directory -Force

        InModuleScope AtlassianPS.Standards -Parameters @{
            ProjectPath = $projectRoot
        } {
            param($ProjectPath)

            $env:BHStaleVariable = 'stale'

            Mock -CommandName Get-BuildEnvironmentMetadata -MockWith {
                [PSCustomObject]@{
                    BuildSystem   = 'Unknown'
                    BranchName    = 'main'
                    CommitHash    = 'deadbeef'
                    BuildNumber   = '0'
                    CommitMessage = 'msg'
                }
            }
            Mock -CommandName Get-BuildEnvironmentInfo -MockWith { [PSCustomObject]@{} }

            $null = Initialize-BuildEnvironment -ProjectName 'AtlassianPS.Standards' -ProjectPath $ProjectPath -ResetBuildEnvironmentVariables

            $env:BHStaleVariable | Should -BeNullOrEmpty
        }
    }
}
