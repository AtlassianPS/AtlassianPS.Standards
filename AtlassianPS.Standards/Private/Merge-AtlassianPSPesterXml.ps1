function Merge-AtlassianPSPesterXml {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive build/test helper with colored operator output.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]$TempResultsDir,

        [Parameter(Mandatory)]
        [String]$OutputPath,

        [Parameter(Mandatory)]
        [String]$SuiteName,

        [Parameter(Mandatory)]
        [TimeSpan]$Duration,

        [Parameter(Mandatory)]
        [PSCustomObject]$Summary,

        [Parameter(Mandatory)]
        [String]$ProjectRoot
    )

    $xmlFiles = Get-ChildItem -LiteralPath $TempResultsDir -Filter '*.xml' -File -ErrorAction SilentlyContinue
    if ($xmlFiles.Count -eq 0) { return }

    $mergedDoc = [xml]'<?xml version="1.0" encoding="utf-8"?><test-results></test-results>'
    $root = $mergedDoc.DocumentElement
    $root.SetAttribute('name', $SuiteName)
    $root.SetAttribute('total', ($Summary.Passed + $Summary.Failed + $Summary.Skipped).ToString())
    $root.SetAttribute('errors', '0')
    $root.SetAttribute('failures', $Summary.Failed.ToString())
    $root.SetAttribute('not-run', $Summary.Skipped.ToString())
    $root.SetAttribute('inconclusive', '0')
    $root.SetAttribute('ignored', '0')
    $root.SetAttribute('skipped', $Summary.Skipped.ToString())
    $root.SetAttribute('invalid', '0')
    $root.SetAttribute('date', (Get-Date).ToString('yyyy-MM-dd'))
    $root.SetAttribute('time', (Get-Date).ToString('HH:mm:ss'))

    $envElement = $mergedDoc.CreateElement('environment')
    $envElement.SetAttribute('platform', "PowerShell $($PSVersionTable.PSVersion)")
    $envElement.SetAttribute('cwd', $ProjectRoot)
    $envElement.SetAttribute('machine-name', [Environment]::MachineName)
    $envElement.SetAttribute('user', [Environment]::UserName)
    [void]$root.AppendChild($envElement)

    $mainSuite = $mergedDoc.CreateElement('test-suite')
    $mainSuite.SetAttribute('type', 'Assembly')
    $mainSuite.SetAttribute('name', $SuiteName)
    $mainSuite.SetAttribute('executed', 'True')
    $mainSuite.SetAttribute('result', $(if ($Summary.Failed -eq 0) { 'Success' } else { 'Failure' }))
    $mainSuite.SetAttribute('success', $(if ($Summary.Failed -eq 0) { 'True' } else { 'False' }))
    $mainSuite.SetAttribute('time', $Duration.TotalSeconds.ToString('0.000'))
    $mainSuite.SetAttribute('asserts', '0')
    $mainResults = $mergedDoc.CreateElement('results')
    [void]$mainSuite.AppendChild($mainResults)

    foreach ($xmlFile in $xmlFiles) {
        try {
            $fileDoc = [xml](Get-Content -LiteralPath $xmlFile.FullName -Raw)
            $testSuites = $fileDoc.SelectNodes('//test-suite[@type="TestFixture" or @type="Describe"]')
            foreach ($suite in $testSuites) {
                [void]$mainResults.AppendChild($mergedDoc.ImportNode($suite, $true))
            }
        }
        catch {
            Write-Warning "Failed to merge XML from $($xmlFile.Name): $_"
        }
    }

    [void]$root.AppendChild($mainSuite)
    $mergedDoc.Save($OutputPath)
    Write-Host "Test results written to: $OutputPath" -ForegroundColor Cyan
}
