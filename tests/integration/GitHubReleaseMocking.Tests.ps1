BeforeAll {
    # Import helpers
    . "$PSScriptRoot\..\helpers\New-MockReleaseRepository.ps1"

    # Setup test workspace
    $script:TestRoot = Join-Path $env:TEMP "github-mock-tests-$PID"
    New-Item -ItemType Directory $TestRoot -Force | Out-Null

    Write-Host "Test workspace: $script:TestRoot" -ForegroundColor Cyan
}

AfterAll {
    # Cleanup
    if (Test-Path $script:TestRoot) {
        Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "GitHub Release Mocking" {
    Context "Mock Release Repository" {
        BeforeAll {
            # Create mock release repository
            $script:MockRepo = New-MockReleaseRepository -Releases @(
                @{
                    Tag = "v1.9.0"
                    Apps = @{git="2.40.0"; node="18.0.0"; python="3.11.0"}
                },
                @{
                    Tag = "v1.9.1"
                    Apps = @{git="2.40.0"; node="20.0.0"; python="3.11.0"}
                    Delta = $true
                }
            ) -OutputPath (Join-Path $TestRoot "releases")
        }

        It "Should create release directory structure" {
            Test-Path "$MockRepo\v1.9.0" | Should -Be $true
            Test-Path "$MockRepo\v1.9.1" | Should -Be $true
        }

        It "Should create release.json files" {
            Test-Path "$MockRepo\v1.9.0\release.json" | Should -Be $true
            Test-Path "$MockRepo\v1.9.1\release.json" | Should -Be $true
        }

        It "Should create versions.txt files" {
            Test-Path "$MockRepo\v1.9.0\versions.txt" | Should -Be $true

            $content = Get-Content "$MockRepo\v1.9.0\versions.txt"
            $content | Should -Contain "git 2.40.0"
            $content | Should -Contain "node 18.0.0"
        }

        It "Should create toolset.zip archives" {
            Test-Path "$MockRepo\v1.9.0\toolset.zip" | Should -Be $true
            (Get-Item "$MockRepo\v1.9.0\toolset.zip").Length | Should -BeGreaterThan 0
        }

        It "Should create delta package for v1.9.1" {
            Test-Path "$MockRepo\v1.9.1\delta-from-v1.9.0.zip" | Should -Be $true
        }

        It "Should set latest pointer" {
            Test-Path "$MockRepo\latest" | Should -Be $true
            $latest = Get-Content "$MockRepo\latest" -Raw | ForEach-Object Trim
            $latest | Should -Be "v1.9.1"
        }
    }

    Context "Get-GitHubRelease with Mock Data" {
        BeforeAll {
            # Create mock repository
            $script:MockRepo = New-MockReleaseRepository -Releases @(
                @{
                    Tag = "v1.9.0"
                    Apps = @{git="2.40.0"; node="18.0.0"}
                }
            ) -OutputPath (Join-Path $TestRoot "releases-api")

            # Set environment variable for mocking
            $env:GITHUB_MOCK_PATH = $MockRepo
        }

        AfterAll {
            Remove-Item env:GITHUB_MOCK_PATH -ErrorAction SilentlyContinue
        }

        It "Should fetch release from mock data" {
            $release = & "$PSScriptRoot\..\..\lib\Get-GitHubRelease.ps1" `
                -Repo "ETML-INF/standard-toolset" `
                -Tag "v1.9.0"

            $release.tag_name | Should -Be "v1.9.0"
            $release.assets.Count | Should -BeGreaterThan 0
        }

        It "Should fetch latest release from mock data" {
            $release = & "$PSScriptRoot\..\..\lib\Get-GitHubRelease.ps1" `
                -Repo "ETML-INF/standard-toolset" `
                -Tag "latest"

            $release.tag_name | Should -Be "v1.9.0"
        }

        It "Should list all releases" {
            $releases = & "$PSScriptRoot\..\..\lib\Get-GitHubRelease.ps1" `
                -Repo "ETML-INF/standard-toolset" `
                -ListReleases

            $releases.Count | Should -Be 1
            $releases[0].tag_name | Should -Be "v1.9.0"
        }

        It "Should download asset from mock data" {
            $outputFile = Join-Path $TestRoot "downloaded-versions.txt"

            & "$PSScriptRoot\..\..\lib\Get-GitHubRelease.ps1" `
                -Repo "ETML-INF/standard-toolset" `
                -Tag "v1.9.0" `
                -AssetName "versions.txt" `
                -OutputPath $outputFile

            Test-Path $outputFile | Should -Be $true
            $content = Get-Content $outputFile
            $content | Should -Contain "git 2.40.0"
        }
    }

    Context "Multiple Releases with Delta Chain" {
        BeforeAll {
            $script:MockRepo = New-MockReleaseRepository -Releases @(
                @{Tag = "v1.8.0"; Apps = @{git="2.39.0"; node="16.0.0"}},
                @{Tag = "v1.9.0"; Apps = @{git="2.40.0"; node="18.0.0"}; Delta = $true},
                @{Tag = "v1.9.1"; Apps = @{git="2.40.0"; node="20.0.0"}; Delta = $true}
            ) -OutputPath (Join-Path $TestRoot "releases-chain")

            $env:GITHUB_MOCK_PATH = $MockRepo
        }

        AfterAll {
            Remove-Item env:GITHUB_MOCK_PATH -ErrorAction SilentlyContinue
        }

        It "Should create delta chain correctly" {
            Test-Path "$MockRepo\v1.9.0\delta-from-v1.8.0.zip" | Should -Be $true
            Test-Path "$MockRepo\v1.9.1\delta-from-v1.9.0.zip" | Should -Be $true
        }

        It "Should list all releases in chain" {
            $releases = & "$PSScriptRoot\..\..\lib\Get-GitHubRelease.ps1" `
                -Repo "ETML-INF/standard-toolset" `
                -ListReleases

            $releases.Count | Should -Be 3
            $releases[0].tag_name | Should -Be "v1.9.1"  # Sorted descending
            $releases[1].tag_name | Should -Be "v1.9.0"
            $releases[2].tag_name | Should -Be "v1.8.0"
        }
    }
}
