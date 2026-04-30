<#
.SYNOPSIS
    Local tests for Invoke-ExeConflictCheck and Find-UninstallEntry.

.DESCRIPTION
    Verifies that Invoke-ExeConflictCheck detects exe instances outside the
    toolset directory. Tests run in isolated subprocesses with a fake
    Find-UninstallEntry to avoid touching the real registry.

    Extracts both functions from toolset.ps1 via the PowerShell AST so
    the test always exercises the current production code.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot      = Split-Path $PSScriptRoot -Parent
$toolsetScript = Join-Path $repoRoot "toolset.ps1"

. (Join-Path $PSScriptRoot "Test-Helpers.ps1")

# -- Extract functions from toolset.ps1 via AST ------------------------------
$parseTokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $toolsetScript, [ref]$parseTokens, [ref]$parseErrors)

if ($parseErrors.Count -gt 0) {
    Write-Host "  FAIL: Could not parse toolset.ps1: $($parseErrors[0])" -ForegroundColor Red
    exit 1
}

function Get-FunctionSource {
    param([string]$Name)
    $fn = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq $Name
    }, $false) | Select-Object -First 1
    if (-not $fn) {
        Write-Host "  FAIL: $Name not found in toolset.ps1" -ForegroundColor Red
        exit 1
    }
    return $fn.Extent.Text
}

$conflictCheckSrc = Get-FunctionSource 'Invoke-ExeConflictCheck'
$findUninstallSrc = Get-FunctionSource 'Find-UninstallEntry'

# -- Helper: run Invoke-ExeConflictCheck in isolated subprocess ---------------
function Invoke-ConflictCheckTest {
    param(
        [string]$ToolsetDir,
        [string]$TestPath,
        [string]$ExeName,
        [string]$DisplayName,
        [string]$UninstallSearch = '',
        # Controls what the fake Find-UninstallEntry returns.
        # 'none'   = returns $null (not found in registry)
        # 'found'  = returns an object with DisplayName + QuietUninstallString
        [string]$FakeUninstall = 'none'
    )

    $funcFile   = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".ps1")
    $mainScript = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), ".ps1")

    Set-Content $funcFile ($findUninstallSrc + "`n" + $conflictCheckSrc) -Encoding UTF8

    $escToolset = $ToolsetDir.Replace("'", "''")
    $escPath    = $TestPath.Replace("'", "''")
    $escFunc    = $funcFile.Replace("'", "''")
    $escExe     = $ExeName.Replace("'", "''")
    $escDisplay = $DisplayName.Replace("'", "''")
    $escSearch  = $UninstallSearch.Replace("'", "''")

    $fakeBody = if ($FakeUninstall -eq 'found') {
        "return [PSCustomObject]@{ DisplayName = 'FakeApp 1.0'; QuietUninstallString = 'MsiExec.exe /X{FAKE-GUID}' }"
    } else {
        "return `$null"
    }

    $scriptContent = @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Continue'
. '$escFunc'
# Override Find-UninstallEntry with a fake implementation
function Find-UninstallEntry { param([string]`$Pattern); $fakeBody }
`$env:PATH    = '$escPath'
`$env:PATHEXT = '.COM;.EXE;.BAT;.CMD'
`$captured = @(Invoke-ExeConflictCheck -toolsetdir '$escToolset' ``
    -ExeName '$escExe' -DisplayName '$escDisplay' ``
    -UninstallSearch '$escSearch' -NoInteraction `$true 3>&1)
foreach (`$item in `$captured) {
    if (`$item -is [System.Management.Automation.WarningRecord]) {
        Write-Host "WARNING_DETECTED: `$(`$item.Message)"
    }
}
"@
    Set-Content $mainScript $scriptContent -Encoding UTF8

    try {
        $output = pwsh -OutputFormat Text -File $mainScript 2>&1
        return ($output | Out-String)
    } finally {
        Remove-Item $funcFile   -Force -ErrorAction SilentlyContinue
        Remove-Item $mainScript -Force -ErrorAction SilentlyContinue
    }
}

# -- Setup temp dirs ----------------------------------------------------------
$tmp         = [System.IO.Path]::GetTempPath()
$uid         = [guid]::NewGuid().ToString('N').Substring(0, 8)
$fakeToolset = Join-Path $tmp "ec-toolset-$uid"
$fakeAdmin   = Join-Path $tmp "ec-admin-$uid"
$fakeShims   = Join-Path $fakeToolset "shims"

try {
    New-Item -Force -ItemType Directory $fakeShims | Out-Null
    New-Item -Force -ItemType Directory $fakeAdmin | Out-Null
    Set-Content (Join-Path $fakeShims "node.cmd")   "@echo off" -Encoding ASCII
    Set-Content (Join-Path $fakeShims "python.cmd") "@echo off" -Encoding ASCII
    Set-Content (Join-Path $fakeShims "code.cmd")   "@echo off" -Encoding ASCII
    Set-Content (Join-Path $fakeAdmin "node.cmd")   "@echo off" -Encoding ASCII
    Set-Content (Join-Path $fakeAdmin "python.cmd") "@echo off" -Encoding ASCII
    Set-Content (Join-Path $fakeAdmin "code.cmd")   "@echo off" -Encoding ASCII

    # [EC-1] Conflict: node in admin dir alongside toolset node
    Write-Host "[EC-1] Conflict detection: node"
    $out1 = Invoke-ConflictCheckTest -ToolsetDir $fakeToolset `
        -TestPath "$fakeShims;$fakeAdmin" -ExeName "node" -DisplayName "Node.js"
    Assert "EC-1: warning emitted for node conflict" ($out1 -match "WARNING_DETECTED")
    Assert "EC-1: warning references admin path"     ($out1 -match [regex]::Escape($fakeAdmin))

    # [EC-2] Clean: only toolset node
    Write-Host "[EC-2] No conflict: only toolset node"
    $out2 = Invoke-ConflictCheckTest -ToolsetDir $fakeToolset `
        -TestPath $fakeShims -ExeName "node" -DisplayName "Node.js"
    Assert "EC-2: no warning when only toolset node" (-not ($out2 -match "WARNING_DETECTED"))

    # [EC-3] Conflict: python in admin dir
    Write-Host "[EC-3] Conflict detection: python"
    $out3 = Invoke-ConflictCheckTest -ToolsetDir $fakeToolset `
        -TestPath "$fakeShims;$fakeAdmin" -ExeName "python" -DisplayName "Python"
    Assert "EC-3: warning emitted for python conflict" ($out3 -match "WARNING_DETECTED")
    Assert "EC-3: warning references admin path"       ($out3 -match [regex]::Escape($fakeAdmin))

    # [EC-4] Conflict: vscode in admin dir
    Write-Host "[EC-4] Conflict detection: vscode"
    $out4 = Invoke-ConflictCheckTest -ToolsetDir $fakeToolset `
        -TestPath "$fakeShims;$fakeAdmin" -ExeName "code" -DisplayName "VS Code"
    Assert "EC-4: warning emitted for code conflict" ($out4 -match "WARNING_DETECTED")

    # [EC-5] With uninstallSearch + registry entry found: uses Add/Remove info (no winget)
    Write-Host "[EC-5] Uninstall entry found in registry"
    $out5 = Invoke-ConflictCheckTest -ToolsetDir $fakeToolset `
        -TestPath "$fakeShims;$fakeAdmin" -ExeName "node" -DisplayName "Node.js" `
        -UninstallSearch "Node.js*" -FakeUninstall "found"
    Assert "EC-5: shows Add/Remove Programs info" ($out5 -match "FakeApp 1.0")
    Assert "EC-5: does not mention winget"        (-not ($out5 -match "winget"))

    # [EC-6] With uninstallSearch + no registry entry: falls back to winget
    Write-Host "[EC-6] No registry entry - winget fallback"
    $out6 = Invoke-ConflictCheckTest -ToolsetDir $fakeToolset `
        -TestPath "$fakeShims;$fakeAdmin" -ExeName "node" -DisplayName "Node.js" `
        -UninstallSearch "Node.js*" -FakeUninstall "none"
    Assert "EC-6: falls back to winget" ($out6 -match "winget")

    # [EC-7] No uninstallSearch at all: shows manual-only message
    Write-Host "[EC-7] No uninstallSearch - manual message only"
    $out7 = Invoke-ConflictCheckTest -ToolsetDir $fakeToolset `
        -TestPath "$fakeShims;$fakeAdmin" -ExeName "node" -DisplayName "Node.js" `
        -UninstallSearch "" -FakeUninstall "none"
    Assert "EC-7: shows manual removal message" ($out7 -match "Control Panel|manually")
    Assert "EC-7: no winget when no search"     (-not ($out7 -match "winget"))

} finally {
    if (Test-Path $fakeToolset) { Remove-Item $fakeToolset -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $fakeAdmin)   { Remove-Item $fakeAdmin   -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
if ($script:fail -gt 0) {
    Write-Host "$($script:fail) test(s) FAILED." -ForegroundColor Red
    if ($script:failedAssertions.Count -gt 0) {
        Write-Host "Failed: $($script:failedAssertions -join ', ')" -ForegroundColor Red
    }
    exit 1
}
Write-Host "All ExeConflictCheck tests passed ($($script:pass) assertion(s))." -ForegroundColor Green
exit 0
