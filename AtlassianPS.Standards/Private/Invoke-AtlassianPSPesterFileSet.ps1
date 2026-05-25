function Invoke-AtlassianPSPesterFileSet {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$TestFile,

        [Parameter(Mandatory)]
        [ScriptBlock]$RunTestScriptBlock,

        [Parameter(Mandatory)]
        [String]$ProjectRoot,

        [Parameter()]
        [String[]]$Tag,

        [Parameter()]
        [String[]]$ExcludeTag,

        [Parameter(Mandatory)]
        [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
        [String]$Output,

        [Parameter()]
        [String]$TempResultsDir,

        [Parameter()]
        [Boolean]$GenerateXml
    )

    foreach ($file in $TestFile) {
        & $RunTestScriptBlock $file $ProjectRoot $Tag $ExcludeTag $Output $TempResultsDir $GenerateXml
    }
}
