# TODO: Tests for delta application via update.ps1
# Depends on refactoring update.ps1 to use lib/Get-GitHubRelease.ps1 (mock mode)
#
# Planned scenarios:
#   - Simple update (v1.9.0 -> v1.9.1, single app changed)
#   - Verify only changed app files are overwritten
#   - Verify VERSION.txt is updated after apply
#   - Verify unchanged apps are not touched

BeforeAll {
    $script:TestRoot = Join-Path $env:TEMP "delta-apply-tests-$PID"
    New-Item -ItemType Directory $TestRoot -Force | Out-Null
}

AfterAll {
    if (Test-Path $script:TestRoot) {
        Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Delta Application (update.ps1)" {
    Context "Simple Delta Update" {
        It "Should apply delta and update VERSION.txt" -Skip {
            # Requires update.ps1 refactored to accept -InstallPath and mock GitHub API
        }

        It "Should only overwrite changed app directories" -Skip {
            # Verify timestamps on unchanged apps are preserved
        }
    }

    Context "Removed Apps Cleanup" {
        It "Should remove apps no longer in latest release" -Skip {
            # Requires mock user input for confirmation
        }
    }
}
