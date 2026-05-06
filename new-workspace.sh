#!/usr/bin/env bash
# new-workspace.sh -- bootstrap a Zephyr T2 workspace from an app git repo.
#
# Usage:
#   new-workspace.sh <workspace-dir> <app-repo-url> [<manifest-subdir>]
#
# Examples:
#   ./new-workspace.sh ~/projects/foo-workspace https://github.com/me/foo.git
#   curl -sL https://raw.githubusercontent.com/Assar63/zephyr-workspace-tools/main/new-workspace.sh \
#       | bash -s -- ~/projects/foo-workspace https://github.com/me/foo.git
#
# Optional env vars:
#   TOOLS_REPO_URL  git URL of zephyr-workspace-tools (default below; edit after publishing)
#   TOOLS_REPO_DIR  local clone path of the tools repo
#                   (default: $HOME/projects/zephyr-workspace-tools).
#                   If this directory already exists it is reused as-is.

set -euo pipefail

DEFAULT_TOOLS_REPO_URL="https://github.com/Assar63/zephyr-workspace-tools.git"
DEFAULT_TOOLS_REPO_DIR="$HOME/projects/zephyr-workspace-tools"

usage() {
	cat >&2 <<EOF
Usage: $(basename "$0") <workspace-dir> <app-repo-url> [<manifest-subdir>]

  <workspace-dir>     Directory to create for the new workspace.
  <app-repo-url>      Git URL of the Zephyr app (must contain west.yml).
  <manifest-subdir>   Optional. Directory name under the workspace where the
                      app is cloned. Defaults to the basename of the URL
                      with .git stripped.
EOF
	exit 1
}

[ "$#" -ge 2 ] || usage

WORKSPACE_DIR="$1"
APP_REPO_URL="$2"
APP_DIR_NAME="${3:-$(basename "$APP_REPO_URL" .git)}"

TOOLS_REPO_URL="${TOOLS_REPO_URL:-$DEFAULT_TOOLS_REPO_URL}"
TOOLS_REPO_DIR="${TOOLS_REPO_DIR:-$DEFAULT_TOOLS_REPO_DIR}"

log() { printf '==> %s\n' "$*"; }

# Host deps
for cmd in python3 git; do
	command -v "$cmd" >/dev/null 2>&1 \
		|| { echo "Missing required tool: $cmd" >&2; exit 1; }
done
python3 -c 'import venv' 2>/dev/null \
	|| { echo "python3 venv module not available; install python3-venv" >&2; exit 1; }

log "Creating workspace at $WORKSPACE_DIR"
mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

if [ -d "$APP_DIR_NAME/.git" ]; then
	log "$APP_DIR_NAME already cloned; skipping"
else
	log "Cloning $APP_REPO_URL -> $APP_DIR_NAME"
	git clone "$APP_REPO_URL" "$APP_DIR_NAME"
fi

if [ ! -d .venv ]; then
	log "Creating Python venv (.venv)"
	python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet west

if [ -d .west ]; then
	log "west already initialized; skipping init"
else
	log "west init -l $APP_DIR_NAME"
	west init -l "$APP_DIR_NAME"
fi

log "west update (may take several minutes)"
west update

log "Installing Zephyr Python deps"
pip install --quiet -r zephyr/scripts/requirements.txt

if [ ! -d "$TOOLS_REPO_DIR" ]; then
	log "Cloning workspace tools repo to $TOOLS_REPO_DIR"
	mkdir -p "$(dirname "$TOOLS_REPO_DIR")"
	git clone "$TOOLS_REPO_URL" "$TOOLS_REPO_DIR"
fi

if [ ! -e activate.sh ]; then
	log "Symlinking activate.sh and tools/ from $TOOLS_REPO_DIR"
	ln -s "$TOOLS_REPO_DIR/activate.sh" activate.sh
	ln -s "$TOOLS_REPO_DIR/tools" tools
fi

cat <<EOF

Workspace ready at: $WORKSPACE_DIR

Next steps:
  cd $WORKSPACE_DIR
  source activate.sh
  west build $APP_DIR_NAME

Note: this script does NOT install the Zephyr SDK or board-specific host
tools (openocd, picocom, ...). Install those separately for your target.
EOF
