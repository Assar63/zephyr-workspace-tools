<#
.SYNOPSIS
    Copy ide-defaults/<ide>-init.{sh,ps1} into a project's
    scripts\ide-setup\ as a starting point for customization.

.DESCRIPTION
    After seeding, the bootstrap (new-workspace.ps1 -Ide <ide>) will run
    the project's seeded copy instead of the in-repo defaults, and you
    can customize the seeded files freely.

    Existing files in the target are never overwritten.

.PARAMETER AppDir
    Path to the Zephyr application repo to seed into. Files land at
    <AppDir>\scripts\ide-setup\.

.PARAMETER Ide
    'vscode', 'clion', or 'both' (default).

.EXAMPLE
    .\seed-ide-templates.ps1 C:\dev\foo-workspace\foo
.EXAMPLE
    .\seed-ide-templates.ps1 C:\dev\foo-workspace\foo -Ide vscode
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$AppDir,
    [ValidateSet('vscode', 'clion', 'both')][string]$Ide = 'both'
)

$ErrorActionPreference = 'Stop'

$Defaults = Join-Path $PSScriptRoot 'ide-defaults'
$Target = Join-Path $AppDir 'scripts\ide-setup'

New-Item -ItemType Directory -Force -Path $Target | Out-Null

function Copy-IfAbsent {
    param([string]$Src, [string]$Dst)
    if (Test-Path $Dst) {
        Write-Host "  $Dst exists; leaving alone"
    } else {
        $dstDir = Split-Path -Parent $Dst
        if (-not (Test-Path $dstDir)) {
            New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
        }
        Copy-Item $Src -Destination $Dst
        Write-Host "  seeded: $Dst"
    }
}

function Seed-VSCode {
    Copy-IfAbsent (Join-Path $Defaults 'vscode-init.sh')  (Join-Path $Target 'vscode-init.sh')
    Copy-IfAbsent (Join-Path $Defaults 'vscode-init.ps1') (Join-Path $Target 'vscode-init.ps1')
}

function Seed-CLion {
    Copy-IfAbsent (Join-Path $Defaults 'clion-init.sh')  (Join-Path $Target 'clion-init.sh')
    Copy-IfAbsent (Join-Path $Defaults 'clion-init.ps1') (Join-Path $Target 'clion-init.ps1')
    # clion-init reads XML data relative to its own location, so the
    # data dir must travel with the script.
    $xmlSrc = Join-Path $Defaults 'clion\runConfigurations'
    $xmlDst = Join-Path $Target 'clion\runConfigurations'
    Get-ChildItem -Path $xmlSrc -Filter '*.xml' | ForEach-Object {
        Copy-IfAbsent $_.FullName (Join-Path $xmlDst $_.Name)
    }
}

switch ($Ide) {
    'vscode' { Seed-VSCode }
    'clion'  { Seed-CLion }
    'both'   { Seed-VSCode; Seed-CLion }
}

Write-Host ""
Write-Host "Done. Edit the seeded files under $Target\ to customize."
