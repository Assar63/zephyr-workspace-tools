#!/usr/bin/env bash
# Default CLion init -- used when the project doesn't ship its own
# scripts/ide-setup/clion-init.sh. Drops the standard run configurations
# (Flash, OpenOCD GDB Server, Serial Monitor) into <app>/.idea/runConfigurations/
# if they aren't already present. Existing files are never overwritten.
#
# Args:
#   $1  workspace dir
#   $2  app dir (the cloned project root inside the workspace)
set -euo pipefail

WORKSPACE_DIR="$1"
APP_DIR="$2"
APP_NAME="$(basename "$APP_DIR")"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SELF_DIR/clion/runConfigurations"
DST="$APP_DIR/.idea/runConfigurations"

mkdir -p "$DST"

wrote_any=0
for f in "$SRC"/*.xml; do
	name="$(basename "$f")"
	if [ -e "$DST/$name" ]; then
		echo "  $DST/$name already exists; leaving alone"
	else
		cp "$f" "$DST/$name"
		echo "  wrote $DST/$name"
		wrote_any=1
	fi
done

cat <<EOF
CLion default setup ready.

  1. Open this folder as the CLion project (NOT the workspace root):
       $APP_DIR
  2. CMakePresets.json (if shipped by the project) is autodetected --
     pick the configure preset matching your board.
  3. Run configurations (Flash, OpenOCD GDB Server, Serial Monitor)
     loaded from .idea/runConfigurations/. They invoke
     ../tools/{flash,gdb-server,serial-monitor}.sh which the bootstrap
     placed at the workspace root.

  Debug (one-time machine-local setup, not committed):
    - Settings -> Build, Execution, Deployment -> Toolchains -> + System.
      Set C/C++ compiler and Debugger to the matching toolchain binaries
      under \$ZEPHYR_SDK_INSTALL_DIR/<arch>-zephyr-*/bin/.
    - Run -> Edit Configurations -> + GDB Remote Debug.
      'target remote' args: tcp:localhost:3333
      Symbol file: $WORKSPACE_DIR/build/$APP_NAME/zephyr/zephyr.elf
EOF
