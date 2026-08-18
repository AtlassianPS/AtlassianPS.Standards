#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"
    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Import-DotEnvFile' {
    BeforeEach {
        [Environment]::SetEnvironmentVariable('ATLAS_TEST_ENV_EXISTING', $null)
        [Environment]::SetEnvironmentVariable('ATLAS_TEST_ENV_ALLOWED', $null)
        [Environment]::SetEnvironmentVariable('ATLAS_TEST_ENV_EXCLUDED', $null)
        [Environment]::SetEnvironmentVariable('ATLAS_TEST_ENV_HASH', $null)
        [Environment]::SetEnvironmentVariable('ATLAS_TEST_ENV_QUOTED', $null)
    }

    AfterEach {
        [Environment]::SetEnvironmentVariable('ATLAS_TEST_ENV_EXISTING', $null)
        [Environment]::SetEnvironmentVariable('ATLAS_TEST_ENV_ALLOWED', $null)
        [Environment]::SetEnvironmentVariable('ATLAS_TEST_ENV_EXCLUDED', $null)
        [Environment]::SetEnvironmentVariable('ATLAS_TEST_ENV_HASH', $null)
        [Environment]::SetEnvironmentVariable('ATLAS_TEST_ENV_QUOTED', $null)
    }

    It 'loads variables and overwrites existing process values' {
        $envFile = Join-Path -Path $TestDrive -ChildPath 'test.env'
        Set-Content -LiteralPath $envFile -Value @(
            '# comment'
            'ATLAS_TEST_ENV_EXISTING=from-file'
            'ATLAS_TEST_ENV_ALLOWED=value  # inline comment'
        )
        [Environment]::SetEnvironmentVariable('ATLAS_TEST_ENV_EXISTING', 'from-process')

        $result = Import-AtlassianPSDotEnvFile -Path $envFile

        $env:ATLAS_TEST_ENV_EXISTING | Should -Be 'from-file'
        $env:ATLAS_TEST_ENV_ALLOWED | Should -Be 'value'
        @($result).Name | Should -Contain 'ATLAS_TEST_ENV_EXISTING'
        @($result).PSObject.Properties.Name | Should -Not -Contain 'Value'
    }

    It 'preserves hash characters inside values and skips excluded names' {
        $envFile = Join-Path -Path $TestDrive -ChildPath 'test-hash.env'
        Set-Content -LiteralPath $envFile -Value @(
            'ATLAS_TEST_ENV_HASH=abc#123'
            'ATLAS_TEST_ENV_QUOTED="quoted # value"'
            'ATLAS_TEST_ENV_EXCLUDED=skip-me'
        )

        $null = Import-AtlassianPSDotEnvFile -Path $envFile -ExcludeName 'ATLAS_TEST_ENV_EXCLUDED'

        $env:ATLAS_TEST_ENV_HASH | Should -Be 'abc#123'
        $env:ATLAS_TEST_ENV_QUOTED | Should -Be 'quoted # value'
        $env:ATLAS_TEST_ENV_EXCLUDED | Should -BeNullOrEmpty
    }

    It 'ignores missing files' {
        $result = Import-AtlassianPSDotEnvFile -Path (Join-Path -Path $TestDrive -ChildPath 'missing.env')

        $result | Should -BeNullOrEmpty
    }
}

Describe 'Test-ModulePackage' {
    BeforeAll {
        function ConvertTo-TestNuspec {
            param(
                [Parameter(Mandatory)]
                [String]$ModuleName,

                [Parameter(Mandatory)]
                [String]$Version,

                [String]$ReleaseNotes = ''
            )

            @"
<?xml version="1.0"?>
<package>
  <metadata>
    <id>$ModuleName</id>
    <version>$Version</version>
    <releaseNotes>$ReleaseNotes</releaseNotes>
  </metadata>
</package>
"@
        }
    }

    It 'validates a release module directory, manifest, and package' {
        $buildOutput = Join-Path -Path $TestDrive -ChildPath 'Release'
        $moduleName = 'PackageValidation'
        $modulePath = Join-Path -Path $buildOutput -ChildPath $moduleName
        $null = New-Item -Path $modulePath -ItemType Directory -Force
        New-ModuleManifest -Path (Join-Path -Path $modulePath -ChildPath "$moduleName.psd1") -RootModule "$moduleName.psm1" -ModuleVersion '1.2.3'
        Set-Content -LiteralPath (Join-Path -Path $modulePath -ChildPath "$moduleName.psm1") -Value ''
        Compress-Archive -Path $modulePath -DestinationPath (Join-Path -Path $buildOutput -ChildPath "$moduleName.zip")

        $galleryRoot = Join-Path -Path $TestDrive -ChildPath 'gallery-package'
        $null = New-Item -Path $galleryRoot -ItemType Directory -Force
        Copy-Item -Path (Join-Path -Path $modulePath -ChildPath '*') -Destination $galleryRoot -Recurse
        ConvertTo-TestNuspec -ModuleName $moduleName -Version '1.2.3' |
            Set-Content -LiteralPath (Join-Path -Path $galleryRoot -ChildPath "$moduleName.nuspec")
        $galleryPackagePath = Join-Path -Path $buildOutput -ChildPath "$moduleName.1.2.3.nupkg"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($galleryRoot, $galleryPackagePath)

        $result = Test-AtlassianPSModulePackage `
            -BuildOutputPath $buildOutput `
            -ModuleName $moduleName `
            -GalleryPackagePath $galleryPackagePath

        $result.Name | Should -Be $moduleName
        $result.Version | Should -Be ([Version]'1.2.3')
        $result.GalleryPackagePath | Should -Be $galleryPackagePath
    }

    It 'requires matching version and release notes when requested' {
        $buildOutput = Join-Path -Path $TestDrive -ChildPath 'Release-metadata'
        $moduleName = 'PackageMetadata'
        $modulePath = Join-Path -Path $buildOutput -ChildPath $moduleName
        $null = New-Item -Path $modulePath -ItemType Directory -Force
        $manifestPath = Join-Path -Path $modulePath -ChildPath "$moduleName.psd1"
        Set-Content -LiteralPath $manifestPath -Value @"
@{
    RootModule = '$moduleName.psm1'
    ModuleVersion = '1.2.3'
    GUID = 'b558bd8c-dc02-4ff2-96b7-4d2c61d9d103'
    PrivateData = @{
        PSData = @{
            ReleaseNotes = 'Release notes'
        }
    }
}
"@
        Set-Content -LiteralPath (Join-Path -Path $modulePath -ChildPath "$moduleName.psm1") -Value ''
        Compress-Archive -Path $modulePath -DestinationPath (Join-Path -Path $buildOutput -ChildPath "$moduleName.zip")

        $result = Test-AtlassianPSModulePackage `
            -BuildOutputPath $buildOutput `
            -ModuleName $moduleName `
            -ExpectedVersion '1.2.3' `
            -RequireReleaseNotes

        $result.Version | Should -Be ([Version]'1.2.3')
    }

    It 'rejects a mismatched expected version' {
        $buildOutput = Join-Path -Path $TestDrive -ChildPath 'Release-version-mismatch'
        $moduleName = 'VersionMismatch'
        $modulePath = Join-Path -Path $buildOutput -ChildPath $moduleName
        $null = New-Item -Path $modulePath -ItemType Directory -Force
        New-ModuleManifest -Path (Join-Path -Path $modulePath -ChildPath "$moduleName.psd1") -RootModule "$moduleName.psm1" -ModuleVersion '1.2.3'
        Set-Content -LiteralPath (Join-Path -Path $modulePath -ChildPath "$moduleName.psm1") -Value ''
        Compress-Archive -Path $modulePath -DestinationPath (Join-Path -Path $buildOutput -ChildPath "$moduleName.zip")

        {
            Test-AtlassianPSModulePackage -BuildOutputPath $buildOutput -ModuleName $moduleName -ExpectedVersion '1.2.4'
        } | Should -Throw -ExpectedMessage '*does not match expected*'
    }

    It 'rejects a mismatched expected prerelease label' {
        $buildOutput = Join-Path -Path $TestDrive -ChildPath 'Release-prerelease-mismatch'
        $moduleName = 'PrereleaseMismatch'
        $modulePath = Join-Path -Path $buildOutput -ChildPath $moduleName
        $null = New-Item -Path $modulePath -ItemType Directory -Force
        $manifestPath = Join-Path -Path $modulePath -ChildPath "$moduleName.psd1"
        Set-Content -LiteralPath $manifestPath -Value @"
@{
    RootModule = '$moduleName.psm1'
    ModuleVersion = '1.2.3'
    GUID = 'b558bd8c-dc02-4ff2-96b7-4d2c61d9d103'
    PrivateData = @{ PSData = @{ Prerelease = 'beta' } }
}
"@
        Set-Content -LiteralPath (Join-Path -Path $modulePath -ChildPath "$moduleName.psm1") -Value ''
        Compress-Archive -Path $modulePath -DestinationPath (Join-Path -Path $buildOutput -ChildPath "$moduleName.zip")

        {
            Test-AtlassianPSModulePackage -BuildOutputPath $buildOutput -ModuleName $moduleName -ExpectedPrerelease 'rc-2'
        } | Should -Throw -ExpectedMessage '*prerelease*does not match expected*'
    }

    It 'throws when the release package is missing' {
        $buildOutput = Join-Path -Path $TestDrive -ChildPath 'Release-missing-package'
        $moduleName = 'MissingPackage'
        $modulePath = Join-Path -Path $buildOutput -ChildPath $moduleName
        $null = New-Item -Path $modulePath -ItemType Directory -Force
        New-ModuleManifest -Path (Join-Path -Path $modulePath -ChildPath "$moduleName.psd1") -RootModule "$moduleName.psm1" -ModuleVersion '1.0.0'
        Set-Content -LiteralPath (Join-Path -Path $modulePath -ChildPath "$moduleName.psm1") -Value ''

        {
            Test-AtlassianPSModulePackage -BuildOutputPath $buildOutput -ModuleName $moduleName
        } | Should -Throw -ExpectedMessage 'Release package was not created*'
    }

    It 'throws when the release package does not contain the expected manifest' {
        $buildOutput = Join-Path -Path $TestDrive -ChildPath 'Release-invalid-package'
        $moduleName = 'InvalidPackage'
        $modulePath = Join-Path -Path $buildOutput -ChildPath $moduleName
        $otherPath = Join-Path -Path $buildOutput -ChildPath 'OtherModule'
        $null = New-Item -Path $modulePath, $otherPath -ItemType Directory -Force
        New-ModuleManifest -Path (Join-Path -Path $modulePath -ChildPath "$moduleName.psd1") -RootModule "$moduleName.psm1" -ModuleVersion '1.0.0'
        Set-Content -LiteralPath (Join-Path -Path $modulePath -ChildPath "$moduleName.psm1") -Value ''
        Set-Content -LiteralPath (Join-Path -Path $otherPath -ChildPath 'OtherModule.psd1') -Value '@{ ModuleVersion = ''1.0.0'' }'
        Compress-Archive -Path $otherPath -DestinationPath (Join-Path -Path $buildOutput -ChildPath "$moduleName.zip")

        {
            Test-AtlassianPSModulePackage -BuildOutputPath $buildOutput -ModuleName $moduleName
        } | Should -Throw -ExpectedMessage '*does not contain expected manifest*'
    }

    It 'rejects a PSGallery package missing a built module file' {
        $buildOutput = Join-Path -Path $TestDrive -ChildPath 'Release-invalid-gallery-package'
        $moduleName = 'InvalidGalleryPackage'
        $modulePath = Join-Path -Path $buildOutput -ChildPath $moduleName
        $galleryRoot = Join-Path -Path $TestDrive -ChildPath 'invalid-gallery-package'
        $null = New-Item -Path $modulePath, $galleryRoot -ItemType Directory -Force
        $manifestPath = Join-Path -Path $modulePath -ChildPath "$moduleName.psd1"
        New-ModuleManifest -Path $manifestPath -RootModule "$moduleName.psm1" -ModuleVersion '1.0.0'
        Set-Content -LiteralPath (Join-Path -Path $modulePath -ChildPath "$moduleName.psm1") -Value 'function Get-Thing {}'
        Compress-Archive -Path $modulePath -DestinationPath (Join-Path -Path $buildOutput -ChildPath "$moduleName.zip")

        Copy-Item -LiteralPath $manifestPath -Destination $galleryRoot
        $galleryPackagePath = Join-Path -Path $buildOutput -ChildPath "$moduleName.1.0.0.nupkg"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($galleryRoot, $galleryPackagePath)

        {
            Test-AtlassianPSModulePackage `
                -BuildOutputPath $buildOutput `
                -ModuleName $moduleName `
                -GalleryPackagePath $galleryPackagePath
        } | Should -Throw -ExpectedMessage '*does not contain built module file*psm1*'
    }

    It 'rejects a PSGallery package without a nuspec' {
        $buildOutput = Join-Path -Path $TestDrive -ChildPath 'Release-gallery-missing-nuspec'
        $moduleName = 'MissingNuspec'
        $modulePath = Join-Path -Path $buildOutput -ChildPath $moduleName
        $galleryRoot = Join-Path -Path $TestDrive -ChildPath 'gallery-missing-nuspec'
        $null = New-Item -Path $modulePath, $galleryRoot -ItemType Directory -Force
        New-ModuleManifest -Path (Join-Path -Path $modulePath -ChildPath "$moduleName.psd1") -RootModule "$moduleName.psm1" -ModuleVersion '1.0.0'
        Set-Content -LiteralPath (Join-Path -Path $modulePath -ChildPath "$moduleName.psm1") -Value ''
        Compress-Archive -Path $modulePath -DestinationPath (Join-Path -Path $buildOutput -ChildPath "$moduleName.zip")
        Copy-Item -Path (Join-Path -Path $modulePath -ChildPath '*') -Destination $galleryRoot -Recurse
        $galleryPackagePath = Join-Path -Path $buildOutput -ChildPath "$moduleName.1.0.0.nupkg"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($galleryRoot, $galleryPackagePath)

        {
            Test-AtlassianPSModulePackage `
                -BuildOutputPath $buildOutput `
                -ModuleName $moduleName `
                -GalleryPackagePath $galleryPackagePath
        } | Should -Throw -ExpectedMessage '*exactly one nuspec file; found 0*'
    }

    It 'rejects mismatched PSGallery nuspec metadata' {
        $buildOutput = Join-Path -Path $TestDrive -ChildPath 'Release-gallery-wrong-nuspec'
        $moduleName = 'WrongNuspec'
        $modulePath = Join-Path -Path $buildOutput -ChildPath $moduleName
        $galleryRoot = Join-Path -Path $TestDrive -ChildPath 'gallery-wrong-nuspec'
        $null = New-Item -Path $modulePath, $galleryRoot -ItemType Directory -Force
        New-ModuleManifest -Path (Join-Path -Path $modulePath -ChildPath "$moduleName.psd1") -RootModule "$moduleName.psm1" -ModuleVersion '1.0.0'
        Set-Content -LiteralPath (Join-Path -Path $modulePath -ChildPath "$moduleName.psm1") -Value ''
        Compress-Archive -Path $modulePath -DestinationPath (Join-Path -Path $buildOutput -ChildPath "$moduleName.zip")
        Copy-Item -Path (Join-Path -Path $modulePath -ChildPath '*') -Destination $galleryRoot -Recurse
        ConvertTo-TestNuspec -ModuleName $moduleName -Version '2.0.0' |
            Set-Content -LiteralPath (Join-Path -Path $galleryRoot -ChildPath "$moduleName.nuspec")
        $galleryPackagePath = Join-Path -Path $buildOutput -ChildPath "$moduleName.1.0.0.nupkg"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($galleryRoot, $galleryPackagePath)

        {
            Test-AtlassianPSModulePackage `
                -BuildOutputPath $buildOutput `
                -ModuleName $moduleName `
                -GalleryPackagePath $galleryPackagePath
        } | Should -Throw -ExpectedMessage '*nuspec version*does not match*1.0.0*'
    }

    It 'rejects a PSGallery package with multiple nuspec files' {
        $buildOutput = Join-Path -Path $TestDrive -ChildPath 'Release-gallery-multiple-nuspec'
        $moduleName = 'MultipleNuspec'
        $modulePath = Join-Path -Path $buildOutput -ChildPath $moduleName
        $galleryRoot = Join-Path -Path $TestDrive -ChildPath 'gallery-multiple-nuspec'
        $null = New-Item -Path $modulePath, $galleryRoot -ItemType Directory -Force
        New-ModuleManifest -Path (Join-Path -Path $modulePath -ChildPath "$moduleName.psd1") -RootModule "$moduleName.psm1" -ModuleVersion '1.0.0'
        Set-Content -LiteralPath (Join-Path -Path $modulePath -ChildPath "$moduleName.psm1") -Value ''
        Compress-Archive -Path $modulePath -DestinationPath (Join-Path -Path $buildOutput -ChildPath "$moduleName.zip")
        Copy-Item -Path (Join-Path -Path $modulePath -ChildPath '*') -Destination $galleryRoot -Recurse
        ConvertTo-TestNuspec -ModuleName $moduleName -Version '1.0.0' |
            Set-Content -LiteralPath (Join-Path -Path $galleryRoot -ChildPath 'one.nuspec')
        ConvertTo-TestNuspec -ModuleName $moduleName -Version '1.0.0' |
            Set-Content -LiteralPath (Join-Path -Path $galleryRoot -ChildPath 'two.nuspec')
        $galleryPackagePath = Join-Path -Path $buildOutput -ChildPath "$moduleName.1.0.0.nupkg"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($galleryRoot, $galleryPackagePath)

        {
            Test-AtlassianPSModulePackage `
                -BuildOutputPath $buildOutput `
                -ModuleName $moduleName `
                -GalleryPackagePath $galleryPackagePath
        } | Should -Throw -ExpectedMessage '*exactly one nuspec file; found 2*'
    }
}

Describe 'Remove-OrphanedExternalHelp' {
    It 'removes generated help files without source markdown' {
        $root = Join-Path -Path $TestDrive -ChildPath 'help'
        $modulePath = Join-Path -Path $root -ChildPath 'Module'
        $docsPath = Join-Path -Path $root -ChildPath 'docs'
        $localeOut = Join-Path -Path $modulePath -ChildPath 'en-US'
        $localeDocs = Join-Path -Path $docsPath -ChildPath 'en-US'
        $commandsPath = Join-Path -Path $localeDocs -ChildPath 'commands'
        $null = New-Item -Path $localeOut, $commandsPath -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path -Path $commandsPath -ChildPath 'Get-Thing.md') -Value '# Get-Thing'
        Set-Content -LiteralPath (Join-Path -Path $localeDocs -ChildPath 'about_Module.md') -Value '# about'
        Set-Content -LiteralPath (Join-Path -Path $localeOut -ChildPath 'Module-help.xml') -Value '<help />'
        Set-Content -LiteralPath (Join-Path -Path $localeOut -ChildPath 'about_Module.help.txt') -Value 'about'
        Set-Content -LiteralPath (Join-Path -Path $localeOut -ChildPath 'orphan.help.txt') -Value 'orphan'

        Remove-AtlassianPSOrphanedExternalHelp -ModulePath $modulePath -DocsPath $docsPath -ModuleName 'Module'

        Test-Path -LiteralPath (Join-Path -Path $localeOut -ChildPath 'Module-help.xml') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $localeOut -ChildPath 'about_Module.help.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $localeOut -ChildPath 'orphan.help.txt') | Should -BeFalse
    }

    It 'honors additional about-topic relative paths' {
        $root = Join-Path -Path $TestDrive -ChildPath 'extra-about-help'
        $modulePath = Join-Path -Path $root -ChildPath 'Module'
        $docsPath = Join-Path -Path $root -ChildPath 'docs'
        $localeOut = Join-Path -Path $modulePath -ChildPath 'en-US'
        $localeDocs = Join-Path -Path $docsPath -ChildPath 'en-US'
        $commandsPath = Join-Path -Path $localeDocs -ChildPath 'commands'
        $null = New-Item -Path $localeOut, $commandsPath -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path -Path $commandsPath -ChildPath 'about_Module.md') -Value '# about'
        Set-Content -LiteralPath (Join-Path -Path $localeOut -ChildPath 'about_Module.help.txt') -Value 'about'
        Set-Content -LiteralPath (Join-Path -Path $localeOut -ChildPath 'orphan.help.txt') -Value 'orphan'

        Remove-AtlassianPSOrphanedExternalHelp -ModulePath $modulePath -DocsPath $docsPath -ModuleName 'Module' -AboutTopicRelativePath @('about_*.md', 'commands/about_*.md')

        Test-Path -LiteralPath (Join-Path -Path $localeOut -ChildPath 'about_Module.help.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $localeOut -ChildPath 'orphan.help.txt') | Should -BeFalse
    }
}
