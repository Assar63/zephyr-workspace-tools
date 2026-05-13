<#
.SYNOPSIS
    Pull updates into an existing Zephyr workspace bootstrapped by
    new-workspace.ps1.

.DESCRIPTION
    Steps, in order:
      1. git pull --ff-only the zephyr-bootstrap tools repo.
      2. Re-copy activate.ps1 + tools\ from the tools repo into the
         workspace (Windows uses copies, not symlinks, so this is what
         actually picks up tool updates).
      3. git pull --ff-only the app repo inside the workspace.
      4. west update (refresh zephyr + modules to manifest pins).
      5. Re-install zephyr\scripts\requirements.txt (picks up new deps).
      6. Upgrade west and pre-commit (standalone tools).
      7. Re-run `pre-commit install` if the app ships
         .pre-commit-config.yaml.

.PARAMETER WorkspaceDir
    The workspace to update. Defaults to the current directory.

.EXAMPLE
    .\update-workspace.ps1
.EXAMPLE
    .\update-workspace.ps1 C:\dev\rv_display-workspace
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$WorkspaceDir = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if (-not (Test-Path (Join-Path $WorkspaceDir '.west'))) {
    throw "Not a Zephyr workspace (no .west\ found): $WorkspaceDir"
}

Set-Location $WorkspaceDir
$WorkspaceDir = (Get-Location).Path

if (-not (Test-Path '.venv')) {
    throw "Workspace has no .venv\ -- can't update without it."
}

function Log([string]$msg) { Write-Host "==> $msg" }

. .\.venv\Scripts\Activate.ps1

$UseUv = [bool](Get-Command uv -ErrorAction SilentlyContinue)

function Install-Pkg {
    param([Parameter(ValueFromRemainingArguments)][string[]]$PkgArgs)
    if ($UseUv) { & uv pip install --quiet @PkgArgs }
    else        { & pip install --quiet @PkgArgs }
    if ($LASTEXITCODE -ne 0) { throw "pip install failed" }
}

$AppDir = (& west config manifest.path).Trim()

$ToolsRepoDir = if ($env:TOOLS_REPO_DIR) {
    $env:TOOLS_REPO_DIR
} else {
    Join-Path $env:USERPROFILE 'projects\zephyr-bootstrap'
}

if (Test-Path (Join-Path $ToolsRepoDir '.git')) {
    Log "Pulling tools repo: $ToolsRepoDir"
    Push-Location $ToolsRepoDir
    try { & git pull --ff-only } finally { Pop-Location }

    # Windows uses copies (not symlinks), so explicitly refresh.
    Log "Refreshing activate.ps1 + tools\ from tools repo"
    Copy-Item (Join-Path $ToolsRepoDir 'activate.ps1') -Destination 'activate.ps1' -Force
    if (Test-Path 'tools') { Remove-Item 'tools' -Recurse -Force }
    Copy-Item (Join-Path $ToolsRepoDir 'tools') -Destination 'tools' -Recurse
} else {
    Write-Warning "Tools repo not found at $ToolsRepoDir; skipping its pull"
}

if (Test-Path (Join-Path $AppDir '.git')) {
    Log "Pulling app repo: $AppDir"
    Push-Location $AppDir
    try { & git pull --ff-only } finally { Pop-Location }
}

Log 'west update'
& west update

Log 'Refreshing Zephyr Python deps'
Install-Pkg -r zephyr/scripts/requirements.txt

Log 'Upgrading west and pre-commit'
Install-Pkg --upgrade west pre-commit

$preCommitCfg = Join-Path $AppDir '.pre-commit-config.yaml'
if (Test-Path $preCommitCfg) {
    Log 'Re-installing pre-commit hooks'
    Push-Location $AppDir
    try { & pre-commit install } finally { Pop-Location }
}

Write-Host ''
Write-Host "Update complete in $WorkspaceDir."
