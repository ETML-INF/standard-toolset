BeforeAll {
    # Import helpers
    . "$PSScriptRoot\..\helpers\New-MockRelease.ps1"

    # Setup test workspace
    $script:TestRoot = Join-Path $env:TEMP "delta-gen-tests-$PID"
    New-Item -ItemType Directory $TestRoot -Force | Out-Null

    Write-Host "Test workspace: $script:TestRoot" -ForegroundColor Cyan
}

AfterAll {
    # Cleanup
    if (Test-Path $script:TestRoot) {
        Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Delta Package Generation" {
    Context "Single App Update" {
        BeforeEach {
            $script:BuildPath = Join-Path $TestRoot "build-single-$([guid]::NewGuid().ToString().Substring(0,8))"
            $script:OutputPath = Join-Path $TestRoot "output-single-$([guid]::NewGuid().ToString().Substring(0,8))"

            # Create mock build directory
            New-Item -ItemType Directory "$BuildPath\scoop\apps\git\2.40.0" -Force | Out-Null
            New-Item -ItemType Directory "$BuildPath\scoop\apps\node\20.0.0" -Force | Out-Null  # Updated
            New-Item -ItemType Directory "$BuildPath\scoop\apps\python\3.11.0" -Force | Out-Null
            New-Item -ItemType Directory "$BuildPath\scoop\shims" -Force | Out-Null

            "mock git" | Out-File "$BuildPath\scoop\apps\git\2.40.0\git.exe"
            "mock node" | Out-File "$BuildPath\scoop\apps\node\20.0.0\node.exe"
            "mock python" | Out-File "$BuildPath\scoop\apps\python\3.11.0\python.exe"

            # Current versions
            $currentVersions = @"
Name Version
---- -------
git 2.40.0
node 20.0.0
python 3.11.0
"@
            $currentVersions | Out-File "$BuildPath\versions.txt"

            # Previous versions
            $prevVersions = @"
Name Version
---- -------
git 2.40.0
node 18.0.0
python 3.11.0
"@
            $script:PrevVersionsFile = Join-Path $TestRoot "prev-versions-$([guid]::NewGuid().ToString().Substring(0,8)).txt"
            $prevVersions | Out-File $PrevVersionsFile

            "v1.9.1" | Out-File "$BuildPath\VERSION.txt"

            # Change to test root for delta output
            Push-Location $OutputPath
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        AfterEach {
            Pop-Location
            if (Test-Path $BuildPath) {
                Remove-Item $BuildPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $OutputPath) {
                Remove-Item $OutputPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should detect single changed app" {
            $result = & "$PSScriptRoot\..\..\lib\Generate-DeltaPackage.ps1" `
                -BuildPath $BuildPath `
                -CurrentTag "v1.9.1" `
                -PreviousTag "v1.9.0" `
                -PreviousVersionsFile $PrevVersionsFile `
                -OutputPath "$OutputPath\delta"

            $result.Created | Should -Be $true
            $result.ChangedApps | Should -Contain "node"
            $result.ChangedApps.Count | Should -Be 1
        }

        It "Should create delta with only changed app" {
            & "$PSScriptRoot\..\..\lib\Generate-DeltaPackage.ps1" `
                -BuildPath $BuildPath `
                -CurrentTag "v1.9.1" `
                -PreviousTag "v1.9.0" `
                -PreviousVersionsFile $PrevVersionsFile `
                -OutputPath "$OutputPath\delta"

            Test-Path "$OutputPath\delta\scoop\apps\node" | Should -Be $true
            Test-Path "$OutputPath\delta\scoop\apps\git" | Should -Be $false
            Test-Path "$OutputPath\delta\scoop\apps\python" | Should -Be $false
        }

        It "Should generate valid DELTA-MANIFEST.json" {
            & "$PSScriptRoot\..\..\lib\Generate-DeltaPackage.ps1" `
                -BuildPath $BuildPath `
                -CurrentTag "v1.9.1" `
                -PreviousTag "v1.9.0" `
                -PreviousVersionsFile $PrevVersionsFile `
                -OutputPath "$OutputPath\delta"

            $manifestPath = "$OutputPath\delta\DELTA-MANIFEST.json"
            Test-Path $manifestPath | Should -Be $true

            $manifest = Get-Content $manifestPath | ConvertFrom-Json
            $manifest.from_version | Should -Be "v1.9.0"
            $manifest.to_version | Should -Be "v1.9.1"
            $manifest.changed_apps | Should -Contain "node"
            $manifest.type | Should -Be "delta"
            $manifest.app_count | Should -Be 1
        }

        It "Should create compressed delta package" {
            $result = & "$PSScriptRoot\..\..\lib\Generate-DeltaPackage.ps1" `
                -BuildPath $BuildPath `
                -CurrentTag "v1.9.1" `
                -PreviousTag "v1.9.0" `
                -PreviousVersionsFile $PrevVersionsFile `
                -OutputPath "$OutputPath\delta"

            $deltaFile = "$OutputPath\delta-from-v1.9.0.zip"
            Test-Path $deltaFile | Should -Be $true
            (Get-Item $deltaFile).Length | Should -BeGreaterThan 0
        }
    }

    Context "New App Addition" {
        BeforeEach {
            $script:BuildPath = Join-Path $TestRoot "build-new-$([guid]::NewGuid().ToString().Substring(0,8))"
            $script:OutputPath = Join-Path $TestRoot "output-new-$([guid]::NewGuid().ToString().Substring(0,8))"

            # Create build with new app
            New-Item -ItemType Directory "$BuildPath\scoop\apps\git\2.40.0" -Force | Out-Null
            New-Item -ItemType Directory "$BuildPath\scoop\apps\node\18.0.0" -Force | Out-Null
            New-Item -ItemType Directory "$BuildPath\scoop\apps\python\3.11.0" -Force | Out-Null  # NEW
            New-Item -ItemType Directory "$BuildPath\scoop\shims" -Force | Out-Null

            # Current versions (with new app)
            @"
Name Version
---- -------
git 2.40.0
node 18.0.0
python 3.11.0
"@ | Out-File "$BuildPath\versions.txt"

            # Previous versions (without python)
            $script:PrevVersionsFile = Join-Path $TestRoot "prev-versions-$([guid]::NewGuid().ToString().Substring(0,8)).txt"
            @"
Name Version
---- -------
git 2.40.0
node 18.0.0
"@ | Out-File $PrevVersionsFile

            "v1.9.1" | Out-File "$BuildPath\VERSION.txt"

            Push-Location $OutputPath
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        AfterEach {
            Pop-Location
            if (Test-Path $BuildPath) {
                Remove-Item $BuildPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $OutputPath) {
                Remove-Item $OutputPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should include new app in delta" {
            $result = & "$PSScriptRoot\..\..\lib\Generate-DeltaPackage.ps1" `
                -BuildPath $BuildPath `
                -CurrentTag "v1.9.1" `
                -PreviousTag "v1.9.0" `
                -PreviousVersionsFile $PrevVersionsFile `
                -OutputPath "$OutputPath\delta"

            $result.Created | Should -Be $true
            $result.ChangedApps | Should -Contain "python"
            Test-Path "$OutputPath\delta\scoop\apps\python" | Should -Be $true
        }
    }

    Context "No Changes" {
        BeforeEach {
            $script:BuildPath = Join-Path $TestRoot "build-nochange-$([guid]::NewGuid().ToString().Substring(0,8))"
            $script:OutputPath = Join-Path $TestRoot "output-nochange-$([guid]::NewGuid().ToString().Substring(0,8))"

            New-Item -ItemType Directory "$BuildPath\scoop\apps\git\2.40.0" -Force | Out-Null
            New-Item -ItemType Directory "$BuildPath\scoop\shims" -Force | Out-Null

            # Identical versions
            $versions = @"
Name Version
---- -------
git 2.40.0
"@
            $versions | Out-File "$BuildPath\versions.txt"

            $script:PrevVersionsFile = Join-Path $TestRoot "prev-versions-$([guid]::NewGuid().ToString().Substring(0,8)).txt"
            $versions | Out-File $PrevVersionsFile

            "v1.9.1" | Out-File "$BuildPath\VERSION.txt"

            Push-Location $OutputPath
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        AfterEach {
            Pop-Location
            if (Test-Path $BuildPath) {
                Remove-Item $BuildPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $OutputPath) {
                Remove-Item $OutputPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should skip delta generation when no changes" {
            $result = & "$PSScriptRoot\..\..\lib\Generate-DeltaPackage.ps1" `
                -BuildPath $BuildPath `
                -CurrentTag "v1.9.1" `
                -PreviousTag "v1.9.0" `
                -PreviousVersionsFile $PrevVersionsFile `
                -OutputPath "$OutputPath\delta"

            $result.Created | Should -Be $false
            $result.Reason | Should -BeLike "*No changes*"
        }
    }

    Context "Multiple App Updates" {
        BeforeEach {
            $script:BuildPath = Join-Path $TestRoot "build-multi-$([guid]::NewGuid().ToString().Substring(0,8))"
            $script:OutputPath = Join-Path $TestRoot "output-multi-$([guid]::NewGuid().ToString().Substring(0,8))"

            # Create build with multiple updated apps
            New-Item -ItemType Directory "$BuildPath\scoop\apps\git\2.41.0" -Force | Out-Null  # Updated
            New-Item -ItemType Directory "$BuildPath\scoop\apps\node\20.0.0" -Force | Out-Null  # Updated
            New-Item -ItemType Directory "$BuildPath\scoop\apps\python\3.11.0" -Force | Out-Null  # Unchanged
            New-Item -ItemType Directory "$BuildPath\scoop\shims" -Force | Out-Null

            @"
Name Version
---- -------
git 2.41.0
node 20.0.0
python 3.11.0
"@ | Out-File "$BuildPath\versions.txt"

            $script:PrevVersionsFile = Join-Path $TestRoot "prev-versions-$([guid]::NewGuid().ToString().Substring(0,8)).txt"
            @"
Name Version
---- -------
git 2.40.0
node 18.0.0
python 3.11.0
"@ | Out-File $PrevVersionsFile

            "v1.9.1" | Out-File "$BuildPath\VERSION.txt"

            Push-Location $OutputPath
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }

        AfterEach {
            Pop-Location
            if (Test-Path $BuildPath) {
                Remove-Item $BuildPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $OutputPath) {
                Remove-Item $OutputPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should include all changed apps in delta" {
            $result = & "$PSScriptRoot\..\..\lib\Generate-DeltaPackage.ps1" `
                -BuildPath $BuildPath `
                -CurrentTag "v1.9.1" `
                -PreviousTag "v1.9.0" `
                -PreviousVersionsFile $PrevVersionsFile `
                -OutputPath "$OutputPath\delta"

            $result.Created | Should -Be $true
            $result.ChangedApps | Should -Contain "git"
            $result.ChangedApps | Should -Contain "node"
            $result.ChangedApps.Count | Should -Be 2

            Test-Path "$OutputPath\delta\scoop\apps\git" | Should -Be $true
            Test-Path "$OutputPath\delta\scoop\apps\node" | Should -Be $true
            Test-Path "$OutputPath\delta\scoop\apps\python" | Should -Be $false
        }
    }
}
