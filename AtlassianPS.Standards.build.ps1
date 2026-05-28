#requires -Modules InvokeBuild
[CmdletBinding()]
param(
    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [String]$PesterVerbosity = 'Normal',

    [Parameter()]
    [String]$VersionToPublish,

    [Parameter()]
    [String]$PSGalleryAPIKey,

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

Task Publish SetVersion, Package, {
    $releasePath = Join-Path -Path $env:BHBuildOutput -ChildPath $env:BHProjectName
    if (-not (Test-Path -LiteralPath $releasePath -PathType Container)) {
        throw "Expected release path '$releasePath' does not exist. Run the Build task before publishing."
    }

    Publish-Module -Path $releasePath -NuGetApiKey $PSGalleryAPIKey -ErrorAction Stop
}

Task SetVersion {
    if (-not $script:BuildInfo.VersionToPublish) {
        throw 'VersionToPublish is required for SetVersion. Use -VersionToPublish <semver>.'
    }

    $changelogPath = Join-Path -Path $env:BHProjectPath -ChildPath 'CHANGELOG.md'
    $releaseNotes = Get-AtlassianPSReleaseNotesFromChangelog -ChangelogPath $changelogPath -ReleaseVersion $script:BuildInfo.VersionToPublish

    $null = Set-AtlassianPSModuleManifestVersion `
        -BuiltManifestPath $script:BuildInfo.BuiltManifestPath `
        -ModuleName $env:BHProjectName `
        -VersionToPublish $script:BuildInfo.VersionToPublish `
        -ReleaseNotes $releaseNotes
}

Task Package {
    $null = New-AtlassianPSModulePackage `
        -BuildOutputPath $env:BHBuildOutput `
        -ModuleName $env:BHProjectName
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
