#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.7"; MaximumVersion = "5.999" }

BeforeAll {
    . "$PSScriptRoot/../../Helpers/TestTools.ps1"
    $script:moduleToTest = Initialize-TestEnvironment
}

Describe 'Test-ReleaseIntent' {
    It 'accepts internal changes with release:none and no changelog intent' {
        $result = InModuleScope AtlassianPS.Standards {
            Test-ReleaseIntent -LabelName @('release:none') -ChangedFilePath @('Tests/Foo.Tests.ps1') -PullRequestNumber 42
        }

        $result.IsValid | Should -BeTrue
        $result.ReleaseImpact | Should -Be 'none'
        $result.ChangelogType | Should -BeNullOrEmpty
    }

    It 'accepts user-facing changes with release and changelog labels' {
        $result = InModuleScope AtlassianPS.Standards {
            Test-ReleaseIntent -LabelName @('release:patch', 'changelog:fixed') -ChangedFilePath @('Public/Get-Thing.ps1') -PullRequestNumber 42
        }

        $result.IsValid | Should -BeTrue
        $result.ReleaseImpact | Should -Be 'patch'
        $result.ChangelogType | Should -Be 'fixed'
        $result.HasChangelogFragment | Should -BeFalse
    }

    It 'accepts a custom changelog fragment instead of a changelog label' {
        $result = InModuleScope AtlassianPS.Standards {
            Test-ReleaseIntent -LabelName @('release:minor') -ChangedFilePath @('.changelog/42.minor.added.md') -PullRequestNumber 42
        }

        $result.IsValid | Should -BeTrue
        $result.ReleaseImpact | Should -Be 'minor'
        $result.ChangelogType | Should -Be 'added'
        $result.HasChangelogFragment | Should -BeTrue
        $result.ChangelogFragment | Should -Be '.changelog/42.minor.added.md'
    }

    It 'requires exactly one release label' {
        $missing = InModuleScope AtlassianPS.Standards {
            Test-ReleaseIntent -LabelName @('changelog:fixed') -ChangedFilePath @('Public/Get-Thing.ps1') -PullRequestNumber 42
        }
        $multiple = InModuleScope AtlassianPS.Standards {
            Test-ReleaseIntent -LabelName @('release:patch', 'release:minor', 'changelog:fixed') -ChangedFilePath @('Public/Get-Thing.ps1') -PullRequestNumber 42
        }

        $missing.IsValid | Should -BeFalse
        $missing.Messages | Should -Contain 'Add exactly one release label: release:none, release:patch, release:minor, or release:major.'
        $multiple.IsValid | Should -BeFalse
        $multiple.Messages | Should -Contain 'Add exactly one release label: release:none, release:patch, release:minor, or release:major.'
    }

    It 'returns validation messages for unlabeled pull requests' {
        $result = InModuleScope AtlassianPS.Standards {
            Test-ReleaseIntent -LabelName @() -ChangedFilePath @('Public/Get-Thing.ps1') -PullRequestNumber 42
        }

        $result.IsValid | Should -BeFalse
        $result.Messages | Should -Contain 'Add exactly one release label: release:none, release:patch, release:minor, or release:major.'
    }

    It 'rejects release:none with changelog labels or fragments' {
        $result = InModuleScope AtlassianPS.Standards {
            Test-ReleaseIntent -LabelName @('release:none', 'changelog:fixed') -ChangedFilePath @('.changelog/42.patch.fixed.md') -PullRequestNumber 42
        }

        $result.IsValid | Should -BeFalse
        $result.Messages | Should -Contain 'release:none must not be combined with changelog labels.'
        $result.Messages | Should -Contain 'release:none must not include changelog fragments.'
    }

    It 'requires changelog intent for release-bearing changes' {
        $result = InModuleScope AtlassianPS.Standards {
            Test-ReleaseIntent -LabelName @('release:patch') -ChangedFilePath @('Public/Get-Thing.ps1') -PullRequestNumber 42
        }

        $result.IsValid | Should -BeFalse
        $result.Messages | Should -Contain 'For release:patch, release:minor, or release:major, add exactly one changelog label or one valid changelog fragment.'
    }

    It 'rejects invalid changelog fragment names' {
        $result = InModuleScope AtlassianPS.Standards {
            Test-ReleaseIntent -LabelName @('release:patch') -ChangedFilePath @('.changelog/41.patch.fixed.md') -PullRequestNumber 42
        }

        $result.IsValid | Should -BeFalse
        $result.Messages[0] | Should -Be "Changelog fragment '.changelog/41.patch.fixed.md' must be named '.changelog/42.<patch|minor|major>.<added|changed|fixed|removed|deprecated|security|breaking>.md'."
    }

    It 'requires fragment impact and type to match labels when both are present' {
        $result = InModuleScope AtlassianPS.Standards {
            Test-ReleaseIntent -LabelName @('release:patch', 'changelog:fixed') -ChangedFilePath @('.changelog/42.minor.added.md') -PullRequestNumber 42
        }

        $result.IsValid | Should -BeFalse
        $result.Messages | Should -Contain "Changelog fragment impact 'minor' must match release label 'release:patch'."
        $result.Messages | Should -Contain "Changelog fragment type 'added' must match label 'changelog:fixed'."
    }

    It 'rejects unknown release and changelog labels' {
        $result = InModuleScope AtlassianPS.Standards {
            Test-ReleaseIntent -LabelName @('release:banana', 'changelog:misc') -ChangedFilePath @('Public/Get-Thing.ps1') -PullRequestNumber 42
        }

        $result.IsValid | Should -BeFalse
        $result.Messages | Should -Contain "Unknown release label 'release:banana'. Use one of: release:none, release:patch, release:minor, release:major."
        $result.Messages | Should -Contain "Unknown changelog label 'changelog:misc'. Use one of: changelog:added, changelog:changed, changelog:fixed, changelog:removed, changelog:deprecated, changelog:security, changelog:breaking."
    }

    It 'requires release:major for breaking changes' {
        $labelResult = InModuleScope AtlassianPS.Standards {
            Test-ReleaseIntent -LabelName @('release:minor', 'changelog:breaking') -ChangedFilePath @('Public/Get-Thing.ps1') -PullRequestNumber 42
        }
        $fragmentResult = InModuleScope AtlassianPS.Standards {
            Test-ReleaseIntent -LabelName @('release:patch') -ChangedFilePath @('.changelog/42.patch.breaking.md') -PullRequestNumber 42
        }

        $labelResult.IsValid | Should -BeFalse
        $labelResult.Messages | Should -Contain 'changelog:breaking and breaking changelog fragments require release:major.'
        $fragmentResult.IsValid | Should -BeFalse
        $fragmentResult.Messages | Should -Contain 'changelog:breaking and breaking changelog fragments require release:major.'
    }
}
