function Invoke-ModuleBuild {
    <#
    .SYNOPSIS
        Runs the common AtlassianPS module build sequence.

    .DESCRIPTION
        Performs the reusable module build pipeline used by AtlassianPS module
        repositories: optional clean, optional external-help generation and orphan
        cleanup, artifact copy, module source compilation, and manifest export
        update.

        Repository build scripts remain responsible for declaring Invoke-Build tasks
        and any product-specific pre/post steps. This command centralizes the
        repeated implementation inside those tasks.

    .PARAMETER ProjectPath
        Repository root path that contains the source module directory.

    .PARAMETER ModuleName
        Name of the module directory and manifest.

    .PARAMETER BuildOutputPath
        Build output root. Defaults to Release below ProjectPath.

    .PARAMETER BuiltManifestPath
        Path to the manifest in the built module. Defaults to <BuildOutputPath>/<ModuleName>/<ModuleName>.psd1.

    .PARAMETER AdditionalFiles
        Additional repository files to copy into the release module directory.

    .PARAMETER IncludeTests
        Copies the repository Tests directory into the build output.

    .PARAMETER Clean
        Removes the build output and Test*.xml files before building.

    .PARAMETER GenerateExternalHelp
        Generates external help from markdown and removes stale generated help files before copying artifacts.

    .PARAMETER DocsPath
        Documentation root containing locale folders. Defaults to docs below ProjectPath.

    .PARAMETER AboutTopicRelativePath
        Relative glob patterns below each locale docs folder for about-topic markdown files.

    .PARAMETER CommandHelpRelativePath
        Relative glob pattern below each locale docs folder for command markdown files.

    .PARAMETER RegionsToKeep
        Region names to preserve from the source .psm1 before appending Public and Private source files.

    .PARAMETER SourceFolders
        Source folders below the release module path to merge into the built .psm1.

    .OUTPUTS
        PSCustomObject with source, release, compiled module, manifest, function export, and alias export metadata.

    .EXAMPLE
        Invoke-AtlassianPSModuleBuild -ProjectPath $env:BHProjectPath -ModuleName $env:BHProjectName -BuildOutputPath $env:BHBuildOutput -IncludeTests -Clean

        Runs the common module build pipeline from an Invoke-Build task.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ProjectPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ModuleName,

        [Parameter()]
        [String]$BuildOutputPath,

        [Parameter()]
        [String]$BuiltManifestPath,

        [Parameter()]
        [String[]]$AdditionalFiles = @('CHANGELOG.md', 'LICENSE', 'README.md'),

        [Parameter()]
        [Switch]$IncludeTests,

        [Parameter()]
        [Switch]$Clean,

        [Parameter()]
        [Switch]$GenerateExternalHelp,

        [Parameter()]
        [String]$DocsPath,

        [Parameter()]
        [String[]]$AboutTopicRelativePath = @('about_*.md'),

        [Parameter()]
        [String]$CommandHelpRelativePath = 'commands/*.md',

        [Parameter()]
        [String[]]$RegionsToKeep = @('Dependencies', 'Configuration'),

        [Parameter()]
        [String[]]$SourceFolders = @('Public', 'Private')
    )

    $resolvedProjectPath = (Resolve-Path -LiteralPath $ProjectPath).ProviderPath
    if (-not $BuildOutputPath) {
        $BuildOutputPath = Join-Path -Path $resolvedProjectPath -ChildPath 'Release'
    }
    if (-not $BuiltManifestPath) {
        $BuiltManifestPath = Join-Path -Path (Join-Path -Path $BuildOutputPath -ChildPath $ModuleName) -ChildPath "$ModuleName.psd1"
    }
    if (-not $DocsPath) {
        $DocsPath = Join-Path -Path $resolvedProjectPath -ChildPath 'docs'
    }

    $sourceModulePath = Join-Path -Path $resolvedProjectPath -ChildPath $ModuleName
    if (-not (Test-Path -LiteralPath $sourceModulePath -PathType Container)) {
        throw "Module source path '$sourceModulePath' was not found."
    }

    if ($Clean) {
        Remove-Item -LiteralPath $BuildOutputPath -Force -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path -Path $resolvedProjectPath -ChildPath 'Test*.xml') -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path -LiteralPath (Join-Path -Path $BuildOutputPath -ChildPath $ModuleName) -PathType Container)) {
        $null = New-Item -Path (Join-Path -Path $BuildOutputPath -ChildPath $ModuleName) -ItemType Directory -Force
    }

    if ($GenerateExternalHelp) {
        Update-ExternalHelp `
            -DocsPath $DocsPath `
            -ModulePath $sourceModulePath `
            -ModuleName $ModuleName `
            -CommandRelativePath $CommandHelpRelativePath `
            -AboutTopicRelativePath $AboutTopicRelativePath

        Remove-OrphanedExternalHelp `
            -ModulePath $sourceModulePath `
            -DocsPath $DocsPath `
            -ModuleName $ModuleName `
            -CommandRelativePath $CommandHelpRelativePath `
            -AboutTopicRelativePath $AboutTopicRelativePath
    }

    $copyResult = Copy-ModuleArtifacts `
        -ProjectPath $resolvedProjectPath `
        -ModuleName $ModuleName `
        -BuildOutputPath $BuildOutputPath `
        -AdditionalFiles $AdditionalFiles `
        -IncludeTests:$IncludeTests

    $compiledModulePath = Join-ModuleSource `
        -ReleaseModulePath $copyResult.ReleaseModulePath `
        -SourceFolders $SourceFolders `
        -RegionsToKeep $RegionsToKeep

    $manifestResult = Update-ModuleManifestExports `
        -SourceModulePath $sourceModulePath `
        -BuiltManifestPath $BuiltManifestPath `
        -ModuleName $ModuleName

    return [PSCustomObject]@{
        ProjectPath        = $resolvedProjectPath
        SourceModulePath   = $sourceModulePath
        ReleaseModulePath  = $copyResult.ReleaseModulePath
        CompiledModulePath = $compiledModulePath
        BuiltManifestPath  = $BuiltManifestPath
        FunctionsToExport  = $manifestResult.FunctionsToExport
        AliasesToExport    = $manifestResult.AliasesToExport
    }
}
