function Resolve-AtlassianPSPesterTestFile {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param(
        [Parameter(Mandatory)]
        [String[]]$Path
    )

    $testFiles = @(
        foreach ($item in $Path) {
            $resolvedPath = Resolve-Path -Path $item -ErrorAction SilentlyContinue
            foreach ($pathInfo in @($resolvedPath)) {
                if (Test-Path -LiteralPath $pathInfo.ProviderPath -PathType Container) {
                    Get-ChildItem -LiteralPath $pathInfo.ProviderPath -Filter '*.Tests.ps1' -File
                }
                else {
                    Get-Item -LiteralPath $pathInfo.ProviderPath
                }
            }
        }
    )

    @($testFiles | Sort-Object -Property FullName -Unique)
}
