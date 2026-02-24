---
applyTo: '**/*.ps1,**/*.psm1,**/*.psd1'
description: 'Instructions for writing PowerShell code following PSScriptAnalyzer rules, Pester testing conventions, and project patterns'

---

# PowerShell Development Instructions

Follow idiomatic PowerShell practices, PSScriptAnalyzer rules (configured in `PSScriptAnalyzerSettings.psd1`), and the patterns established in this codebase.

## General Instructions

- Always add `Set-StrictMode -Version Latest` at the top of every script — it catches undefined variables, uninitialized properties, and bad function calls
- Use `$ErrorActionPreference = 'Stop'` in scripts that must fail fast on any error
- Favor clarity over brevity — PowerShell is often read by sysadmins, not just developers
- Write self-documenting code with descriptive parameter and variable names
- Do not use aliases in scripts (`%`, `?`, `gci`, `ls`, etc.) — always use full cmdlet names
- Write comments in English
- Avoid emoji in code and comments

## Function Naming

- **Always use approved Verb-Noun format**: `Get-InstalledVersion`, `New-MockRelease`, `Compare-Versions`, `Generate-DeltaPackage`
- Check approved verbs with `Get-Verb` — PSScriptAnalyzer enforces `PSUseApprovedVerbs`
- **Noun** should describe the object being acted on, using PascalCase: `DeltaPackage`, `MockRelease`, `VersionsFile`
- Helper functions internal to a script use the same convention — do not use private helper naming like `_helper`

## Variable Naming

- **PascalCase** for script-level and parameter variables: `$BuildPath`, `$OutputPath`, `$PreviousTag`
- **camelCase** for local loop/iteration variables: `$appName`, `$currentSize`, `$deltaFile`
- **`$script:` prefix** for file-scoped variables shared across Pester test blocks: `$script:TestRoot`, `$script:MockPath`
- **`$env:` prefix** only for environment variables — never store config in `$global:`
- Avoid single-letter variables except for loop indices (`$i`, `$j`)

## Parameters

Every function must declare parameters explicitly:

```powershell
param(
    [Parameter(Mandatory=$true, HelpMessage="Path to the build directory containing scoop apps")]
    [string]$BuildPath,

    [Parameter(Mandatory=$false, HelpMessage="Output verbosity level")]
    [ValidateSet("Normal", "Detailed", "Diagnostic")]
    [string]$Verbosity = "Normal"
)
```

- Use `[Parameter(Mandatory=$true)]` for required parameters — never rely on interactive prompting
- Always include `HelpMessage` for every parameter
- Use `[ValidateSet(...)]` for parameters with a fixed set of valid values
- Use `[ValidateNotNullOrEmpty()]` for string paths that must be provided
- Declare explicit types: `[string]`, `[bool]`, `[int]`, `[hashtable]`, `[switch]`, `[string[]]`
- Use `[switch]` for boolean flags, not `[bool]` with a default — `[switch]$Force` not `[bool]$Force = $false`

## Comment-Based Help

Every function and every script file must have comment-based help:

```powershell
<#
.SYNOPSIS
    One-line summary of what the function does.

.DESCRIPTION
    Longer description. Explain the algorithm, the expected input format,
    any side effects, and important constraints.

.PARAMETER ParameterName
    What this parameter controls, its expected format, and valid values.

.OUTPUTS
    Describe the return type and structure. For hashtables, list all keys:
    Returns a hashtable with:
    - Created [bool]: Whether a delta package was created
    - DeltaFileName [string]: Name of the generated zip file
    - ChangedApps [string[]]: List of app names that changed
    - Metrics [hashtable]: { DeltaSize, FullSize, SavingsPercent }

.EXAMPLE
    $result = .\lib\Generate-DeltaPackage.ps1 -BuildPath "C:\build" -CurrentTag "v1.10.0"
    if ($result.Created) { Write-Host "Delta: $($result.DeltaFileName)" }
#>
```

## Output and Logging

### Use the right output stream for the right purpose

| Stream | Cmdlet | Use for |
|--------|--------|---------|
| Success | `return` / `Write-Output` | Machine-readable data, pipeline values |
| Display | `Write-Host` | User-facing progress and status (not captured by pipeline) |
| Verbose | `Write-Verbose` | Debug/diagnostic details (shown with `-Verbose`) |
| Warning | `Write-Warning` | Non-fatal issues the user should know about |
| Error | `Write-Error` | Recoverable errors |
| Fatal | `throw` | Unrecoverable errors that must stop execution |

### Color conventions (for `Write-Host`)
- `Cyan` — Section headers, major steps
- `Green` — Success messages
- `Yellow` — Warnings, non-critical notes
- `Red` — Errors, failures
- White/default — Informational text

```powershell
Write-Host "Generating delta package..." -ForegroundColor Cyan
Write-Host "Delta created: $outputFile" -ForegroundColor Green
Write-Host "Warning: delta chain > 3, fallback recommended" -ForegroundColor Yellow
Write-Error "Build path not found: $BuildPath"
```

### Never use `Write-Host` for data that callers will consume
```powershell
# WRONG — caller cannot capture this
Write-Host "Found 3 changed apps"

# CORRECT — return structured data
return @{ ChangedApps = $changedApps; Count = $changedApps.Count }
```

## Error Handling

```powershell
try {
    # Main logic
    $result = Invoke-SomeOperation -Path $Path
}
catch [System.IO.FileNotFoundException] {
    Write-Error "File not found: $Path"
    exit 1
}
catch {
    Write-Error "Unexpected error: $_"
    throw   # Re-throw to preserve stack trace
}
finally {
    # Cleanup that must always run (e.g., temp files)
    if (Test-Path $TempPath) {
        Remove-Item $TempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
```

- Catch specific exception types where possible — avoid bare `catch { }` that swallows all errors
- Use `exit 1` (or `exit 2`, `exit 3` etc.) for fatal script-level failures with distinct codes
- Use `throw` to re-propagate exceptions that callers should handle
- Always clean up temp resources in `finally` or `AfterAll` (Pester)

## File and Path Operations

- Always use `Join-Path` for path construction — never string concatenation:
  ```powershell
  # WRONG
  $file = "$BasePath\apps\$appName"
  # CORRECT
  $file = Join-Path $BasePath "apps" $appName
  ```
- Use `Test-Path` before accessing files/directories
- Use `$PSScriptRoot` to reference paths relative to the current script file
- Use `$env:TEMP` for temp directories in tests and scripts — never hardcode `C:\Temp`
- Prefer `New-Item -ItemType Directory -Force` over manually checking existence before creating

## Returning Structured Data

Functions in `lib/` must return hashtables for structured results — never raw strings for multi-value outputs:

```powershell
# CORRECT — structured, machine-readable
return @{
    Created       = $true
    DeltaFileName = "delta-from-v1.9.0.zip"
    ChangedApps   = @("node", "git")
    Metrics       = @{
        DeltaSize    = 52428800
        FullSize     = 1073741824
        SavingsMB    = 975
        SavingsPercent = 95
    }
}

# WRONG — caller has to parse text
return "Delta created with 2 apps changed"
```

## Mockability Pattern

Any function that calls an external API or accesses a non-local resource must support mock mode via an environment variable:

```powershell
# Check for mock mode first
if ($env:GITHUB_MOCK_PATH) {
    # Use local filesystem mock
    $mockFile = Join-Path $env:GITHUB_MOCK_PATH $Tag "release.json"
    return Get-Content $mockFile | ConvertFrom-Json
}

# Real API call
$response = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag"
return $response
```

Follow this exact pattern from `lib/Get-GitHubRelease.ps1` — the `$env:` variable name should be `<SERVICE>_MOCK_PATH`.

## Testing with Pester 5

### Test file structure

```powershell
Describe "Feature Name" {

    BeforeAll {
        # Create isolated workspace — use PID + GUID for uniqueness
        $script:TestRoot = Join-Path $env:TEMP "standard-toolset-test-$PID"
        New-Item -ItemType Directory $script:TestRoot -Force | Out-Null

        # Dot-source the module under test
        . "$PSScriptRoot\..\..\lib\MyFunction.ps1"
    }

    AfterAll {
        # Always clean up — even on test failure
        if (Test-Path $script:TestRoot) {
            Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Normal operation" {
        It "Should return expected result for valid input" {
            $result = My-Function -InputPath $script:TestRoot
            $result.Created | Should -Be $true
            $result.ChangedApps | Should -Contain "node"
        }
    }

    Context "Edge cases" {
        It "Should handle empty input gracefully" {
            $result = My-Function -InputPath $script:TestRoot
            $result.Created | Should -Be $false
        }
    }
}
```

### Isolation rules

- **Every test suite** gets its own unique temp directory: `Join-Path $env:TEMP "test-$PID"`
- **Every test case** that creates files uses a GUID suffix: `Join-Path $TestRoot "build-$([guid]::NewGuid().ToString().Substring(0,8))"`
- **Never test against real installation paths** (`C:\inf-toolset`, `D:\data\inf-toolset`)
- **Always mock GitHub API** using `$env:GITHUB_MOCK_PATH` — no real network calls in tests
- **Disable activation** steps in tests — test file operations only, not PATH/registry modification

### Test naming

- Use `Describe` for the top-level feature or module name
- Use `Context` for scenario grouping (normal path, edge cases, failure cases)
- Use `It` with a full sentence: `"Should detect single changed app when only one version differs"`

### Assertions

Use Pester's `Should` assertions — never `if (...) { throw }` style in `It` blocks:

```powershell
$result.Count          | Should -Be 3
$result.ChangedApps    | Should -Contain "node"
$result.Created        | Should -BeTrue
$result.DeltaFileName  | Should -Match "^delta-from-v\d+\.\d+\.\d+"
Test-Path $outputFile  | Should -BeTrue
```

## PSScriptAnalyzer Compliance

The project enforces these rules (see `PSScriptAnalyzerSettings.psd1`):

| Rule | What it catches |
|------|----------------|
| `PSUseApprovedVerbs` | Function names with unapproved verbs |
| `PSAvoidUsingCmdletAliases` | `%`, `?`, `gci`, `ls`, etc. in scripts |
| `PSUseDeclaredVarsMoreThanAssignments` | Variables assigned but never read |
| `PSMisleadingBacktick` | Backtick line continuation with trailing spaces |
| `PSReservedCmdletChar` | Reserved characters in function names |
| `PSReservedParams` | Using built-in parameter names incorrectly |

Run locally before pushing:
```powershell
Invoke-ScriptAnalyzer -Path lib -Recurse -Settings PSScriptAnalyzerSettings.psd1
```

Zero errors are acceptable in CI. Warnings should be reviewed and suppressed only with an inline comment explaining why.

## Common Pitfalls to Avoid

- **Not using `Set-StrictMode`** — undefined variables become silent bugs
- **Using aliases** (`%`, `?`, `gci`) — PSScriptAnalyzer will flag these
- **Unapproved verb names** — always check with `Get-Verb` before naming a function
- **Hardcoded drive letters** (`C:\`, `D:\`) — use parameters or `$env:USERPROFILE`
- **Using `Write-Host` for data** — it bypasses the pipeline and cannot be captured
- **Forgetting `| Out-Null`** on operations that produce unwanted output inside test assertions
- **Not cleaning up temp directories** — leaked test artifacts accumulate in `$env:TEMP`
- **Using `$global:` variables** — pass state through parameters or `$script:` within a file
- **String concatenation for paths** — always use `Join-Path`
- **Not handling the mock environment check** in functions that call external services
- **Testing with real GitHub API** — always use `$env:GITHUB_MOCK_PATH` in tests
- **Compress-Archive on directories containing `.git`** — rename `.git` to `.git-force` first (known limitation)
