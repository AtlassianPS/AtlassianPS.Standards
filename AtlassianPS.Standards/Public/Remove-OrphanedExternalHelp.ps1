function Remove-OrphanedExternalHelp {
    <#
    .SYNOPSIS
        Removes generated help files that no longer have markdown sources.

    .PARAMETER ModulePath
        Path to the module source directory that contains generated locale folders.

    .PARAMETER DocsPath
        Path to the docs root that contains locale folders.

    .PARAMETER ModuleName
        Module name used for command MAML file names.

    .PARAMETER CommandRelativePath
        Relative glob pattern below each locale docs folder for command markdown files.

    .PARAMETER AboutTopicRelativePath
        Relative glob patterns below each locale docs folder that contain about-topic markdown files.

    .OUTPUTS
        None. Removes generated help files and directories when their markdown sources no longer exist.

    .EXAMPLE
        Remove-AtlassianPSOrphanedExternalHelp -ModulePath './JiraPS' -DocsPath './docs' -ModuleName 'JiraPS'

        Removes stale generated help artifacts from locale folders in the JiraPS module directory.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Build helper removes generated help artifacts only from generated locale output folders.')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ModulePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$DocsPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ModuleName,

        [Parameter()]
        [String]$CommandRelativePath = 'commands/*.md',

        [Parameter()]
        [String[]]$AboutTopicRelativePath = @('about_*.md')
    )

    if (-not (Test-Path -LiteralPath $ModulePath -PathType Container)) { return }
    if (-not (Test-Path -LiteralPath $DocsPath -PathType Container)) { return }

    $isHelpOutputDir = {
        param($Directory)
        $files = @(Get-ChildItem -LiteralPath $Directory.FullName -File -ErrorAction SilentlyContinue)
        if ($files.Count -eq 0) { return $false }
        @($files | Where-Object { $_.Name -notlike '*.help.txt' -and $_.Name -notlike '*-help.xml' }).Count -eq 0
    }

    $helpDirs = Get-ChildItem -LiteralPath $ModulePath -Directory -ErrorAction SilentlyContinue |
        Where-Object { & $isHelpOutputDir $_ }

    foreach ($localeDir in $helpDirs) {
        $localeDocs = Join-Path -Path $DocsPath -ChildPath $localeDir.Name
        if (-not (Test-Path -LiteralPath $localeDocs -PathType Container)) {
            if ($PSCmdlet.ShouldProcess($localeDir.FullName, 'Remove generated help locale directory without source docs')) {
                Remove-Item -LiteralPath $localeDir.FullName -Recurse -Force
            }
            continue
        }

        $expected = [System.Collections.Generic.HashSet[String]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $hasCommandHelp = Get-ChildItem -Path (Join-Path -Path $localeDocs -ChildPath $CommandRelativePath) -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'index.md' -and $_.Name -notlike 'about_*.md' } |
            Select-Object -First 1
        if ($hasCommandHelp) {
            $null = $expected.Add("$ModuleName-help.xml")
        }

        foreach ($relativePath in $AboutTopicRelativePath) {
            Get-ChildItem -Path (Join-Path -Path $localeDocs -ChildPath $relativePath) -File -ErrorAction SilentlyContinue |
                ForEach-Object { $null = $expected.Add("$($_.BaseName).help.txt") }
        }

        Get-ChildItem -LiteralPath $localeDir.FullName -File -ErrorAction SilentlyContinue |
            Where-Object { -not $expected.Contains($_.Name) } |
            ForEach-Object {
                if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove orphaned generated help file')) {
                    Remove-Item -LiteralPath $_.FullName -Force
                }
            }
    }
}
