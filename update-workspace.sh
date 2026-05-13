#!/usr/bin/env bash
# update-workspace.sh -- pull updates into an existing Zephyr workspace
# that was bootstrapped by new-workspace.sh.
#
# Usage:
#   update-workspace.sh [<workspace-dir>]    # defaults to $PWD
#
# What it does, in order:
#   1. git pull --ff-only the zephyr-bootstrap tools repo
#      (activate.sh / tools/ are symlinks into it on Linux/macOS,
#      so the workspace sees the new code automatically)
#   2. git pull --ff-only the app repo inside the workspace
#   3. west update                          (refresh zephyr + modules to pins)
#   4. re-install zephyr/scripts/requirements.txt (picks up any new deps)
#   5. upgrade west and pre-commit          (standalone tools)
#   6. re-run `pre-commit install` if the app ships .pre-commit-config.yaml

set -euo pipefail

WORKSPACE_DIR="${1:-$PWD}"
if [ ! -d "$WORKSPACE_DIR/.west" ]; then
	echo "Not a Zephyr workspace (no .west/ found): $WORKSPACE_DIR" >&2
	exit 1
fi

cd "$WORKSPACE_DIR"
WORKSPACE_DIR="$(pwd)"   # canonicalize

if [ ! -d .venv ]; then
	echo "Workspace has no .venv/ -- can't update without it." >&2
	exit 1
fi

log() { printf '==> %s\n' "$*"; }

# shellcheck disable=SC1091
source .venv/bin/activate

USE_UV=0
command -v uv >/dev/null 2>&1 && USE_UV=1

pip_install() {
	if [ "$USE_UV" = "1" ]; then
		uv pip install --quiet "$@"
	else
		pip install --quiet "$@"
	fi
}

# App dir comes from west's own config (set by `west init -l <app>`).
APP_DIR="$(west config manifest.path)"

# Tools repo: prefer following the workspace's `tools/` symlink (then up one
# level for the repo root). Fall back to $TOOLS_REPO_DIR / default.
TOOLS_REPO_DIR=""
if [ -L tools ]; then
	TOOLS_REPO_DIR="$(cd "$(dirname "$(readlink -f tools)")" && pwd)"
fi
TOOLS_REPO_DIR="${TOOLS_REPO_DIR:-${TOOLS_REPO_DIR_ENV:-$HOME/projects/zephyr-bootstrap}}"

if [ -d "$TOOLS_REPO_DIR/.git" ]; then
	log "Pulling tools repo: $TOOLS_REPO_DIR"
	git -C "$TOOLS_REPO_DIR" pull --ff-only
else
	echo "Warning: tools repo not found at $TOOLS_REPO_DIR; skipping its pull" >&2
fi

if [ -d "$APP_DIR/.git" ]; then
	log "Pulling app repo: $APP_DIR"
	git -C "$APP_DIR" pull --ff-only
fi

log "west update"
west update

log "Refreshing Zephyr Python deps"
pip_install -r zephyr/scripts/requirements.txt

log "Upgrading west and pre-commit"
pip_install --upgrade west pre-commit

if [ -f "$APP_DIR/.pre-commit-config.yaml" ]; then
	log "Re-installing pre-commit hooks"
	( cd "$APP_DIR" && pre-commit install )
fi

echo
echo "Update complete in $WORKSPACE_DIR."
