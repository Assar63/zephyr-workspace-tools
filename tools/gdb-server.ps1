# Start openocd as a GDB server on :3333 for the configured board.
# Used as the upstream of a "GDB Remote Debug" run config.

$ErrorActionPreference = 'Stop'

if (-not (Get-Command openocd -ErrorAction SilentlyContinue)) {
    Write-Error "openocd not found on PATH. Install it (e.g. via xPack openocd or scoop) and try again."
    exit 1
}

# Adjust -f for your board; default targets the Nucleo-H753ZI.
& openocd `
    -f board/st_nucleo_h743zi.cfg `
    -c 'gdb_port 3333' `
    -c 'tcl_port disabled' `
    -c 'telnet_port disabled' `
    -c 'init' `
    -c 'reset halt'
exit $LASTEXITCODE
