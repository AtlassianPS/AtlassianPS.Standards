function Update-ExternalHelp {
    <#
    .SYNOPSIS
        Generates external help from PlatyPS markdown and repairs MAML metadata.

    .DESCRIPTION
        Generates command MAML and about-topic help text for each locale under a
        docs root. The command MAML generation includes the PlatyPS v1 repairs used
        by AtlassianPS modules: flatten nested module output, restore aliases,
        pipeline input, default values, and split example prose/code into the nodes
        consumed by Get-Help.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$DocsPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ModulePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ModuleName,

        [Parameter()]
        [String]$CommandRelativePath = 'commands/*.md',

        [Parameter()]
        [String[]]$AboutTopicRelativePath = @('about_*.md')
    )

    if (-not (Test-Path -LiteralPath $DocsPath -PathType Container)) {
        throw "Docs path '$DocsPath' was not found."
    }
    if (-not (Test-Path -LiteralPath $ModulePath -PathType Container)) {
        throw "Module path '$ModulePath' was not found."
    }

    $platyPSWasLoaded = [Boolean](Get-Module -Name Microsoft.PowerShell.PlatyPS)
    Import-Module Microsoft.PowerShell.PlatyPS -Force
    try {
        foreach ($locale in (Get-ChildItem -LiteralPath $DocsPath -Directory)) {
            $outputPath = Join-Path -Path $ModulePath -ChildPath $locale.BaseName
            $null = New-Item -ItemType Directory -Path $outputPath -Force

            $commandHelpFiles = Get-ChildItem -Path (Join-Path -Path $locale.FullName -ChildPath $CommandRelativePath) -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne 'index.md' -and $_.Name -notlike 'about_*.md' }

            if ($commandHelpFiles -and $PSCmdlet.ShouldProcess($outputPath, 'Generate command MAML help')) {
                $commandHelp = @($commandHelpFiles | Import-MarkdownCommandHelp)
                $commandHelp | Export-MamlCommandHelp -OutputFolder $outputPath -Force

                $nestedPath = Join-Path -Path $outputPath -ChildPath $ModuleName
                if (Test-Path -LiteralPath $nestedPath -PathType Container) {
                    Get-ChildItem -LiteralPath $nestedPath -Filter '*.xml' -File | Move-Item -Destination $outputPath -Force
                    Remove-Item -LiteralPath $nestedPath -Recurse -Force
                }

                $mamlFile = Join-Path -Path $outputPath -ChildPath "$ModuleName-help.xml"
                if (-not (Test-Path -LiteralPath $mamlFile -PathType Leaf)) {
                    throw "Expected MAML help file was not created: $mamlFile"
                }

                Repair-AtlassianPSMamlHelp -MamlFile $mamlFile -CommandHelp $commandHelp
            }

            $utf8Bom = [System.Text.UTF8Encoding]::new($true)
            foreach ($relativePath in $AboutTopicRelativePath) {
                Get-ChildItem -Path (Join-Path -Path $locale.FullName -ChildPath $relativePath) -File -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        $helpTextName = $_.BaseName + '.help.txt'
                        $content = [System.IO.File]::ReadAllText($_.FullName)
                        $content = $content -replace '\A---\r?\n[\s\S]*?\r?\n---\r?\n?', ''
                        $helpTextPath = Join-Path -Path $outputPath -ChildPath $helpTextName
                        if ($PSCmdlet.ShouldProcess($helpTextPath, 'Write about-topic help text')) {
                            [System.IO.File]::WriteAllText($helpTextPath, $content, $utf8Bom)
                        }
                    }
            }
        }
    }
    finally {
        if (-not $platyPSWasLoaded) {
            Remove-Module Microsoft.PowerShell.PlatyPS -ErrorAction SilentlyContinue
        }
    }
}
