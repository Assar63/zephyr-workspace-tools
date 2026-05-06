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

_WS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_WS_NAME="$(basename "${_WS}")"

# shellcheck disable=SC1091
. "${_WS}/.venv/bin/activate"

export ZEPHYR_BASE="${_WS}/zephyr"
# Override before sourcing if your SDK lives elsewhere.
: "${ZEPHYR_SDK_INSTALL_DIR:=${HOME}/zephyr-sdk-1.0.1}"
export ZEPHYR_SDK_INSTALL_DIR

echo "${_WS_NAME} workspace ready"
echo "  ZEPHYR_BASE=${ZEPHYR_BASE}"
echo "  ZEPHYR_SDK_INSTALL_DIR=${ZEPHYR_SDK_INSTALL_DIR}"
echo "  west:  $(command -v west)"
echo "  pyocd: $(command -v pyocd)"

unset _WS _WS_NAME
