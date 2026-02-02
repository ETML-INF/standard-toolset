BeforeAll {
    # Setup test workspace
    $script:TestRoot = Join-Path $env:TEMP "version-detect-tests-$PID"
    New-Item -ItemType Directory $TestRoot -Force | Out-Null

    Write-Host "Test workspace: $script:TestRoot" -ForegroundColor Cyan
}

AfterAll {
    # Cleanup
    if (Test-Path $script:TestRoot) {
        Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Version Detection" {
    Context "Modern Installation (VERSION.txt exists)" {
        BeforeEach {
            $script:InstallPath = Join-Path $TestRoot "modern-install-$([guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -ItemType Directory $InstallPath -Force | Out-Null

            # Create VERSION.txt
            "v1.9.0" | Out-File "$InstallPath\VERSION.txt"

            # Also create versions.txt for completeness
            @"
Name Version
---- -------
git 2.40.0
node 18.0.0
"@ | Out-File "$InstallPath\versions.txt"
        }

        AfterEach {
            if (Test-Path $InstallPath) {
                Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should detect version from VERSION.txt" {
            $detection = & "$PSScriptRoot\..\..\detect-version.ps1" -InstallPath $InstallPath

            $detection.Version | Should -Be "v1.9.0"
            $detection.Source | Should -Be "VERSION.txt"
            $detection.Confidence | Should -Be "high"
        }
    }

    Context "Legacy Installation (only versions.txt)" {
        BeforeEach {
            $script:InstallPath = Join-Path $TestRoot "legacy-install-$([guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -ItemType Directory $InstallPath -Force | Out-Null

            # Only versions.txt, no VERSION.txt
            @"
Name Version
---- -------
git 2.39.0
node 16.0.0
"@ | Out-File "$InstallPath\versions.txt"
        }

        AfterEach {
            if (Test-Path $InstallPath) {
                Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should detect as pre-v1.9.0 installation" {
            $detection = & "$PSScriptRoot\..\..\detect-version.ps1" -InstallPath $InstallPath

            $detection.Version | Should -Be "pre-v1.9.0"
            $detection.Source | Should -Be "fingerprint"
            $detection.Confidence | Should -Be "medium"
        }
    }

    Context "Very Legacy Installation (scoop only)" {
        BeforeEach {
            $script:InstallPath = Join-Path $TestRoot "verylegacy-install-$([guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -ItemType Directory "$InstallPath\scoop\apps\scoop\current\bin" -Force | Out-Null

            # Create scoop.ps1 to indicate it's a scoop installation
            "# Mock scoop" | Out-File "$InstallPath\scoop\apps\scoop\current\bin\scoop.ps1"
        }

        AfterEach {
            if (Test-Path $InstallPath) {
                Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should detect as legacy installation" {
            $detection = & "$PSScriptRoot\..\..\detect-version.ps1" -InstallPath $InstallPath

            $detection.Version | Should -Be "legacy"
            $detection.Source | Should -Be "scoop-detection"
            $detection.Confidence | Should -Be "low"
        }
    }

    Context "Unknown/Empty Installation" {
        BeforeEach {
            $script:InstallPath = Join-Path $TestRoot "empty-install-$([guid]::NewGuid().ToString().Substring(0,8))"
            New-Item -ItemType Directory $InstallPath -Force | Out-Null
            # Empty directory
        }

        AfterEach {
            if (Test-Path $InstallPath) {
                Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should return unknown version" {
            $detection = & "$PSScriptRoot\..\..\detect-version.ps1" -InstallPath $InstallPath

            $detection.Version | Should -Be "unknown"
            $detection.Confidence | Should -Be "low"
        }
    }

    Context "Missing Installation Path" {
        It "Should handle missing path gracefully" {
            $nonExistentPath = Join-Path $TestRoot "does-not-exist-$([guid]::NewGuid().ToString())"

            { & "$PSScriptRoot\..\..\detect-version.ps1" -InstallPath $nonExistentPath 2>&1 } |
                Should -Throw
        }
    }
}
