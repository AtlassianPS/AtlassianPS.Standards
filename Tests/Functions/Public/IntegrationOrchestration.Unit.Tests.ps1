#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"
    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Initialize-IntegrationEnvironment' {
    BeforeEach {
        [Environment]::SetEnvironmentVariable('ATLAS_TRACK', $null)
        [Environment]::SetEnvironmentVariable('ATLAS_CLOUD_URL', $null)
        [Environment]::SetEnvironmentVariable('ATLAS_CLOUD_TOKEN', $null)
        [Environment]::SetEnvironmentVariable('ATLAS_DC_URL', $null)
        [Environment]::SetEnvironmentVariable('ATLAS_OPTIONAL', $null)
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable('ATLAS_TRACK', $null)
        [Environment]::SetEnvironmentVariable('ATLAS_CLOUD_URL', $null)
        [Environment]::SetEnvironmentVariable('ATLAS_CLOUD_TOKEN', $null)
        [Environment]::SetEnvironmentVariable('ATLAS_DC_URL', $null)
        [Environment]::SetEnvironmentVariable('ATLAS_OPTIONAL', $null)
    }

    It 'loads dotenv values and returns normalized track metadata' {
        $envFile = Join-Path -Path $TestDrive -ChildPath 'integration.env'
        Set-Content -LiteralPath $envFile -Value @(
            'ATLAS_CLOUD_URL=https://example.atlassian.net'
            'ATLAS_CLOUD_TOKEN=secret'
            'ATLAS_OPTIONAL=fixture'
        )
        $requiredVariableByTrack = @{
            Cloud      = @('ATLAS_CLOUD_URL', 'ATLAS_CLOUD_TOKEN')
            DataCenter = @('ATLAS_DC_URL')
        }
        $optionalVariableByTrack = @{
            Cloud = @('ATLAS_OPTIONAL')
        }

        $result = Initialize-AtlassianPSIntegrationEnvironment `
            -TrackEnvironmentVariableName 'ATLAS_TRACK' `
            -DefaultTrack 'Cloud' `
            -DotEnvPath $envFile `
            -RequiredVariableByTrack $requiredVariableByTrack `
            -OptionalVariableByTrack $optionalVariableByTrack

        $result.Track | Should -Be 'Cloud'
        $result.IsDefaultTrack | Should -BeTrue
        $result.RequiredVariables | Should -Contain 'ATLAS_CLOUD_URL'
        $result.OptionalVariables | Should -Contain 'ATLAS_OPTIONAL'
        $result.PSObject.Properties.Name | Should -Not -Contain 'Values'
        $env:ATLAS_CLOUD_URL | Should -Be 'https://example.atlassian.net'
        $env:ATLAS_OPTIONAL | Should -Be 'fixture'
    }

    It 'throws when required variables for the selected track are missing' {
        [Environment]::SetEnvironmentVariable('ATLAS_TRACK', 'DataCenter')
        $requiredVariableByTrack = @{
            Cloud      = @('ATLAS_CLOUD_URL')
            DataCenter = @('ATLAS_DC_URL')
        }

        {
            Initialize-AtlassianPSIntegrationEnvironment `
                -TrackEnvironmentVariableName 'ATLAS_TRACK' `
                -DefaultTrack 'Cloud' `
                -RequiredVariableByTrack $requiredVariableByTrack
        } | Should -Throw -ExpectedMessage '*ATLAS_DC_URL*'
    }

    It 'returns null instead of throwing for missing variables in warn-only mode' {
        $requiredVariableByTrack = @{
            Cloud = @('ATLAS_CLOUD_URL')
        }

        $result = Initialize-AtlassianPSIntegrationEnvironment `
            -TrackEnvironmentVariableName 'ATLAS_TRACK' `
            -DefaultTrack 'Cloud' `
            -RequiredVariableByTrack $requiredVariableByTrack `
            -WarnOnly 3>$null

        $result | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-DockerIntegrationTrack' {
    It 'applies defaults, runs docker lifecycle, wait script, and tests' {
        $composeFile = Join-Path -Path $TestDrive -ChildPath 'docker-compose.yml'
        $waitScript = Join-Path -Path $TestDrive -ChildPath 'Wait-Test.ps1'
        $markerPath = Join-Path -Path $TestDrive -ChildPath 'test-marker.txt'
        $waitMarkerPath = Join-Path -Path $TestDrive -ChildPath 'wait-marker.txt'
        Set-Content -LiteralPath $composeFile -Value 'services: {}'
        Set-Content -LiteralPath $waitScript -Value "Set-Content -LiteralPath '$($waitMarkerPath.Replace("'", "''"))' -Value 'waited'"
        [Environment]::SetEnvironmentVariable('ATLAS_DOCKER_DEFAULT', $null)

        InModuleScope AtlassianPS.Standards -Parameters @{
            ComposeFile = $composeFile
            WaitScript  = $waitScript
            MarkerPath  = $markerPath
        } {
            param($ComposeFile, $WaitScript, $MarkerPath)

            function docker {
                param([Parameter(ValueFromRemainingArguments)]$ArgumentList)
                $script:DockerCalls += , ($ArgumentList -join ' ')
                $global:LASTEXITCODE = 0
            }

            $script:DockerCalls = @()

            $result = Invoke-DockerIntegrationTrack `
                -ComposeFile $ComposeFile `
                -ServiceName 'app' `
                -WaitScriptPath $WaitScript `
                -EnvironmentDefault @{ ATLAS_DOCKER_DEFAULT = 'default-value' } `
                -TestScriptBlock { Set-Content -LiteralPath $MarkerPath -Value 'tested'; $global:LASTEXITCODE = 0 } `
                -SkipDockerCheck

            $result.ServiceName | Should -Be 'app'
            [Environment]::GetEnvironmentVariable('ATLAS_DOCKER_DEFAULT') | Should -Be 'default-value'
            Test-Path -LiteralPath $MarkerPath | Should -BeTrue
            $script:DockerCalls[0] | Should -BeLike 'compose -f * up*'
            $script:DockerCalls[-1] | Should -BeLike 'compose -f * down*'
        }

        Test-Path -LiteralPath $waitMarkerPath | Should -BeTrue
        [Environment]::SetEnvironmentVariable('ATLAS_DOCKER_DEFAULT', $null)
    }

    It 'captures logs and rethrows when the test script fails' {
        $composeFile = Join-Path -Path $TestDrive -ChildPath 'docker-compose-fail.yml'
        $logPath = Join-Path -Path $TestDrive -ChildPath 'service.log'
        Set-Content -LiteralPath $composeFile -Value 'services: {}'

        InModuleScope AtlassianPS.Standards -Parameters @{
            ComposeFile = $composeFile
            LogPath     = $logPath
        } {
            param($ComposeFile, $LogPath)

            function docker {
                param([Parameter(ValueFromRemainingArguments)]$ArgumentList)
                $global:LASTEXITCODE = 0
                if (($ArgumentList -join ' ') -like '* logs app') {
                    'container log line'
                }
            }

            {
                Invoke-DockerIntegrationTrack `
                    -ComposeFile $ComposeFile `
                    -ServiceName 'app' `
                    -LogPath $LogPath `
                    -TestScriptBlock { $global:LASTEXITCODE = 7 } `
                    -SkipDockerCheck
            } | Should -Throw -ExpectedMessage '*exit code 7*'
        }

        Get-Content -LiteralPath $logPath -Raw | Should -Match 'container log line'
    }
}

Describe 'New-AtlassianPSPesterFailureResult' {
    It 'creates a consistent failure result object' {
        InModuleScope AtlassianPS.Standards {
            $result = New-AtlassianPSPesterFailureResult -File 'Thing.Tests.ps1' -Name 'Timeout' -Message 'Timed out.' -Duration ([TimeSpan]::FromSeconds(2))

            $result.File | Should -Be 'Thing.Tests.ps1'
            $result.Failed | Should -Be 1
            $result.FailedTests[0].Name | Should -Be 'Timeout'
            $result.Duration.TotalSeconds | Should -Be 2
        }
    }
}
