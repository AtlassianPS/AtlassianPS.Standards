#requires -modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0'; MaximumVersion = '6.999' }

BeforeAll {
    . "$PSScriptRoot/Helpers/TestTools.ps1"
    $script:moduleToTest = Initialize-TestEnvironment
    $script:planner = Join-Path $PSScriptRoot '../.github/actions/plan-merged-release/plan-merged-release.ps1'
}

Describe 'Candidate manifest and archive identity' {
    BeforeEach {
        $script:output = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
        $script:modulePath = Join-Path $output 'CandidateSample'
        $null = New-Item -Path $modulePath -ItemType Directory -Force
        $script:manifestPath = Join-Path $modulePath 'CandidateSample.psd1'
        New-ModuleManifest -Path $manifestPath -RootModule CandidateSample.psm1 -ModuleVersion 0.3.0 -Prerelease alpha0001 -ReleaseNotes 'Candidate notes'
        Set-Content (Join-Path $modulePath 'CandidateSample.psm1') 'function Get-CandidateSample { "candidate" }'
        $script:packagePath = New-AtlassianPSModulePackage -BuildOutputPath $output -ModuleName CandidateSample
    }

    It 'verifies the exact alpha in the built and packaged manifests' {
        $result = Test-AtlassianPSModulePackage -BuildOutputPath $output -ModuleName CandidateSample -ExpectedVersion 0.3.0-alpha0001 -RequireReleaseNotes
        $result.Version | Should -Be ([Version]'0.3.0')
        $result.FullVersion | Should -BeExactly '0.3.0-alpha0001'
    }

    It 'rejects a numeric version, other candidate, beta, or stable expectation' -ForEach @(
        @{ Expected = '0.3.0' }, @{ Expected = '0.3.0-alpha0002' },
        @{ Expected = '0.3.0-beta0001' }, @{ Expected = '0.4.0-alpha0001' }
    ) {
        { Test-AtlassianPSModulePackage -BuildOutputPath $output -ModuleName CandidateSample -ExpectedVersion $Expected } |
            Should -Throw -ExpectedMessage '*does not match expected*'
    }

    It 'rejects a same-numeric archive with a different prerelease label' {
        $null = Set-AtlassianPSModuleManifestVersion -BuiltManifestPath $manifestPath -ModuleName CandidateSample -VersionToPublish 0.3.0-beta0001
        { Test-AtlassianPSModulePackage -BuildOutputPath $output -ModuleName CandidateSample } |
            Should -Throw -ExpectedMessage '*prerelease label*'
    }

    It 'rejects archive release notes that differ from the built directory' {
        $null = Set-AtlassianPSModuleManifestVersion -BuiltManifestPath $manifestPath -ModuleName CandidateSample -VersionToPublish 0.3.0-alpha0001 -ReleaseNotes 'Changed notes'
        { Test-AtlassianPSModulePackage -BuildOutputPath $output -ModuleName CandidateSample } |
            Should -Throw -ExpectedMessage '*release notes do not match*'
    }

    It 'loads a hash-verified archive in a fresh process and checks the full version and loaded path' {
        $helper = Join-Path $PSScriptRoot '../AtlassianPS.Standards/AtlassianPS.Standards.psd1'
        $consumer = Join-Path $TestDrive 'consume.ps1'
        Set-Content $consumer @'
param($Helper, $Package, $Digest, $Destination)
$ErrorActionPreference = 'Stop'
Import-Module $Helper -Force -ErrorAction Stop
$result = Install-AtlassianPSModuleCandidate -ModuleName CandidateSample -RequiredVersion 0.3.0-alpha0001 -DestinationPath $Destination -PackagePath $Package -PackageSha256 $Digest
if ($result.FullVersion -cne '0.3.0-alpha0001' -or (Get-Module CandidateSample).Path -cne $result.ModulePath) { throw 'Wrong loaded candidate.' }
if ((Get-CandidateSample) -cne 'candidate') { throw 'Wrong candidate implementation.' }
'candidate acquired'
'@
        $digest = (Get-FileHash $packagePath -Algorithm SHA256).Hash
        $shell = (Get-Process -Id $PID).Path
        $result = & $shell -NoLogo -NonInteractive -NoProfile -File $consumer $helper $packagePath $digest (Join-Path $TestDrive 'installed') 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($result -join "`n")
        $result | Should -Contain 'candidate acquired'
    }

    It 'rejects a corrupted archive before extraction' {
        { Install-AtlassianPSModuleCandidate -ModuleName CandidateSample -RequiredVersion 0.3.0-alpha0001 -DestinationPath $TestDrive -PackagePath $packagePath -PackageSha256 ('0' * 64) } |
            Should -Throw -ExpectedMessage '*SHA256 mismatch*'
    }

    It 'rejects archived code that differs from the tested built directory' {
        Set-Content (Join-Path $modulePath 'CandidateSample.psm1') 'function Get-CandidateSample { "changed" }'
        { Test-AtlassianPSModulePackage -BuildOutputPath $output -ModuleName CandidateSample } |
            Should -Throw -ExpectedMessage '*Packaged file*differs*'
    }
}

Describe 'Candidate planning' {
    BeforeEach {
        $script:savedEnvironment = @{}
        foreach ($name in @('GITHUB_REPOSITORY', 'GITHUB_OUTPUT', 'RELEASE_IMPACT', 'RELEASE_CHANNEL', 'MAJOR_AUTHORIZATION', 'ATLAS_TEST_CANDIDATE_TAGS')) {
            $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
        }
        $env:GITHUB_REPOSITORY = 'AtlassianPS/CandidateSample'
        $env:GITHUB_OUTPUT = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N') + '.txt')
        $env:RELEASE_IMPACT = 'minor'
        $env:RELEASE_CHANNEL = 'alpha'
        $env:MAJOR_AUTHORIZATION = ''
        $env:ATLAS_TEST_CANDIDATE_TAGS = 'v0.2.0;v0.3.0-alpha0001;v0.3.0-alpha0002'
        function git {
            if ($args[0] -eq 'tag') { $env:ATLAS_TEST_CANDIDATE_TAGS -split ';'; return }
            if ($args[0] -eq 'show-ref') { $global:LASTEXITCODE = 1; return }
            throw "Unexpected git invocation: $args"
        }
        function gh { throw "Candidate planning must not generate merged-PR fragments: $args" }
    }
    AfterEach {
        foreach ($name in $savedEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name])
        }
    }

    It 'increments the alpha sequence independently of the numeric base' {
        & $planner
        Get-Content $env:GITHUB_OUTPUT -Raw | Should -Match 'release_tag=v0.3.0-alpha0003'
    }

    It 'starts beta at 0001 and stable retains the same numeric base' {
        $env:RELEASE_CHANNEL = 'beta'
        & $planner
        Get-Content $env:GITHUB_OUTPUT -Raw | Should -Match 'release_tag=v0.3.0-beta0001'
        $env:RELEASE_CHANNEL = 'stable'
        & $planner
        Get-Content $env:GITHUB_OUTPUT -Raw | Should -Match '(?m)^release_tag=v0.3.0$'
    }

    It 'does not allow alpha after a beta at the same base' {
        $env:ATLAS_TEST_CANDIDATE_TAGS += ';v0.3.0-beta0001'
        { & $planner } | Should -Throw -ExpectedMessage '*already has beta*'
    }

    It 'requires repository and major authorization for a major-base candidate' {
        $env:RELEASE_IMPACT = 'major'
        { & $planner } | Should -Throw -ExpectedMessage '*AtlassianPS/CandidateSample v1*'
        $env:MAJOR_AUTHORIZATION = 'AtlassianPS/Other v1'
        { & $planner } | Should -Throw -ExpectedMessage '*fresh human authorization*'
        $env:MAJOR_AUTHORIZATION = 'AtlassianPS/CandidateSample v1'
        & $planner
        Get-Content $env:GITHUB_OUTPUT -Raw | Should -Match 'release_tag=v1.0.0-alpha0001'
    }
}
