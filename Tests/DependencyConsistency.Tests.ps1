#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.9.0"; MaximumVersion = "5.9.999" }

BeforeAll {
    $projectRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath
    $manifestPath = Join-Path -Path $projectRoot -ChildPath 'AtlassianPS.Standards/AtlassianPS.Standards.psd1'
    $buildRequirementsPath = Join-Path -Path $projectRoot -ChildPath 'Tools/build.requirements.psd1'

    $script:manifestData = Import-PowerShellDataFile -Path $manifestPath
    $buildRequirements = @(Import-PowerShellDataFile -Path $buildRequirementsPath)
    $manifestRequirements = @($script:manifestData.RequiredModules)

    $script:manifestRequirementNames = @(
        foreach ($requirement in $manifestRequirements) {
            [string]$requirement.ModuleName
        }
    )
    $script:buildRequirementNames = @(
        foreach ($requirement in $buildRequirements) {
            [string]$requirement.ModuleName
        }
    )
    $script:publicFunctionNames = @(
        Get-ChildItem -Path (Join-Path -Path $projectRoot -ChildPath 'AtlassianPS.Standards/Public/*.ps1') -ErrorAction SilentlyContinue
    ).BaseName
    $script:privateFunctionNames = @(
        Get-ChildItem -Path (Join-Path -Path $projectRoot -ChildPath 'AtlassianPS.Standards/Private/*.ps1') -ErrorAction SilentlyContinue
    ).BaseName
}

Describe 'Dependency declarations' -Tag 'Lint' {
    It 'pins runtime dependency versions in module manifest' {
        foreach ($requirement in $script:manifestData.RequiredModules) {
            $requirement.ModuleName | Should -Not -BeNullOrEmpty
            @($requirement.RequiredVersion, $requirement.ModuleVersion) |
                Where-Object { $_ } |
                Select-Object -First 1 |
                Should -Not -BeNullOrEmpty
        }
    }

    It 'keeps build requirements focused on build-only modules' {
        $overlap = @(
            Compare-Object -ReferenceObject $script:manifestRequirementNames -DifferenceObject $script:buildRequirementNames -IncludeEqual |
                Where-Object { $_.SideIndicator -eq '==' } |
                Select-Object -ExpandProperty InputObject
        )

        $overlap.Count | Should -Be 0
    }

    It 'keeps InvokeBuild in build requirements' {
        $script:buildRequirementNames | Should -Contain 'InvokeBuild'
    }

    It 'does not export functions implemented under Private' {
        $script:publicFunctionNames.Count | Should -BeGreaterThan 0
        $privateExports = @(
            $script:publicFunctionNames | Where-Object { $_ -in $script:privateFunctionNames }
        )

        if ($privateExports.Count -gt 0) {
            throw "Private functions must not be part of the build export set. Found duplicate names: $($privateExports -join ', ')"
        }
    }
}
