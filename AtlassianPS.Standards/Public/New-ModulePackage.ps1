function New-ModulePackage {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$BuildOutputPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$ModuleName,

        [Parameter()]
        [String]$DestinationPath
    )

    $sourcePath = Join-Path -Path $BuildOutputPath -ChildPath $ModuleName
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        throw "Missing files to package at '$sourcePath'."
    }

    if (-not $DestinationPath) {
        $DestinationPath = Join-Path -Path $BuildOutputPath -ChildPath "$ModuleName.zip"
    }

    if ($PSCmdlet.ShouldProcess($DestinationPath, "Create package from '$sourcePath'")) {
        Remove-Item -Path $DestinationPath -ErrorAction SilentlyContinue
        $null = Compress-Archive -Path $sourcePath -DestinationPath $DestinationPath
    }

    return $DestinationPath
}
