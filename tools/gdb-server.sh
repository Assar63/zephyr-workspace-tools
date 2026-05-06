#!/usr/bin/env bash
# Start openocd as a GDB server for the Nucleo-H753ZI on :3333.
# Used as the upstream of CLion's "GDB Remote Debug" run configuration.
# Run this first, then start the debug config.
set -euo pipefail
exec openocd \
	-f board/st_nucleo_h743zi.cfg \
	-c 'gdb_port 3333' \
	-c 'tcl_port disabled' \
	-c 'telnet_port disabled' \
	-c 'init' \
	-c 'reset halt'
