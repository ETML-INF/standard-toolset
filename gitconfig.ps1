# gitconfig.ps1 — Ensures the shared toolset directory is trusted by git for all users.
#
# Git's safe.directory mechanism blocks operations on repos owned by a different user.
# Since the toolset is installed under a shared path (e.g. D:\data\inf-toolset), each
# user account needs a [safe] directory = <toolsetdir>/* entry in their ~/.gitconfig.
#
# Usage: gitconfig.ps1 <gitconfig-path> <toolset-directory>
#   gitconfig-path     Absolute path to the user's .gitconfig file
#   toolset-directory  Root of the toolset (e.g. D:\data\inf-toolset)
#
# Behaviour:
#   - [safe] missing                → prepend [safe] + directory line
#   - [safe] present, no directory  → insert directory line after [safe]
#   - [safe] present, directory set → replace existing directory line

$path = $args[0]
$toolsetdir = $args[1]

if ([string]::IsNullOrEmpty($path) -or [string]::IsNullOrEmpty($toolsetdir)) {
    Write-Error "Usage: gitconfig.ps1 <gitconfig-path> <toolset-directory>"
    exit 1
}

$add = "`tdirectory = $($toolsetdir -replace '\\', '/')/*"

# @() guarantees an array even for single-line files
$content = @(Get-Content $path)

$safeIndex = ($content | Select-String "^\[safe\]$" | Select-Object -First 1).LineNumber - 1
$dirIndex  = ($content | Select-String "^\s*directory\s*=" | Select-Object -First 1).LineNumber - 1

if ($safeIndex -ge 0) {
    if ($dirIndex -ge 0) {
        # directory line already exists — replace it
        $content[$dirIndex] = $add
    } else {
        # [safe] exists but no directory — insert after [safe]
        $tail = if (($safeIndex + 1) -le ($content.Length - 1)) { $content[($safeIndex+1)..($content.Length-1)] } else { @() }
        $content = $content[0..$safeIndex] + @($add) + $tail
    }
} else {
    # No [safe] section at all — prepend one
    $content = @("[safe]", $add) + $content
}

$content | Set-Content $path -Encoding UTF8
