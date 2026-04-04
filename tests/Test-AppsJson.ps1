<#
.SYNOPSIS
    Validates the structure and schema of apps.json.

.DESCRIPTION
    Checks that apps.json is valid JSON and that every entry conforms to the
    expected schema: a required 'name' field and only known optional fields.
    Exits 0 on success, 1 on any validation error.

    Intended to be called from CI/CD (validate-and-test action) and locally
    during development.

.PARAMETER Path
    Path to the apps.json file to validate.
    Defaults to apps.json in the repository root (one directory above $PSScriptRoot).

.OUTPUTS
    None.  Writes results to the host and exits with 0 (pass) or 1 (fail).
#>
param(
    [string]$Path = (Join-Path $PSScriptRoot "..\apps.json")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$resolved = Resolve-Path $Path -ErrorAction SilentlyContinue
if (-not $resolved) {
    Write-Error "apps.json not found at: $Path"
    exit 1
}
$Path = $resolved.ProviderPath

# ── JSON syntax check ────────────────────────────────────────────────────────
$raw = Get-Content -Raw $Path
if (-not ($raw | Test-Json)) {
    Write-Error "apps.json is not valid JSON: $Path"
    exit 1
}
$apps = $raw | ConvertFrom-Json

# ── Schema check ─────────────────────────────────────────────────────────────
$allowed = @('name', 'bucket', 'version', 'tags', 'paths2DropToEnableMultiUser', 'integrityExcludePaths', 'patchBuildPaths', 'shortcuts', '//comment')
$errors  = [System.Collections.Generic.List[string]]::new()

foreach ($app in $apps) {
    if (-not $app.name) {
        $errors.Add("Entry missing required 'name' field: $($app | ConvertTo-Json -Compress)")
        continue
    }
    foreach ($prop in $app.PSObject.Properties.Name) {
        if ($prop -notin $allowed) {
            $errors.Add("'$($app.name)': unknown field '$prop' (allowed: $($allowed -join ', '))")
        }
    }
}

if ($errors.Count -gt 0) {
    foreach ($e in $errors) { Write-Error $e }
    exit 1
}

Write-Host "apps.json: $($apps.Count) entries OK" -ForegroundColor Green
exit 0
