#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.9.0"; MaximumVersion = "5.9.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"
    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Resolve-ProjectRoot' {
    It 'walks upward until it finds the configured marker' {
        $root = Join-Path -Path $TestDrive -ChildPath 'repo'
        $nested = Join-Path -Path $root -ChildPath 'Tests/Functions/Public'
        $null = New-Item -Path $nested -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path -Path $root -ChildPath 'CODEOWNERS') -Value '* @team'

        $result = Resolve-AtlassianPSProjectRoot -StartPath $nested

        $result | Should -Be $root
    }

    It 'throws when the marker cannot be found' {
        $root = Join-Path -Path $TestDrive -ChildPath 'no-marker'
        $null = New-Item -Path $root -ItemType Directory -Force

        {
            Resolve-AtlassianPSProjectRoot -StartPath $root
        } | Should -Throw -ExpectedMessage "Could not find project root marker*"
    }
}

Describe 'Resolve-ModuleSource' {
    It 'resolves a source module manifest' {
        $root = Join-Path -Path $TestDrive -ChildPath 'source-repo'
        $modulePath = Join-Path -Path $root -ChildPath 'ExampleModule'
        $nested = Join-Path -Path $root -ChildPath 'Tests'
        $null = New-Item -Path $modulePath, $nested -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path -Path $root -ChildPath 'CODEOWNERS') -Value '* @team'
        New-ModuleManifest -Path (Join-Path -Path $modulePath -ChildPath 'ExampleModule.psd1') -RootModule 'ExampleModule.psm1' -ModuleVersion '1.0.0'

        $result = Resolve-AtlassianPSModuleSource -ModuleName 'ExampleModule' -StartPath $nested

        $result | Should -Be (Join-Path -Path $modulePath -ChildPath 'ExampleModule.psd1')
    }

    It 'resolves a release module manifest when the start path is below Release' {
        $root = Join-Path -Path $TestDrive -ChildPath 'release-repo'
        $modulePath = Join-Path -Path $root -ChildPath 'Release/ExampleModule'
        $nested = Join-Path -Path $modulePath -ChildPath 'Tests'
        $null = New-Item -Path $modulePath, $nested -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path -Path $root -ChildPath 'CODEOWNERS') -Value '* @team'
        New-ModuleManifest -Path (Join-Path -Path $modulePath -ChildPath 'ExampleModule.psd1') -RootModule 'ExampleModule.psm1' -ModuleVersion '1.0.0'

        $result = Resolve-AtlassianPSModuleSource -ModuleName 'ExampleModule' -StartPath $nested

        $result | Should -Be (Join-Path -Path $modulePath -ChildPath 'ExampleModule.psd1')
    }
}

Describe 'Initialize-ModuleTestEnvironment' {
    It 'imports the module under test and returns the manifest path' {
        $root = Join-Path -Path $TestDrive -ChildPath 'import-repo'
        $modulePath = Join-Path -Path $root -ChildPath 'ExampleModule'
        $nested = Join-Path -Path $root -ChildPath 'Tests'
        $null = New-Item -Path $modulePath, $nested -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path -Path $root -ChildPath 'CODEOWNERS') -Value '* @team'
        Set-Content -LiteralPath (Join-Path -Path $modulePath -ChildPath 'ExampleModule.psm1') -Value 'function Get-ExampleValue { 42 }'
        New-ModuleManifest -Path (Join-Path -Path $modulePath -ChildPath 'ExampleModule.psd1') -RootModule 'ExampleModule.psm1' -ModuleVersion '1.0.0' -FunctionsToExport 'Get-ExampleValue'

        try {
            $result = Initialize-AtlassianPSModuleTestEnvironment -ModuleName 'ExampleModule' -StartPath $nested -Global

            $result | Should -Be (Join-Path -Path $modulePath -ChildPath 'ExampleModule.psd1')
            Get-Command -Name Get-ExampleValue -Module ExampleModule | Should -Not -BeNullOrEmpty
        }
        finally {
            Remove-Module -Name ExampleModule -Force -ErrorAction SilentlyContinue
        }
    }
}
