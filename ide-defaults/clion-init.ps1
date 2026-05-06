# Default CLion init for Windows / PowerShell users -- used when the
# project doesn't ship its own scripts\ide-setup\clion-init.ps1. Drops
# the standard run configurations into <app>\.idea\runConfigurations\
# if they aren't already present. Existing files are never overwritten.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$WorkspaceDir,
    [Parameter(Mandatory = $true, Position = 1)][string]$AppDir
)

$ErrorActionPreference = 'Stop'

$AppName = Split-Path -Leaf $AppDir
$Src = Join-Path $PSScriptRoot 'clion\runConfigurations'
$Dst = Join-Path $AppDir '.idea\runConfigurations'

New-Item -ItemType Directory -Force -Path $Dst | Out-Null

Get-ChildItem -Path $Src -Filter '*.xml' | ForEach-Object {
    $target = Join-Path $Dst $_.Name
    if (Test-Path $target) {
        Write-Host "  $target already exists; leaving alone"
    } else {
        Copy-Item $_.FullName -Destination $target
        Write-Host "  wrote $target"
    }
}

@"
CLion default setup ready.

  1. Open this folder as the CLion project (NOT the workspace root):
       $AppDir
  2. CMakePresets.json (if shipped by the project) is autodetected --
     pick the configure preset matching your board.
  3. Run configurations (Flash, OpenOCD GDB Server, Serial Monitor)
     loaded from .idea\runConfigurations\. They invoke
     ..\tools\{flash,gdb-server,serial-monitor}.sh which the bootstrap
     placed at the workspace root.
"@ | Write-Host

# Print attachable directories (CLion stores those in workspace.xml,
# per-user, not committable, so we print rather than copy).
$attach = $null
Push-Location $WorkspaceDir
try {
    $attach = & west list -f '{name} {path}' 2>$null
} catch { } finally { Pop-Location }

if ($attach) {
    Write-Host ""
    Write-Host "  Suggested 'Attach Directory to Project' targets (right-click"
    Write-Host "  the project root in the pane, or File -> Attach Directory):"
    foreach ($line in $attach) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -ne 2) { continue }
        $name, $path = $parts
        if ($name -eq 'manifest' -or $name -eq $AppName) { continue }
        Write-Host "    - $WorkspaceDir\$path  ($name)"
    }
}

@"

  Debug (one-time machine-local setup, not committed):
    - Settings -> Build, Execution, Deployment -> Toolchains -> + System.
      Set C/C++ compiler and Debugger to the matching toolchain binaries
      under `$env:ZEPHYR_SDK_INSTALL_DIR\<arch>-zephyr-*\bin\.
    - Run -> Edit Configurations -> + GDB Remote Debug.
      'target remote' args: tcp:localhost:3333
      Symbol file: $WorkspaceDir\build\$AppName\zephyr\zephyr.elf
"@ | Write-Host
