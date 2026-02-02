BeforeAll {
    # Setup test workspace
    $script:TestRoot = Join-Path $env:TEMP "compare-versions-tests-$PID"
    New-Item -ItemType Directory $TestRoot -Force | Out-Null

    Write-Host "Test workspace: $script:TestRoot" -ForegroundColor Cyan
}

AfterAll {
    # Cleanup
    if (Test-Path $script:TestRoot) {
        Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Version Comparison" {
    Context "Single App Update" {
        BeforeEach {
            $script:PrevFile = Join-Path $TestRoot "prev-$([guid]::NewGuid().ToString().Substring(0,8)).txt"
            $script:CurrFile = Join-Path $TestRoot "curr-$([guid]::NewGuid().ToString().Substring(0,8)).txt"

            @"
Name Version
---- -------
git 2.40.0
node 18.0.0
python 3.11.0
"@ | Out-File $PrevFile

            @"
Name Version
---- -------
git 2.40.0
node 20.0.0
python 3.11.0
"@ | Out-File $CurrFile
        }

        AfterEach {
            if (Test-Path $PrevFile) { Remove-Item $PrevFile -Force }
            if (Test-Path $CurrFile) { Remove-Item $CurrFile -Force }
        }

        It "Should detect single updated app" {
            $result = & "$PSScriptRoot\..\..\lib\Compare-Versions.ps1" `
                -PreviousVersionsFile $PrevFile `
                -CurrentVersionsFile $CurrFile

            $result.UpdatedApps.Count | Should -Be 1
            $result.UpdatedApps[0].Name | Should -Be "node"
            $result.UpdatedApps[0].OldVersion | Should -Be "18.0.0"
            $result.UpdatedApps[0].NewVersion | Should -Be "20.0.0"

            $result.NewApps.Count | Should -Be 0
            $result.RemovedApps.Count | Should -Be 0
            $result.UnchangedApps.Count | Should -Be 2
            $result.TotalChanges | Should -Be 1
        }
    }

    Context "New App Addition" {
        BeforeEach {
            $script:PrevFile = Join-Path $TestRoot "prev-$([guid]::NewGuid().ToString().Substring(0,8)).txt"
            $script:CurrFile = Join-Path $TestRoot "curr-$([guid]::NewGuid().ToString().Substring(0,8)).txt"

            @"
Name Version
---- -------
git 2.40.0
node 18.0.0
"@ | Out-File $PrevFile

            @"
Name Version
---- -------
git 2.40.0
node 18.0.0
python 3.11.0
"@ | Out-File $CurrFile
        }

        AfterEach {
            if (Test-Path $PrevFile) { Remove-Item $PrevFile -Force }
            if (Test-Path $CurrFile) { Remove-Item $CurrFile -Force }
        }

        It "Should detect new app" {
            $result = & "$PSScriptRoot\..\..\lib\Compare-Versions.ps1" `
                -PreviousVersionsFile $PrevFile `
                -CurrentVersionsFile $CurrFile

            $result.NewApps.Count | Should -Be 1
            $result.NewApps | Should -Contain "python"

            $result.UpdatedApps.Count | Should -Be 0
            $result.RemovedApps.Count | Should -Be 0
            $result.TotalChanges | Should -Be 1
        }
    }

    Context "App Removal" {
        BeforeEach {
            $script:PrevFile = Join-Path $TestRoot "prev-$([guid]::NewGuid().ToString().Substring(0,8)).txt"
            $script:CurrFile = Join-Path $TestRoot "curr-$([guid]::NewGuid().ToString().Substring(0,8)).txt"

            @"
Name Version
---- -------
git 2.40.0
node 18.0.0
python 3.11.0
"@ | Out-File $PrevFile

            @"
Name Version
---- -------
git 2.40.0
node 18.0.0
"@ | Out-File $CurrFile
        }

        AfterEach {
            if (Test-Path $PrevFile) { Remove-Item $PrevFile -Force }
            if (Test-Path $CurrFile) { Remove-Item $CurrFile -Force }
        }

        It "Should detect removed app" {
            $result = & "$PSScriptRoot\..\..\lib\Compare-Versions.ps1" `
                -PreviousVersionsFile $PrevFile `
                -CurrentVersionsFile $CurrFile

            $result.RemovedApps.Count | Should -Be 1
            $result.RemovedApps | Should -Contain "python"

            $result.NewApps.Count | Should -Be 0
            $result.UpdatedApps.Count | Should -Be 0
            $result.TotalChanges | Should -Be 1
        }
    }

    Context "Multiple Changes" {
        BeforeEach {
            $script:PrevFile = Join-Path $TestRoot "prev-$([guid]::NewGuid().ToString().Substring(0,8)).txt"
            $script:CurrFile = Join-Path $TestRoot "curr-$([guid]::NewGuid().ToString().Substring(0,8)).txt"

            @"
Name Version
---- -------
git 2.40.0
node 18.0.0
rclone 1.60.0
"@ | Out-File $PrevFile

            @"
Name Version
---- -------
git 2.41.0
node 20.0.0
python 3.11.0
"@ | Out-File $CurrFile
        }

        AfterEach {
            if (Test-Path $PrevFile) { Remove-Item $PrevFile -Force }
            if (Test-Path $CurrFile) { Remove-Item $CurrFile -Force }
        }

        It "Should detect all types of changes" {
            $result = & "$PSScriptRoot\..\..\lib\Compare-Versions.ps1" `
                -PreviousVersionsFile $PrevFile `
                -CurrentVersionsFile $CurrFile

            # 2 updated (git, node)
            $result.UpdatedApps.Count | Should -Be 2

            # 1 new (python)
            $result.NewApps.Count | Should -Be 1
            $result.NewApps | Should -Contain "python"

            # 1 removed (rclone)
            $result.RemovedApps.Count | Should -Be 1
            $result.RemovedApps | Should -Contain "rclone"

            # Total changes: 2 updates + 1 new + 1 removed = 4
            $result.TotalChanges | Should -Be 4
        }
    }

    Context "No Changes" {
        BeforeEach {
            $script:PrevFile = Join-Path $TestRoot "prev-$([guid]::NewGuid().ToString().Substring(0,8)).txt"
            $script:CurrFile = Join-Path $TestRoot "curr-$([guid]::NewGuid().ToString().Substring(0,8)).txt"

            $content = @"
Name Version
---- -------
git 2.40.0
node 18.0.0
"@
            $content | Out-File $PrevFile
            $content | Out-File $CurrFile
        }

        AfterEach {
            if (Test-Path $PrevFile) { Remove-Item $PrevFile -Force }
            if (Test-Path $CurrFile) { Remove-Item $CurrFile -Force }
        }

        It "Should detect no changes" {
            $result = & "$PSScriptRoot\..\..\lib\Compare-Versions.ps1" `
                -PreviousVersionsFile $PrevFile `
                -CurrentVersionsFile $CurrFile

            $result.NewApps.Count | Should -Be 0
            $result.UpdatedApps.Count | Should -Be 0
            $result.RemovedApps.Count | Should -Be 0
            $result.UnchangedApps.Count | Should -Be 2
            $result.TotalChanges | Should -Be 0
        }
    }

    Context "Format Variations" {
        BeforeEach {
            $script:PrevFile = Join-Path $TestRoot "prev-$([guid]::NewGuid().ToString().Substring(0,8)).txt"
            $script:CurrFile = Join-Path $TestRoot "curr-$([guid]::NewGuid().ToString().Substring(0,8)).txt"

            # Previous with extra whitespace
            @"
  git   2.40.0
node 18.0.0
"@ | Out-File $PrevFile

            # Current without header
            @"
git 2.40.0
node 20.0.0
"@ | Out-File $CurrFile
        }

        AfterEach {
            if (Test-Path $PrevFile) { Remove-Item $PrevFile -Force }
            if (Test-Path $CurrFile) { Remove-Item $CurrFile -Force }
        }

        It "Should handle whitespace variations" {
            $result = & "$PSScriptRoot\..\..\lib\Compare-Versions.ps1" `
                -PreviousVersionsFile $PrevFile `
                -CurrentVersionsFile $CurrFile

            $result.UpdatedApps.Count | Should -Be 1
            $result.UpdatedApps[0].Name | Should -Be "node"
        }
    }
}
