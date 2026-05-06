#!/usr/bin/env bash
# new-workspace.sh -- bootstrap a Zephyr T2 workspace from an app git repo.
#
# Usage:
#   new-workspace.sh [--ide vscode|clion] [--toolchain LIST]
#                    <workspace-dir> <app-repo-url> [<manifest-subdir>]
#
# Examples:
#   ./new-workspace.sh ~/projects/foo-workspace https://github.com/me/foo.git
#   ./new-workspace.sh --ide clion --toolchain arm \
#       ~/projects/foo-workspace https://github.com/me/foo.git
#
# IDE setup (--ide):
#   When --ide=<name> is given, after the workspace is otherwise ready the
#   bootstrap looks for an init script in this order:
#       1. <workspace>/<app>/scripts/ide-setup/<name>-init.sh   (project-shipped)
#       2. <tools-repo>/ide-defaults/<name>-init.sh             (fallback)
#   and runs it with two args: the workspace dir and the cloned app dir.
#
# Toolchain install (--toolchain):
#   Off by default. Comma-separated short names: arm, arm64, riscv, or
#   the literal "all" (full SDK, ~3 GB). The matching tarballs are
#   downloaded from sdk-ng releases for the SDK version that the cloned
#   zephyr/SDK_VERSION pins, extracted under $HOME/zephyr-sdk-<version>/,
#   and registered via setup.sh. Skipped if that dir already exists.
#
# Optional env vars:
#   TOOLS_REPO_URL  git URL of zephyr-bootstrap.
#   TOOLS_REPO_DIR  local clone path of the tools repo
#                   (default: $HOME/projects/zephyr-bootstrap).
#                   Reused as-is if it already exists.

set -euo pipefail

DEFAULT_TOOLS_REPO_URL="https://github.com/Assar63/zephyr-bootstrap.git"
DEFAULT_TOOLS_REPO_DIR="$HOME/projects/zephyr-bootstrap"

usage() {
	cat >&2 <<EOF
Usage: $(basename "$0") [--ide vscode|clion] [--toolchain LIST]
                       <workspace-dir> <app-repo-url> [<manifest-subdir>]

  --ide <name>        Optional. After bootstrap, run the project's (or
                      bundled-default) ide-setup/<name>-init.sh.
                      Accepted: vscode, clion.
  --toolchain LIST    Optional. Off by default. Comma-separated short
                      names (arm, arm64, riscv) or "all" (full SDK).
                      Installs the matching Zephyr SDK to
                      \$HOME/zephyr-sdk-<version>/.
  <workspace-dir>     Directory to create for the new workspace.
  <app-repo-url>      Git URL of the Zephyr app (must contain west.yml).
  <manifest-subdir>   Optional. Directory name under the workspace where the
                      app is cloned. Defaults to the basename of the URL
                      with .git stripped.
EOF
	exit 1
}

IDE=""
TOOLCHAIN=""
POSITIONAL=()
while [ $# -gt 0 ]; do
	case "$1" in
		--ide)        [ $# -ge 2 ] || usage; IDE="$2"; shift 2 ;;
		--ide=*)      IDE="${1#--ide=}"; shift ;;
		--toolchain)  [ $# -ge 2 ] || usage; TOOLCHAIN="$2"; shift 2 ;;
		--toolchain=*) TOOLCHAIN="${1#--toolchain=}"; shift ;;
		-h|--help)    usage ;;
		--)           shift; POSITIONAL+=("$@"); break ;;
		-*)           echo "Unknown option: $1" >&2; usage ;;
		*)            POSITIONAL+=("$1"); shift ;;
	esac
done
set -- "${POSITIONAL[@]}"

case "$IDE" in
	""|vscode|clion) ;;
	*) echo "Unknown --ide value: '$IDE' (expected vscode or clion)" >&2; exit 1 ;;
esac

# Validate toolchain list early so we don't get to a bad name after a 5-min west update.
if [ -n "$TOOLCHAIN" ] && [ "$TOOLCHAIN" != "all" ]; then
	IFS=',' read -ra _TC_VALIDATE <<<"$TOOLCHAIN"
	for tc in "${_TC_VALIDATE[@]}"; do
		case "$tc" in
			arm|arm64|riscv) ;;
			*) echo "Unknown --toolchain entry: '$tc' (expected arm, arm64, riscv, or all)" >&2; exit 1 ;;
		esac
	done
fi

[ "$#" -ge 2 ] || usage

WORKSPACE_DIR="$1"
APP_REPO_URL="$2"
APP_DIR_NAME="${3:-$(basename "$APP_REPO_URL" .git)}"

TOOLS_REPO_URL="${TOOLS_REPO_URL:-$DEFAULT_TOOLS_REPO_URL}"
TOOLS_REPO_DIR="${TOOLS_REPO_DIR:-$DEFAULT_TOOLS_REPO_DIR}"

log() { printf '==> %s\n' "$*"; }

# Host deps
command -v git >/dev/null 2>&1 \
	|| { echo "Missing required tool: git" >&2; exit 1; }

# Prefer uv (much faster venv + installs) and fall back to python3+pip if not present.
if command -v uv >/dev/null 2>&1; then
	USE_UV=1
	log "Using uv for venv and package installs"
else
	USE_UV=0
	command -v python3 >/dev/null 2>&1 \
		|| { echo "Missing required tool: python3 (or install uv)" >&2; exit 1; }
	python3 -c 'import venv' 2>/dev/null \
		|| { echo "python3 venv module not available; install python3-venv (or install uv)" >&2; exit 1; }
fi

create_venv() {
	if [ "$USE_UV" = "1" ]; then
		uv venv "$1"
	else
		python3 -m venv "$1"
	fi
}

pip_install() {
	if [ "$USE_UV" = "1" ]; then
		uv pip install --quiet "$@"
	else
		pip install --quiet "$@"
	fi
}

install_zephyr_sdk() {
	# Args: $1 = comma-separated short names ("arm", "arm,riscv", or "all")
	local req="$1"
	local sdk_version sdk_dir os arch osarch base_url
	local tc_full setup_args=(-h -c)

	sdk_version="$(cat zephyr/SDK_VERSION 2>/dev/null || true)"
	[ -n "$sdk_version" ] || { echo "could not read zephyr/SDK_VERSION" >&2; return 1; }
	sdk_dir="$HOME/zephyr-sdk-$sdk_version"

	if [ -d "$sdk_dir" ]; then
		log "Zephyr SDK $sdk_version already at $sdk_dir; skipping install"
		return 0
	fi

	case "$(uname -s)" in
		Linux)  os="linux" ;;
		Darwin) os="macos" ;;
		*) echo "--toolchain: unsupported OS $(uname -s) (use the .ps1 bootstrap on Windows)" >&2; return 1 ;;
	esac
	case "$(uname -m)" in
		x86_64|amd64)   arch="x86_64" ;;
		aarch64|arm64)  arch="aarch64" ;;
		*) echo "--toolchain: unsupported arch $(uname -m)" >&2; return 1 ;;
	esac
	osarch="${os}-${arch}"
	base_url="https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${sdk_version}"

	log "Installing Zephyr SDK $sdk_version into $sdk_dir"

	if [ "$req" = "all" ]; then
		log "  downloading full SDK (large)"
		curl -fsSL "$base_url/zephyr-sdk-${sdk_version}_${osarch}.tar.xz" -o /tmp/zsdk.tar.xz
		tar -xf /tmp/zsdk.tar.xz -C "$HOME"
		rm /tmp/zsdk.tar.xz
		( cd "$sdk_dir" && bash setup.sh -h -c -t all )
	else
		log "  downloading minimal SDK"
		curl -fsSL "$base_url/zephyr-sdk-${sdk_version}_${osarch}_minimal.tar.xz" -o /tmp/zsdk-min.tar.xz
		tar -xf /tmp/zsdk-min.tar.xz -C "$HOME"
		rm /tmp/zsdk-min.tar.xz
		IFS=',' read -ra _tc_array <<<"$req"
		for tc in "${_tc_array[@]}"; do
			case "$tc" in
				arm)   tc_full="arm-zephyr-eabi" ;;
				arm64) tc_full="aarch64-zephyr-elf" ;;
				riscv) tc_full="riscv64-zephyr-elf" ;;
			esac
			log "  downloading toolchain: $tc_full"
			curl -fsSL "$base_url/toolchain_gnu_${osarch}_${tc_full}.tar.xz" -o /tmp/zsdk-tc.tar.xz
			tar -xf /tmp/zsdk-tc.tar.xz -C "$sdk_dir"
			rm /tmp/zsdk-tc.tar.xz
			setup_args+=(-t "$tc_full")
		done
		( cd "$sdk_dir" && bash setup.sh "${setup_args[@]}" )
	fi
}

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
	create_venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
# pip self-upgrade is only meaningful on the pip path; uv doesn't use pip's machinery.
[ "$USE_UV" = "0" ] && pip_install --upgrade pip
pip_install west

if [ -d .west ]; then
	log "west already initialized; skipping init"
else
	log "west init -l $APP_DIR_NAME"
	west init -l "$APP_DIR_NAME"
fi

log "west update (may take several minutes)"
west update

log "Installing Zephyr Python deps"
pip_install -r zephyr/scripts/requirements.txt

if [ -n "$TOOLCHAIN" ]; then
	install_zephyr_sdk "$TOOLCHAIN"
fi

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

if [ -n "$IDE" ]; then
	APP_FULL="$WORKSPACE_DIR/$APP_DIR_NAME"
	PROJECT_INIT="$APP_FULL/scripts/ide-setup/${IDE}-init.sh"
	DEFAULT_INIT="$TOOLS_REPO_DIR/ide-defaults/${IDE}-init.sh"
	# Export so project init scripts can delegate to / locate the defaults.
	export ZEPHYR_BOOTSTRAP_DIR="$TOOLS_REPO_DIR"
	if [ -f "$PROJECT_INIT" ]; then
		log "Running project IDE init: $PROJECT_INIT"
		bash "$PROJECT_INIT" "$WORKSPACE_DIR" "$APP_FULL"
	elif [ -f "$DEFAULT_INIT" ]; then
		log "No project IDE init found; using default: $DEFAULT_INIT"
		bash "$DEFAULT_INIT" "$WORKSPACE_DIR" "$APP_FULL"
	else
		echo "Warning: --ide=$IDE requested but no init script found (project nor default); skipping" >&2
	fi
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
