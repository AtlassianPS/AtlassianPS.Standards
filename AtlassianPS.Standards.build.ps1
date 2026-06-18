#requires -Modules InvokeBuild
[CmdletBinding()]
param(
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [String]$PesterVerbosity = 'Normal',

    [Parameter()]
    [String]$VersionToPublish,

    [Parameter()]
    [String[]]$Tag,

    [Parameter()]
    [String[]]$ExcludeTag,

    # Release-publish mode: require the built artifact to already carry the planned version,
    # enforce it is newer than the published package, and verify release notes were written.
    [Parameter()]
    [Switch]$VerifyPublishedRelease
)

$projectName = 'AtlassianPS.Standards'
$moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath "$projectName/$projectName.psd1"

try {
    Import-Module $moduleManifestPath -Force -ErrorAction Stop
}
catch {
    throw "Failed to import '$projectName'. Run './Tools/setup.ps1' and retry. Original error: $($_.Exception.Message)"
}

$script:BuildInfo = Initialize-AtlassianPSBuildEnvironment `
    -ProjectName $projectName `
    -ProjectPath $PSScriptRoot `
    -VersionToPublish $VersionToPublish `
    -ResetBuildEnvironmentVariables

Task ShowDebugInfo {
    Write-AtlassianPSBuildInfo -BuildInfo $script:BuildInfo
}

Task Lint {
    $null = Invoke-AtlassianPSModuleTests `
        -TestPath (Join-Path -Path $env:BHProjectPath -ChildPath 'Tests/DependencyConsistency.Tests.ps1') `
        -PesterVerbosity $PesterVerbosity `
        -DefaultExcludeTag @()

    Invoke-AtlassianPSLint `
        -BuildScriptPath "$env:BHProjectPath/AtlassianPS.Standards.build.ps1" `
        -PesterVerbosity $PesterVerbosity
}

Task Clean {
    $testFiles = Join-Path -Path $env:BHProjectPath -ChildPath 'Test-*.xml'

    Remove-Item -Path $env:BHBuildOutput -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item -Path $testFiles -Force -ErrorAction SilentlyContinue
}

Task CopyBuildArtifacts {
    $additionalFiles = @(
        'CHANGELOG.md'
        'README.md'
        'LICENSE'
    )

    $null = Copy-AtlassianPSModuleArtifacts `
        -ProjectPath $env:BHProjectPath `
        -ModuleName $env:BHProjectName `
        -BuildOutputPath $env:BHBuildOutput `
        -AdditionalFiles $additionalFiles `
        -IncludeTests
}

Task Build Clean, CopyBuildArtifacts, CompileModule, UpdateManifest

# Synopsis: Compile all functions into the .psm1 file
Task CompileModule {
    $releaseModulePath = Join-Path -Path $env:BHBuildOutput -ChildPath $env:BHProjectName
    $null = Join-AtlassianPSModuleSource -ReleaseModulePath $releaseModulePath
}

# Synopsis: Update the manifest of the module
Task UpdateManifest {
    $null = Update-AtlassianPSModuleManifestExports `
        -SourceModulePath $env:BHModulePath `
        -BuiltManifestPath $script:BuildInfo.BuiltManifestPath `
        -ModuleName $env:BHProjectName
}

Task Test {
    $resultOutputPath = Join-Path -Path $env:BHProjectPath -ChildPath "Test-$($script:BuildInfo.OS)-$($PSVersionTable.PSVersion.ToString()).xml"
    $null = Invoke-AtlassianPSModuleTests `
        -TestPath (Join-Path -Path $env:BHProjectPath -ChildPath 'Tests') `
        -PesterVerbosity $PesterVerbosity `
        -Tag $Tag `
        -ExcludeTag $ExcludeTag `
        -DefaultExcludeTag @('Integration', 'Lint') `
        -ResultOutputPath $resultOutputPath
}

Task SetVersion {
    if (-not $script:BuildInfo.VersionToPublish) {
        throw 'VersionToPublish is required for SetVersion. Use -VersionToPublish <semver>.'
    }

    $builtManifestPath = $script:BuildInfo.BuiltManifestPath
    $expectedCore = $script:BuildInfo.VersionToPublish -replace '-.*$', ''

    # In release-publish mode the artifact is the CI-tested package built from the already
    # version-stamped source manifest, so it must already carry the planned version. A mismatch
    # means the prepare step never stamped the source manifest (the original release defect).
    if ($VerifyPublishedRelease) {
        $built = Import-PowerShellDataFile -LiteralPath $builtManifestPath
        if ($built.ModuleVersion -ne $expectedCore) {
            throw "Built artifact ModuleVersion '$($built.ModuleVersion)' does not match release version '$($script:BuildInfo.VersionToPublish)'. The prepare step did not stamp the source manifest version."
        }
    }

    $changelogPath = Join-Path -Path $env:BHProjectPath -ChildPath 'CHANGELOG.md'
    $releaseNotes = Get-AtlassianPSReleaseNotesFromChangelog -ChangelogPath $changelogPath -ReleaseVersion $script:BuildInfo.VersionToPublish

    $setVersionParameters = @{
        BuiltManifestPath = $builtManifestPath
        ModuleName        = $env:BHProjectName
        VersionToPublish  = $script:BuildInfo.VersionToPublish
        ReleaseNotes      = $releaseNotes
    }
    if ($VerifyPublishedRelease) {
        $setVersionParameters.EnforceGreaterThanPublished = $true
    }

    $null = Set-AtlassianPSModuleManifestVersion @setVersionParameters

    # Confirm the immutable package will publish with the intended version and non-empty notes.
    if ($VerifyPublishedRelease) {
        $stamped = Import-PowerShellDataFile -LiteralPath $builtManifestPath
        if ($stamped.ModuleVersion -ne $expectedCore) {
            throw "Artifact ModuleVersion '$($stamped.ModuleVersion)' does not match expected '$expectedCore' after stamping."
        }
        if ([string]::IsNullOrWhiteSpace($stamped.PrivateData.PSData.ReleaseNotes)) {
            throw 'Artifact PrivateData.PSData.ReleaseNotes is empty after stamping.'
        }
    }
}

Task TestPublish Build, {
    $packagePath = New-AtlassianPSModulePackage `
        -BuildOutputPath $env:BHBuildOutput `
        -ModuleName $env:BHProjectName

    $null = Test-AtlassianPSModulePackage `
        -BuildOutputPath $env:BHBuildOutput `
        -ModuleName $env:BHProjectName `
        -PackagePath $packagePath
}

Task . Lint, Build, Test
