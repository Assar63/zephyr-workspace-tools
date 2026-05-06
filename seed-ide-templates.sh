#!/usr/bin/env bash
# seed-ide-templates.sh -- copy ide-defaults/<ide>-init.{sh,ps1} into a
# project's scripts/ide-setup/ as a starting point for customization.
#
# Usage:
#   seed-ide-templates.sh <app-dir> [--ide vscode|clion|both]
#
# Default --ide is 'both'. Existing files in the target are never
# overwritten.
#
# After seeding, the bootstrap (`new-workspace.sh --ide <ide>`) will run
# the project's seeded copy instead of the in-repo defaults, and you can
# customize the seeded files freely.

set -euo pipefail

usage() {
	cat >&2 <<EOF
Usage: $(basename "$0") <app-dir> [--ide vscode|clion|both]

  <app-dir>        Path to the Zephyr application repo to seed into.
                   Files land at <app-dir>/scripts/ide-setup/.
  --ide <name>     Which IDE template(s) to seed. Default: both.
EOF
	exit 1
}

IDE=both
APP_DIR=

while [ $# -gt 0 ]; do
	case "$1" in
		--ide) [ $# -ge 2 ] || usage; IDE="$2"; shift 2 ;;
		--ide=*) IDE="${1#--ide=}"; shift ;;
		-h|--help) usage ;;
		-*) echo "Unknown option: $1" >&2; usage ;;
		*) [ -z "$APP_DIR" ] || usage; APP_DIR="$1"; shift ;;
	esac
done

[ -n "$APP_DIR" ] || usage
case "$IDE" in
	vscode|clion|both) ;;
	*) echo "Unknown --ide value: '$IDE'" >&2; exit 1 ;;
esac

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS="$SELF_DIR/ide-defaults"
TARGET="$APP_DIR/scripts/ide-setup"

mkdir -p "$TARGET"

copy_if_absent() {
	local src="$1" dst="$2"
	if [ -e "$dst" ]; then
		echo "  $dst exists; leaving alone"
	else
		mkdir -p "$(dirname "$dst")"
		cp "$src" "$dst"
		echo "  seeded: $dst"
	fi
}

seed_vscode() {
	copy_if_absent "$DEFAULTS/vscode-init.sh"  "$TARGET/vscode-init.sh"
	copy_if_absent "$DEFAULTS/vscode-init.ps1" "$TARGET/vscode-init.ps1"
}

seed_clion() {
	copy_if_absent "$DEFAULTS/clion-init.sh"  "$TARGET/clion-init.sh"
	copy_if_absent "$DEFAULTS/clion-init.ps1" "$TARGET/clion-init.ps1"
	# clion-init copies XML data files relative to its own location, so
	# the data dir must travel with the script.
	for f in "$DEFAULTS/clion/runConfigurations"/*.xml; do
		copy_if_absent "$f" "$TARGET/clion/runConfigurations/$(basename "$f")"
	done
}

case "$IDE" in
	vscode) seed_vscode ;;
	clion)  seed_clion ;;
	both)   seed_vscode; seed_clion ;;
esac

echo
echo "Done. Edit the seeded files under $TARGET/ to customize."
