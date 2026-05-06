#!/usr/bin/env bash
# Open the ST-Link VCP (where Zephyr's console lives on the Nucleo-H753ZI).
# Prefers a real serial terminal if one is installed; falls back to stty+cat.
set -euo pipefail
PORT="${PORT:-/dev/ttyACM1}"
BAUD="${BAUD:-115200}"

if [ ! -e "$PORT" ]; then
	echo "Serial port $PORT not found. Set PORT=/dev/ttyACMx if it differs." >&2
	exit 1
fi

if command -v tio >/dev/null 2>&1; then
	exec tio -b "$BAUD" "$PORT"
elif command -v picocom >/dev/null 2>&1; then
	exec picocom -b "$BAUD" "$PORT"
elif command -v minicom >/dev/null 2>&1; then
	exec minicom -b "$BAUD" -D "$PORT" -o
else
	echo "No serial terminal (tio/picocom/minicom) found; using stty+cat fallback." >&2
	echo "Install one with: sudo apt install tio  (or picocom)" >&2
	stty -F "$PORT" "$BAUD" raw -echo
	exec cat "$PORT"
fi
