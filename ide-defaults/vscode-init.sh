#!/usr/bin/env bash
# Default VSCode init -- used when the project doesn't ship its own
# scripts/ide-setup/vscode-init.sh. Generates a multi-root .code-workspace
# at the workspace root and a .vscode/tasks.json with build/flash/monitor
# tasks. Existing files are never overwritten.
#
# Args:
#   $1  workspace dir
#   $2  app dir (the cloned project root inside the workspace)
set -euo pipefail

WORKSPACE_DIR="$1"
APP_DIR="$2"
APP_NAME="$(basename "$APP_DIR")"

mkdir -p "$WORKSPACE_DIR/.vscode"

CW="$WORKSPACE_DIR/$APP_NAME.code-workspace"
if [ -e "$CW" ]; then
	echo "  $CW already exists; leaving alone"
else
	cat > "$CW" <<EOF
{
    "folders": [
        { "name": "$APP_NAME", "path": "$APP_NAME" },
        { "name": "workspace", "path": "." }
    ],
    "settings": {
        "clangd.arguments": [
            "--compile-commands-dir=\${workspaceFolder:workspace}/build/$APP_NAME",
            "--background-index",
            "--header-insertion=never",
            "--clang-tidy"
        ],
        "files.exclude": {
            "build": true,
            "modules": true,
            "zephyr": true,
            ".venv": true,
            ".west": true
        },
        "files.watcherExclude": {
            "**/build/**": true,
            "**/modules/**": true,
            "**/zephyr/**": true,
            "**/.venv/**": true
        },
        "C_Cpp.intelliSenseEngine": "disabled"
    },
    "extensions": {
        "recommendations": [
            "llvm-vs-code-extensions.vscode-clangd",
            "marus25.cortex-debug"
        ]
    }
}
EOF
	echo "  wrote $CW"
fi

TASKS="$WORKSPACE_DIR/.vscode/tasks.json"
if [ -e "$TASKS" ]; then
	echo "  $TASKS already exists; leaving alone"
else
	cat > "$TASKS" <<EOF
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Build",
            "type": "shell",
            "command": "bash",
            "args": [
                "-c",
                "source \"\${workspaceFolder}/activate.sh\" && west build $APP_NAME"
            ],
            "problemMatcher": ["\$gcc"],
            "group": { "kind": "build", "isDefault": true }
        },
        {
            "label": "Pristine Build",
            "type": "shell",
            "command": "bash",
            "args": [
                "-c",
                "source \"\${workspaceFolder}/activate.sh\" && west build -p always $APP_NAME"
            ],
            "problemMatcher": ["\$gcc"]
        },
        {
            "label": "Flash",
            "type": "shell",
            "command": "\${workspaceFolder}/tools/flash.sh",
            "problemMatcher": []
        },
        {
            "label": "Serial Monitor",
            "type": "shell",
            "command": "\${workspaceFolder}/tools/serial-monitor.sh",
            "problemMatcher": [],
            "presentation": { "reveal": "always", "panel": "dedicated" }
        },
        {
            "label": "OpenOCD GDB Server",
            "type": "shell",
            "command": "\${workspaceFolder}/tools/gdb-server.sh",
            "isBackground": true,
            "problemMatcher": {
                "pattern": [{ "regexp": ".", "file": 1, "location": 2, "message": 3 }],
                "background": {
                    "activeOnStart": true,
                    "beginsPattern": "Open On-Chip Debugger",
                    "endsPattern": "Listening on port"
                }
            }
        }
    ]
}
EOF
	echo "  wrote $TASKS"
fi

cat <<EOF
VSCode default setup ready.

  Open this file in VSCode (NOT the directory):
    $CW

  Recommended extensions: clangd (code intel), Cortex-Debug (debugging).
  IntelliSense is disabled by design -- clangd handles indexing using the
  build's compile_commands.json.
EOF
