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

function Get-ReleaseNotesFromChangelog {
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ChangelogPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ReleaseVersion
    )

    if (-not (Test-Path -LiteralPath $ChangelogPath -PathType Leaf)) {
        throw "Changelog file was not found at '$ChangelogPath'."
    }

    $normalizedVersion = $ReleaseVersion.Trim()
    if ($normalizedVersion.StartsWith('v')) {
        $normalizedVersion = $normalizedVersion.Substring(1)
    }

    $escapedVersion = [System.Text.RegularExpressions.Regex]::Escape($normalizedVersion)
    $content = Get-Content -LiteralPath $ChangelogPath -Raw
    $match = [System.Text.RegularExpressions.Regex]::Match(
        $content,
        "(?ms)^##\s+v$escapedVersion\s*\r?\n(?<body>.*?)(?=^##\s+|\z)"
    )

    if (-not $match.Success) {
        throw "Could not find changelog section '## v$normalizedVersion' in '$ChangelogPath'."
    }

    $releaseNotes = $match.Groups['body'].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($releaseNotes)) {
        throw "Changelog section '## v$normalizedVersion' in '$ChangelogPath' is empty."
    }

    return $releaseNotes
}

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
    Publish-AtlassianPSModuleRelease `
        -BuildOutputPath $env:BHBuildOutput `
        -ModuleName $env:BHProjectName `
        -ApiKey $PSGalleryAPIKey
}

Task SetVersion {
    if (-not $script:BuildInfo.VersionToPublish) {
        throw 'VersionToPublish is required for SetVersion. Use -VersionToPublish <semver>.'
    }

    $changelogPath = Join-Path -Path $env:BHProjectPath -ChildPath 'CHANGELOG.md'
    $releaseNotes = Get-ReleaseNotesFromChangelog -ChangelogPath $changelogPath -ReleaseVersion $script:BuildInfo.VersionToPublish

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
