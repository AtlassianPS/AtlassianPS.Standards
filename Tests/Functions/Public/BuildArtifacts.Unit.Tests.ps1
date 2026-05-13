#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"
    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Copy-ModuleArtifacts' {
    It 'copies module files, additional files, and tests' {
        $projectRoot = Join-Path -Path $TestDrive -ChildPath 'project'
        $moduleName = 'AtlassianPS.Standards'
        $modulePath = Join-Path -Path $projectRoot -ChildPath $moduleName
        $publicPath = Join-Path -Path $modulePath -ChildPath 'Public'
        $testsPath = Join-Path -Path $projectRoot -ChildPath 'Tests'
        $buildOutput = Join-Path -Path $projectRoot -ChildPath 'Release'

        $null = New-Item -Path $publicPath -ItemType Directory -Force
        $null = New-Item -Path $testsPath -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path -Path $publicPath -ChildPath 'Example.ps1') -Value 'function Get-Example { }'
        Set-Content -LiteralPath (Join-Path -Path $projectRoot -ChildPath 'README.md') -Value '# readme'
        Set-Content -LiteralPath (Join-Path -Path $testsPath -ChildPath 'Example.Tests.ps1') -Value 'Describe "x" { }'

        $result = Copy-AtlassianPSModuleArtifacts `
            -ProjectPath $projectRoot `
            -ModuleName $moduleName `
            -BuildOutputPath $buildOutput `
            -AdditionalFiles @('README.md') `
            -IncludeTests

        (Test-Path -LiteralPath (Join-Path -Path $result.ReleaseModulePath -ChildPath 'Public/Example.ps1') -PathType Leaf) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path -Path $result.ReleaseModulePath -ChildPath 'README.md') -PathType Leaf) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path -Path $buildOutput -ChildPath 'Tests/Example.Tests.ps1') -PathType Leaf) | Should -BeTrue
    }

    It 'throws when an additional artifact file is missing' {
        $projectRoot = Join-Path -Path $TestDrive -ChildPath 'project-missing-artifact'
        $moduleName = 'AtlassianPS.Standards'
        $modulePath = Join-Path -Path $projectRoot -ChildPath $moduleName
        $buildOutput = Join-Path -Path $projectRoot -ChildPath 'Release'

        $null = New-Item -Path $modulePath -ItemType Directory -Force

        {
            Copy-AtlassianPSModuleArtifacts `
                -ProjectPath $projectRoot `
                -ModuleName $moduleName `
                -BuildOutputPath $buildOutput `
                -AdditionalFiles @('MISSING.md')
        } | Should -Throw -ExpectedMessage "Artifact source file*was not found."
    }
}

Describe 'Join-ModuleSource' {
    It 'merges function files into psm1 and removes source folders' {
        $releaseModulePath = Join-Path -Path $TestDrive -ChildPath 'Release/AtlassianPS.Standards'
        $publicPath = Join-Path -Path $releaseModulePath -ChildPath 'Public'
        $privatePath = Join-Path -Path $releaseModulePath -ChildPath 'Private'
        $null = New-Item -Path $publicPath -ItemType Directory -Force
        $null = New-Item -Path $privatePath -ItemType Directory -Force

        $psm1Path = Join-Path -Path $releaseModulePath -ChildPath 'AtlassianPS.Standards.psm1'
        Set-Content -LiteralPath $psm1Path -Value @'
#region Dependencies
$null = $true
#endregion
'@
        Set-Content -LiteralPath (Join-Path -Path $publicPath -ChildPath 'Get-Example.ps1') -Value 'function Get-Example { "public" }'
        Set-Content -LiteralPath (Join-Path -Path $privatePath -ChildPath 'Invoke-Example.ps1') -Value 'function Invoke-Example { "private" }'

        $targetFile = Join-AtlassianPSModuleSource -ReleaseModulePath $releaseModulePath

        $targetFile | Should -Be $psm1Path
        (Get-Content -LiteralPath $targetFile -Raw) | Should -Match 'function Get-Example'
        (Get-Content -LiteralPath $targetFile -Raw) | Should -Match 'function Invoke-Example'
        (Get-Content -LiteralPath $targetFile -Raw) | Should -Match '#endregion'
        (Test-Path -LiteralPath $publicPath -PathType Container) | Should -BeFalse
        (Test-Path -LiteralPath $privatePath -PathType Container) | Should -BeFalse
    }

    It 'merges source files in deterministic name order' {
        $releaseModulePath = Join-Path -Path $TestDrive -ChildPath 'Release/DeterministicOrder'
        $publicPath = Join-Path -Path $releaseModulePath -ChildPath 'Public'
        $privatePath = Join-Path -Path $releaseModulePath -ChildPath 'Private'
        $null = New-Item -Path $publicPath -ItemType Directory -Force
        $null = New-Item -Path $privatePath -ItemType Directory -Force

        $psm1Path = Join-Path -Path $releaseModulePath -ChildPath 'DeterministicOrder.psm1'
        Set-Content -LiteralPath $psm1Path -Value @'
#region Dependencies
$null = $true
#endregion
'@
        Set-Content -LiteralPath (Join-Path -Path $publicPath -ChildPath 'Zeta.ps1') -Value 'function Get-Zeta { "z" }'
        Set-Content -LiteralPath (Join-Path -Path $privatePath -ChildPath 'Alpha.ps1') -Value 'function Invoke-Alpha { "a" }'

        $null = Join-AtlassianPSModuleSource -ReleaseModulePath $releaseModulePath -RemoveSourceFolders $false

        $compiled = Get-Content -LiteralPath $psm1Path -Raw
        $compiled.IndexOf('function Invoke-Alpha') | Should -BeLessThan $compiled.IndexOf('function Get-Zeta')
    }

    It 'throws when the module psm1 file is missing' {
        $releaseModulePath = Join-Path -Path $TestDrive -ChildPath 'Release/MissingPsm1'
        $null = New-Item -Path $releaseModulePath -ItemType Directory -Force

        {
            Join-AtlassianPSModuleSource -ReleaseModulePath $releaseModulePath
        } | Should -Throw -ExpectedMessage "Module source file*was not found."
    }

    It 'throws when a source folder escapes the release module path' {
        $releaseModulePath = Join-Path -Path $TestDrive -ChildPath 'Release/Traversal'
        $psm1Path = Join-Path -Path $releaseModulePath -ChildPath 'Traversal.psm1'
        $null = New-Item -Path $releaseModulePath -ItemType Directory -Force
        Set-Content -LiteralPath $psm1Path -Value @'
#region Dependencies
$null = $true
#endregion
'@

        {
            Join-AtlassianPSModuleSource -ReleaseModulePath $releaseModulePath -SourceFolders @('..')
        } | Should -Throw -ExpectedMessage "Source folder*resolves outside release module path*"
    }

    It 'keeps source folders when RemoveSourceFolders is false' {
        $releaseModulePath = Join-Path -Path $TestDrive -ChildPath 'Release/NoDelete'
        $publicPath = Join-Path -Path $releaseModulePath -ChildPath 'Public'
        $privatePath = Join-Path -Path $releaseModulePath -ChildPath 'Private'
        $null = New-Item -Path $publicPath -ItemType Directory -Force
        $null = New-Item -Path $privatePath -ItemType Directory -Force

        $psm1Path = Join-Path -Path $releaseModulePath -ChildPath 'NoDelete.psm1'
        Set-Content -LiteralPath $psm1Path -Value @'
#region Dependencies
$null = $true
#endregion
'@
        Set-Content -LiteralPath (Join-Path -Path $publicPath -ChildPath 'Get-Example.ps1') -Value 'function Get-Example { "public" }'
        Set-Content -LiteralPath (Join-Path -Path $privatePath -ChildPath 'Invoke-Example.ps1') -Value 'function Invoke-Example { "private" }'

        $null = Join-AtlassianPSModuleSource -ReleaseModulePath $releaseModulePath -RemoveSourceFolders $false

        (Test-Path -LiteralPath $publicPath -PathType Container) | Should -BeTrue
        (Test-Path -LiteralPath $privatePath -PathType Container) | Should -BeTrue
    }
}

Describe 'New-ModulePackage' {
    It 'creates a zip package for the release module directory' {
        $buildOutput = Join-Path -Path $TestDrive -ChildPath 'Release'
        $modulePath = Join-Path -Path $buildOutput -ChildPath 'AtlassianPS.Standards'
        $null = New-Item -Path $modulePath -ItemType Directory -Force
        Set-Content -LiteralPath (Join-Path -Path $modulePath -ChildPath 'README.md') -Value 'content'

        $zipPath = New-AtlassianPSModulePackage -BuildOutputPath $buildOutput -ModuleName 'AtlassianPS.Standards'

        (Test-Path -LiteralPath $zipPath -PathType Leaf) | Should -BeTrue
        $zipPath | Should -Match 'AtlassianPS\.Standards\.zip$'
    }

    It 'throws when release files are missing' {
        $buildOutput = Join-Path -Path $TestDrive -ChildPath 'Release-missing'

        {
            New-AtlassianPSModulePackage -BuildOutputPath $buildOutput -ModuleName 'AtlassianPS.Standards'
        } | Should -Throw -ExpectedMessage "Missing files to package*"
    }
}

Describe 'Publish-ModuleRelease' {
    It 'publishes using the release module path and API key' {
        $buildOutput = Join-Path -Path $TestDrive -ChildPath 'Release'
        $moduleName = 'AtlassianPS.Standards'
        $modulePath = Join-Path -Path $buildOutput -ChildPath $moduleName
        $null = New-Item -Path $modulePath -ItemType Directory -Force

        InModuleScope AtlassianPS.Standards -Parameters @{
            BuildOutputPath = $buildOutput
            ModuleName      = $moduleName
        } {
            param($BuildOutputPath, $ModuleName)

            Mock -CommandName Publish-Module -MockWith {}

            Publish-ModuleRelease -BuildOutputPath $BuildOutputPath -ModuleName $ModuleName -ApiKey 'abc'

            Should -Invoke -CommandName Publish-Module -Times 1 -Exactly -Scope It
        }
    }

    It 'throws when release path does not exist' {
        $buildOutput = Join-Path -Path $TestDrive -ChildPath 'Release-missing'

        {
            Publish-AtlassianPSModuleRelease -BuildOutputPath $buildOutput -ModuleName 'AtlassianPS.Standards' -ApiKey 'abc'
        } | Should -Throw -ExpectedMessage "Expected release path*does not exist*"
    }
}
