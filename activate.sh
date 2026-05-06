# Source this file from the workspace root:
#
#   source activate.sh
#
# It activates the in-tree Python venv and sets ZEPHYR_BASE / SDK so that
# `west`, `cmake --preset`, and clangd all see a consistent environment.

if [ -z "${BASH_SOURCE[0]}" ]; then
	echo "activate.sh must be sourced from bash/zsh, not executed" >&2
	return 1 2>/dev/null || exit 1
fi

_RV_DISPLAY_WS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
. "${_RV_DISPLAY_WS}/.venv/bin/activate"

export ZEPHYR_BASE="${_RV_DISPLAY_WS}/zephyr"
export ZEPHYR_SDK_INSTALL_DIR="${HOME}/zephyr-sdk-1.0.1"

unset _RV_DISPLAY_WS

echo "rv_display workspace ready"
echo "  ZEPHYR_BASE=${ZEPHYR_BASE}"
echo "  ZEPHYR_SDK_INSTALL_DIR=${ZEPHYR_SDK_INSTALL_DIR}"
echo "  west:  $(command -v west)"
echo "  pyocd: $(command -v pyocd)"
