#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

Describe 'Release artifact downstream contract' {
    It 'loads the built module and runs the exported prefixed lint command in a fresh process' {
        $projectRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath
        $manifestPath = Join-Path -Path $projectRoot -ChildPath 'Release/AtlassianPS.Standards/AtlassianPS.Standards.psd1'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw "Built module manifest was not found at '$manifestPath'. Run Invoke-Build -Task Build before running this test."
        }

        $powerShellPath = (Get-Process -Id $PID).Path
        $script = @'
param([string]$ManifestPath)

$ErrorActionPreference = 'Stop'
$projectPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString())
$modulePath = Join-Path -Path $projectPath -ChildPath 'Sample.Module'
$testsPath = Join-Path -Path $projectPath -ChildPath 'Tests'
$stylePath = Join-Path -Path $testsPath -ChildPath 'Style.Tests.ps1'
$settingsPath = Join-Path -Path $projectPath -ChildPath 'PSScriptAnalyzerSettings.psd1'
$buildScriptPath = Join-Path -Path $projectPath -ChildPath 'Sample.Module.build.ps1'

try {
    $null = New-Item -Path $modulePath -ItemType Directory -Force
    $null = New-Item -Path $testsPath -ItemType Directory -Force
    Set-Content -LiteralPath $stylePath -Value 'Describe "style" { It "passes" { $true | Should -BeTrue } }'
    Set-Content -LiteralPath $settingsPath -Value '@{ IncludeRules = @() }'
    Set-Content -LiteralPath $buildScriptPath -Value '$null = $true'

    Import-Module -Name $ManifestPath -Force -ErrorAction Stop
    $result = Invoke-AtlassianPSLint `
        -ProjectPath $projectPath `
        -ModulePath $modulePath `
        -BuildScriptPath $buildScriptPath `
        -AnalyzerSettingsPath $settingsPath `
        -AnalyzerPaths @($buildScriptPath) `
        -PesterVerbosity None

    if ($result.StyleFailedCount -ne 0 -or $result.AnalyzerIssueCount -ne 0) {
        throw "Unexpected lint result: $($result | ConvertTo-Json -Compress)"
    }
}
finally {
    Remove-Item -LiteralPath $projectPath -Recurse -Force -ErrorAction SilentlyContinue
}
'@
        $scriptPath = Join-Path -Path $TestDrive -ChildPath 'Invoke-ReleaseArtifactLint.ps1'
        Set-Content -LiteralPath $scriptPath -Value $script

        $output = & $powerShellPath -NoLogo -NoProfile -NonInteractive -File $scriptPath $manifestPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Release artifact lint smoke failed with exit code $LASTEXITCODE.`n$output"
        }
    }
}
