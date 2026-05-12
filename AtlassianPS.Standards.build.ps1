#requires -Modules InvokeBuild
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:ProjectRoot = $PSScriptRoot
$script:ModuleName = 'AtlassianPS.Standards'
$script:ModuleSourcePath = Join-Path -Path $script:ProjectRoot -ChildPath $script:ModuleName
$script:ManifestPath = Join-Path -Path $script:ModuleSourcePath -ChildPath "$script:ModuleName.psd1"
$script:AnalyzerSettingsPath = Join-Path -Path $script:ModuleSourcePath -ChildPath 'PSScriptAnalyzerSettings.psd1'
$script:TestPath = Join-Path -Path $script:ProjectRoot -ChildPath 'Tests'
$script:ToolsPath = Join-Path -Path $script:ProjectRoot -ChildPath 'Tools'
$script:ReleaseRoot = Join-Path -Path $script:ProjectRoot -ChildPath 'Release'
$script:ReleaseModulePath = Join-Path -Path $script:ReleaseRoot -ChildPath $script:ModuleName
$script:TestResultFile = Join-Path -Path $script:ProjectRoot -ChildPath "Test-$([System.Environment]::OSVersion.Platform)-$($PSVersionTable.PSVersion).xml"

task Init {
    Assert (Test-Path -LiteralPath $script:ManifestPath -PathType Leaf) "Module manifest not found at '$script:ManifestPath'."
    Assert (Test-Path -LiteralPath $script:AnalyzerSettingsPath -PathType Leaf) "Analyzer settings file not found at '$script:AnalyzerSettingsPath'."
}

task Clean {
    Remove-Item -Path $script:ReleaseRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path -Path $script:ProjectRoot -ChildPath 'Test-*.xml') -Force -ErrorAction SilentlyContinue
}

task Lint Init, {
    $analysisFiles = @(
        Get-ChildItem -Path $script:ModuleSourcePath, $script:TestPath, $script:ToolsPath -Recurse -File -Include '*.ps1', '*.psm1'
    ) | Sort-Object -Property FullName -Unique

    $analysisResults = foreach ($analysisFile in $analysisFiles) {
        Invoke-ScriptAnalyzer -Path $analysisFile.FullName -Settings $script:AnalyzerSettingsPath
    }

    if ($analysisResults) {
        $analysisResults | Format-Table -AutoSize | Out-String | Write-Output
        throw "PSScriptAnalyzer found $($analysisResults.Count) issue(s)."
    }
}

task Build Init, Clean, {
    $null = New-Item -Path $script:ReleaseModulePath -ItemType Directory -Force
    Copy-Item -Path "$script:ModuleSourcePath/*" -Destination $script:ReleaseModulePath -Recurse -Force
    Copy-Item -Path @(
        (Join-Path -Path $script:ProjectRoot -ChildPath 'README.md')
        (Join-Path -Path $script:ProjectRoot -ChildPath 'LICENSE')
    ) -Destination $script:ReleaseModulePath -Force
}

task Test Build, {
    $env:ATLASSIANPS_STANDARDS_MODULE_MANIFEST = Join-Path -Path $script:ReleaseModulePath -ChildPath "$script:ModuleName.psd1"

    $configuration = New-PesterConfiguration
    $configuration.Run.Path = $script:TestPath
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'Detailed'
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputFormat = 'NUnitXml'
    $configuration.TestResult.OutputPath = $script:TestResultFile

    $results = Invoke-Pester -Configuration $configuration

    if ($results.FailedCount -gt 0) {
        throw "$($results.FailedCount) test(s) failed."
    }
}

task . Lint, Build, Test
