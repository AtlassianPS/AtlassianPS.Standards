#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"
    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Sync-ScriptAnalyzerSettings' {
    It 'is exported by the module' {
        $command = Get-Command -Name 'Sync-AtlassianPSScriptAnalyzerSettings' -ErrorAction SilentlyContinue
        $command | Should -Not -BeNullOrEmpty
    }

    It 'copies shared analyzer settings to the destination file' {
        $destinationPath = Join-Path -Path $TestDrive -ChildPath 'PSScriptAnalyzerSettings.psd1'
        $sourcePath = InModuleScope AtlassianPS.Standards { Get-ScriptAnalyzerSettingsPath }

        $syncedPath = Sync-AtlassianPSScriptAnalyzerSettings -DestinationPath $destinationPath

        $syncedPath | Should -Be (Resolve-Path -LiteralPath $destinationPath).ProviderPath
        (Test-Path -LiteralPath $destinationPath -PathType Leaf) | Should -BeTrue
        (Get-Content -LiteralPath $destinationPath -Raw) | Should -Be (Get-Content -LiteralPath $sourcePath -Raw)
    }

    It 'throws a clear error when the shared settings file cannot be resolved' {
        $missingPath = Join-Path -Path $TestDrive -ChildPath 'missing.psd1'
        $destinationPath = Join-Path -Path $TestDrive -ChildPath 'PSScriptAnalyzerSettings.psd1'

        InModuleScope AtlassianPS.Standards -Parameters @{
            DestinationPath = $destinationPath
            MissingPath     = $missingPath
        } {
            param($DestinationPath, $MissingPath)

            Mock -CommandName Get-ScriptAnalyzerSettingsPath -MockWith { $MissingPath }

            {
                Sync-ScriptAnalyzerSettings -DestinationPath $DestinationPath
            } | Should -Throw -ExpectedMessage "Shared PSScriptAnalyzer settings file was not found*"
        }
    }
}
