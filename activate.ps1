# Source this file from the workspace root in PowerShell:
#
#   . .\activate.ps1
#
# Activates the in-tree Python venv and exports ZEPHYR_BASE / SDK so that
# `west`, `cmake --preset`, and clangd all see a consistent environment.

$ErrorActionPreference = 'Stop'

# $PSCommandPath is set when a script is dot-sourced; $MyInvocation.MyCommand.Path
# is the fallback. Either gives us the path to this script.
$ScriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$WorkspaceDir = Split-Path -Parent $ScriptPath

$VenvActivate = Join-Path $WorkspaceDir '.venv\Scripts\Activate.ps1'
if (-not (Test-Path $VenvActivate)) {
    Write-Error "venv not found: $VenvActivate"
    return
}
. $VenvActivate

$env:ZEPHYR_BASE = Join-Path $WorkspaceDir 'zephyr'
if (-not $env:ZEPHYR_SDK_INSTALL_DIR) {
    # Best-effort default; override before sourcing if your SDK lives elsewhere.
    $env:ZEPHYR_SDK_INSTALL_DIR = Join-Path $env:USERPROFILE 'zephyr-sdk-1.0.1'
}

$WsName = Split-Path -Leaf $WorkspaceDir
Write-Host "$WsName workspace ready"
Write-Host "  ZEPHYR_BASE=$env:ZEPHYR_BASE"
Write-Host "  ZEPHYR_SDK_INSTALL_DIR=$env:ZEPHYR_SDK_INSTALL_DIR"
$west = (Get-Command west -ErrorAction SilentlyContinue).Source
$pyocd = (Get-Command pyocd -ErrorAction SilentlyContinue).Source
Write-Host "  west:  $west"
Write-Host "  pyocd: $pyocd"
