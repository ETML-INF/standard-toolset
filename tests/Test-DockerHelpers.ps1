# Shared Docker helpers -- dot-source this file from any script that calls docker.

function Get-DockerArgs {
<#
.SYNOPSIS
    Returns a docker argument prefix for the Windows containers context.
.DESCRIPTION
    On Docker Desktop, targets the 'desktop-windows' context so Windows container
    commands work regardless of the current default mode.
    On CI ($env:CI set), uses the default context (mode already guaranteed by the
    switch-docker-windows workflow step).
    Prints the resolved context to the host and returns an array suitable for
    splatting before any docker sub-command, e.g.:
        docker @(Get-DockerArgs) build ...
#>
    $availableContexts = docker context ls --format "{{.Name}}" 2>$null
    $context = if ($env:CI) {
        $null
    } elseif ($availableContexts -contains "desktop-windows") {
        "desktop-windows"
    } else {
        Write-Warning "'desktop-windows' context not found -- using current default context."
        Write-Warning "If the build fails, make sure Docker Desktop is in Windows containers mode."
        $null
    }
    Write-Host "Docker context : $(if ($context) { $context } else { '(default)' })" -ForegroundColor Cyan
    if ($context) { return @("--context", $context) } else { return @() }
}
