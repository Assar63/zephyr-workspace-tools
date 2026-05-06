#!/usr/bin/env bash
# Flash the current build to the Nucleo-H753ZI via openocd.
# Wired into CLion as a "Flash" Shell Script run configuration.
set -euo pipefail
WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$WS/activate.sh" >/dev/null
exec west flash "$@"
