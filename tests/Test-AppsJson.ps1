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

.PARAMETER AllowLocalPack
    Also allow private-apps.json-only fields such as localPack and zipMd5.

.OUTPUTS
    None.  Writes results to the host and exits with 0 (pass) or 1 (fail).
#>
param(
    [string]$Path = (Join-Path $PSScriptRoot "..\apps.json"),
    [switch]$AllowLocalPack
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$resolved = Resolve-Path $Path -ErrorAction SilentlyContinue
$jsonName = Split-Path $Path -Leaf
if (-not $resolved) {
    Write-Error "$jsonName not found at: $Path"
    exit 1
}
$Path = $resolved.ProviderPath

# ── JSON syntax check ────────────────────────────────────────────────────────
$raw = Get-Content -Raw $Path
if (-not ($raw | Test-Json)) {
    Write-Error "$jsonName is not valid JSON: $Path"
    exit 1
}
$apps = $raw | ConvertFrom-Json

# ── Schema check ─────────────────────────────────────────────────────────────
$allowed = @('name', 'bucket', 'version', 'tags', 'paths2DropToEnableMultiUser', 'integrityExcludePaths', 'patchBuildPaths', 'shortcuts', 'exeToCheck', 'uninstallSearch')
if ($AllowLocalPack) {
    $allowed += @('localPack', 'zipMd5')
}
$errors  = [System.Collections.Generic.List[string]]::new()

foreach ($app in $apps) {
    $properties = @($app.PSObject.Properties.Name)
    $nonCommentProperties = @($properties | Where-Object { $_ -notlike '//*' })
    if ($nonCommentProperties.Count -eq 0) {
        continue
    }
    if (-not $app.PSObject.Properties['name'] -or -not $app.name) {
        $errors.Add("Entry missing required 'name' field: $($app | ConvertTo-Json -Compress)")
        continue
    }
    foreach ($prop in $properties) {
        if ($prop -like '//*') { continue }
        if ($prop -notin $allowed) {
            $errors.Add("'$($app.name)': unknown field '$prop' (allowed: $($allowed -join ', '))")
        }
    }
}

if ($errors.Count -gt 0) {
    foreach ($e in $errors) { Write-Error $e }
    exit 1
}

Write-Host ("{0}: {1} entries OK" -f $jsonName, $apps.Count) -ForegroundColor Green
exit 0
