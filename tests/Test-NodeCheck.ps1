<#
.SYNOPSIS
    Local tests for Invoke-NodeCheck -- no Docker required.

.DESCRIPTION
    Verifies that Invoke-NodeCheck detects node.exe instances outside the
    toolset directory even when the toolset's own node is first in PATH.

    Extracts Invoke-NodeCheck from toolset.ps1 via the PowerShell AST so the
    test always exercises the current production code.

    Runs in a subprocess per assertion group to isolate PATH manipulation.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot     = Split-Path $PSScriptRoot -Parent
$toolsetScript = Join-Path $repoRoot "toolset.ps1"

. (Join-Path $PSScriptRoot "Test-Helpers.ps1")

# ── Extract Invoke-NodeCheck from toolset.ps1 via AST ────────────────────────
$parseTokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $toolsetScript, [ref]$parseTokens, [ref]$parseErrors)

if ($parseErrors.Count -gt 0) {
    Write-Host "  FAIL: Could not parse toolset.ps1: $($parseErrors[0])" -ForegroundColor Red
    exit 1
}

$funcAst = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Invoke-NodeCheck'
}, $false) | Select-Object -First 1

if (-not $funcAst) {
    Write-Host "  FAIL: Invoke-NodeCheck not found in toolset.ps1" -ForegroundColor Red
    exit 1
}

$funcSource = $funcAst.Extent.Text

# ── Helper: run Invoke-NodeCheck in isolated subprocess ───────────────────────
# Writes the function to a temp file and dot-sources it from a second temp
# script, so that $ signs in the function body are never expanded here.
function Invoke-NodeCheckTest {
    param(
        [string]$ToolsetDir,
        [string]$TestPath
    )

    $funcFile  = [System.IO.Path]::ChangeExtension(
                     [System.IO.Path]::GetTempFileName(), ".ps1")
    $mainScript = [System.IO.Path]::ChangeExtension(
                     [System.IO.Path]::GetTempFileName(), ".ps1")

    # Save raw function source -- no variable expansion here.
    Set-Content $funcFile $funcSource -Encoding UTF8

    $esc      = $ToolsetDir.Replace("'", "''")
    $escPath  = $TestPath.Replace("'", "''")
    $escFunc  = $funcFile.Replace("'", "''")

    $scriptContent = @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Continue'
. '$escFunc'
`$env:PATH    = '$escPath'
`$env:PATHEXT = '.COM;.EXE;.BAT;.CMD'
`$captured = @(Invoke-NodeCheck -toolsetdir '$esc' -NoInteraction `$true 3>&1)
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

# ── Setup temp dirs ───────────────────────────────────────────────────────────
$tmp        = [System.IO.Path]::GetTempPath()
$uid        = [guid]::NewGuid().ToString('N').Substring(0, 8)
$fakeToolset = Join-Path $tmp "nc-toolset-$uid"
$fakeAdmin   = Join-Path $tmp "nc-admin-$uid"
$fakeShims   = Join-Path $fakeToolset "shims"

try {
    New-Item -Force -ItemType Directory $fakeShims | Out-Null
    New-Item -Force -ItemType Directory $fakeAdmin | Out-Null
    # Minimal .cmd stubs -- just need to exist for Get-Command node -All to find them.
    Set-Content (Join-Path $fakeShims "node.cmd") "@echo off" -Encoding ASCII
    Set-Content (Join-Path $fakeAdmin "node.cmd") "@echo off" -Encoding ASCII

    # ── [NC-1] Conflict: admin node present alongside toolset node ────────────
    Write-Host "[NC-1] Conflict detection: admin node alongside toolset node"
    $out1 = Invoke-NodeCheckTest -ToolsetDir $fakeToolset `
                                  -TestPath "$fakeShims;$fakeAdmin"
    Assert "NC-1: warning emitted for conflicting node" ($out1 -match "WARNING_DETECTED")
    Assert "NC-1: warning references admin path"        ($out1 -match [regex]::Escape($fakeAdmin))

    # ── [NC-2] Clean: only toolset node in PATH ───────────────────────────────
    Write-Host "[NC-2] No conflict: only toolset node present"
    $out2 = Invoke-NodeCheckTest -ToolsetDir $fakeToolset `
                                  -TestPath $fakeShims
    Assert "NC-2: no warning when only toolset node" (-not ($out2 -match "WARNING_DETECTED"))

} finally {
    if (Test-Path $fakeToolset) {
        Remove-Item $fakeToolset -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $fakeAdmin) {
        Remove-Item $fakeAdmin -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
if ($script:fail -gt 0) {
    Write-Host "$($script:fail) test(s) FAILED." -ForegroundColor Red
    if ($script:failedAssertions.Count -gt 0) {
        Write-Host "Failed: $($script:failedAssertions -join ', ')" -ForegroundColor Red
    }
    exit 1
}
Write-Host "All NodeCheck tests passed ($($script:pass) assertion(s))." -ForegroundColor Green
exit 0
