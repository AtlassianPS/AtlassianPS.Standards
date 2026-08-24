#requires -modules @{ ModuleName = "Pester"; ModuleVersion = "5.9.0"; MaximumVersion = "5.9.999" }

Describe "Style rules" -Tag "Lint", "Unit", "Style" {
    BeforeAll {
        . "$PSScriptRoot/Helpers/TestTools.ps1"

        $projectRoot = Resolve-ProjectRoot
        ${/} = [System.IO.Path]::DirectorySeparatorChar

        # -Force ensures dot-prefixed files are checked on Unix-like hosts.
        $script:codeFiles = @(
            Get-ChildItem -Path $projectRoot -Recurse -File -Force -Include '*.ps1', '*.psm1', '*.psd1' |
                Where-Object { $_.FullName -notlike "*${/}Release${/}*" }
        )
        $script:docFiles = @(
            Get-ChildItem -Path $projectRoot -Recurse -File -Force -Include '*.md' |
                Where-Object { $_.FullName -notlike "*${/}Release${/}*" }
        )
    }

    It "discovers PowerShell files" {
        $codeFiles.Count | Should -BeGreaterThan 0
    }

    It "has no trailing whitespace in code files" {
        $badLines = @(
            foreach ($file in $codeFiles) {
                $lines = [System.IO.File]::ReadAllLines($file.FullName)
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($lines[$i] -match '\s+$') {
                        'File: {0}, Line: {1}' -f $file.FullName, ($i + 1)
                    }
                }
            }
        )

        if ($badLines.Count -gt 0) {
            throw "The following $($badLines.Count) lines contain trailing whitespace:`n  $($badLines -join "`n  ")"
        }
    }

    It "has one newline at the end of files" {
        $badFiles = @(
            foreach ($file in @($codeFiles + $docFiles)) {
                $content = [System.IO.File]::ReadAllText($file.FullName)
                if ($content.Length -gt 0 -and $content[-1] -ne "`n") {
                    $file.FullName
                }
            }
        )

        if ($badFiles.Count -gt 0) {
            throw "The following files do not end with a newline:`n  $($badFiles -join "`n  ")"
        }
    }

    It "uses UTF-8 with BOM for code files" {
        $badFiles = @(
            foreach ($file in $codeFiles) {
                $encoding = Get-FileEncoding -Path $file.FullName
                if ($encoding -and $encoding.Encoding -ne "UTF8-BOM") {
                    $file.FullName
                }
            }
        )

        if ($badFiles.Count -gt 0) {
            throw "The following files are not encoded with UTF-8 BOM (required for PS v5 compatibility):`n  $($badFiles -join "`n  ")"
        }
    }

    It "uses UTF-8 without BOM for documentation files" {
        $badFiles = @(
            foreach ($file in $docFiles) {
                $encoding = Get-FileEncoding -Path $file.FullName
                if ($encoding -and $encoding.Encoding -ne "UTF8") {
                    $file.FullName
                }
            }
        )

        if ($badFiles.Count -gt 0) {
            throw "The following files are not encoded with UTF-8 (no BOM):`n  $($badFiles -join "`n  ")"
        }
    }

    It "uses CRLF line endings for code files" {
        $badFiles = @(
            foreach ($file in $codeFiles) {
                $content = [System.IO.File]::ReadAllText($file.FullName)
                if ($content.Length -gt 0 -and $content -notmatch "`r`n$") {
                    $file.FullName
                }
            }
        )

        if ($badFiles.Count -gt 0) {
            throw "The following files do not use CRLF line endings:`n  $($badFiles -join "`n  ")"
        }
    }

    It "uses LF line endings for documentation files" {
        $badFiles = @(
            foreach ($file in $docFiles) {
                $content = [System.IO.File]::ReadAllText($file.FullName)
                if ($content.Length -gt 0 -and $content -notmatch "`n$") {
                    $file.FullName
                }
            }
        )

        if ($badFiles.Count -gt 0) {
            throw "The following files do not use LF line endings:`n  $($badFiles -join "`n  ")"
        }
    }
}
