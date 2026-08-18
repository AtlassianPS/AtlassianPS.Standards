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
    [String[]]$ExcludeTag
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

# Synopsis: Stamp the planned version into the committed source manifest (release notes stay empty here).
Task SetSourceVersion {
    if (-not $script:BuildInfo.VersionToPublish) {
        throw 'VersionToPublish is required for SetSourceVersion. Use -VersionToPublish <semver>.'
    }

    $null = Set-AtlassianPSModuleManifestVersion `
        -BuiltManifestPath $env:BHPSModuleManifest `
        -ModuleName $env:BHProjectName `
        -VersionToPublish $script:BuildInfo.VersionToPublish
}

# Synopsis: Stamp the planned version and release notes into the built artifact.
Task SetVersion {
    if (-not $script:BuildInfo.VersionToPublish) {
        throw 'VersionToPublish is required for SetVersion. Use -VersionToPublish <semver>.'
    }

    $builtManifestPath = $script:BuildInfo.BuiltManifestPath
    $changelogPath = Join-Path -Path $env:BHProjectPath -ChildPath 'CHANGELOG.md'
    $releaseNotes = Get-AtlassianPSReleaseNotesFromChangelog -ChangelogPath $changelogPath -ReleaseVersion $script:BuildInfo.VersionToPublish

    $null = Set-AtlassianPSModuleManifestVersion `
        -BuiltManifestPath $builtManifestPath `
        -ModuleName $env:BHProjectName `
        -VersionToPublish $script:BuildInfo.VersionToPublish `
        -ReleaseNotes $releaseNotes
}

# Synopsis: Compress the built module into the publishable release artifact
Task Package {
    $script:PackagePath = New-AtlassianPSModulePackage `
        -BuildOutputPath $env:BHBuildOutput `
        -ModuleName $env:BHProjectName
}

Task VerifyReleaseArtifact Package, {
    if (-not $script:BuildInfo.VersionToPublish) {
        throw 'VersionToPublish is required for VerifyReleaseArtifact. Use -VersionToPublish <semver>.'
    }

    $expectedVersion = $script:BuildInfo.VersionToPublish.TrimStart('v')
    $null = Test-AtlassianPSModulePackage `
        -BuildOutputPath $env:BHBuildOutput `
        -ModuleName $env:BHProjectName `
        -PackagePath $script:PackagePath `
        -ExpectedVersion $expectedVersion `
        -RequireReleaseNotes
}

Task TestPublish Build, Package, {
    $null = Test-AtlassianPSModulePackage `
        -BuildOutputPath $env:BHBuildOutput `
        -ModuleName $env:BHProjectName `
        -PackagePath $script:PackagePath
}

Task . Lint, Build, Test
