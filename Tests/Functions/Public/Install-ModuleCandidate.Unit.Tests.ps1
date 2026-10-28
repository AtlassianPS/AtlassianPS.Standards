#requires -modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0'; MaximumVersion = '6.999' }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"
    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Exact Gallery candidate acquisition' {
    BeforeEach {
        $script:savedModulePath = $env:PSModulePath
        $script:sampleRoot = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
        $sample = Join-Path $sampleRoot 'AcquisitionSample/0.3.0'
        $support = Join-Path $sampleRoot 'AcquisitionSupport/1.0.0'
        $null = New-Item $sample, $support -ItemType Directory -Force
        New-ModuleManifest -Path (Join-Path $support 'AcquisitionSupport.psd1') -RootModule AcquisitionSupport.psm1 -ModuleVersion 1.0.0
        Set-Content (Join-Path $support 'AcquisitionSupport.psm1') 'function Get-AcquisitionSupport { "saved dependency" }'
        Set-Content (Join-Path $sample 'AcquisitionSample.psd1') @'
@{
    RootModule = 'AcquisitionSample.psm1'
    ModuleVersion = '0.3.0'
    GUID = '06fca3e7-1f86-490c-a9da-5c9a21b7ab99'
    FunctionsToExport = '*'
    PrivateData = @{ PSData = @{ Prerelease = 'beta0002' } }
    RequiredModules = @(@{ ModuleName = 'AcquisitionSupport'; ModuleVersion = '1.0.0' })
}
'@
        Set-Content (Join-Path $sample 'AcquisitionSample.psm1') 'function Get-AcquisitionSample { Get-AcquisitionSupport }'
    }
    AfterEach {
        Remove-Module AcquisitionSample, AcquisitionSupport -Force -ErrorAction SilentlyContinue
        $env:PSModulePath = $savedModulePath
    }

    It 'opts in to the exact full candidate, resolves saved dependencies, and exposes the imported command globally' {
        InModuleScope AtlassianPS.Standards -Parameters @{ Samples = $sampleRoot; Destination = (Join-Path $TestDrive 'acquired') } {
            param($Samples, $Destination)
            Mock Save-Module {
                param($Path)
                Copy-Item (Join-Path $Samples '*') $Path -Recurse
            }
            $result = Install-ModuleCandidate -ModuleName AcquisitionSample -RequiredVersion 0.3.0-beta0002 -DestinationPath $Destination
            $result.FullVersion | Should -BeExactly '0.3.0-beta0002'
            $result.ModulePath | Should -BeLike "$Destination*"
            Should -Invoke Save-Module -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'AcquisitionSample' -and $RequiredVersion -eq '0.3.0-beta0002' -and $AllowPrerelease -and $Repository -eq 'PSGallery'
            }
        }
        (Get-Module AcquisitionSample).PrivateData.PSData.Prerelease | Should -BeExactly 'beta0002'
        Get-AcquisitionSample | Should -BeExactly 'saved dependency'
    }

    It 'rejects another candidate with the same numeric version' {
        InModuleScope AtlassianPS.Standards -Parameters @{ Samples = $sampleRoot; Destination = $TestDrive } {
            param($Samples, $Destination)
            Mock Save-Module {
                param($Path)
                Copy-Item (Join-Path $Samples '*') $Path -Recurse
            }
            { Install-ModuleCandidate -ModuleName AcquisitionSample -RequiredVersion 0.3.0-alpha0001 -DestinationPath $Destination } |
                Should -Throw -ExpectedMessage '*expected exact candidate*'
        }
        Get-Module AcquisitionSample | Should -BeNullOrEmpty
    }
}
