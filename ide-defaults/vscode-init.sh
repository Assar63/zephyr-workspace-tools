#!/usr/bin/env bash
# Default VSCode init -- used when the project doesn't ship its own
# scripts/ide-setup/vscode-init.sh. Generates a multi-root .code-workspace
# at the workspace root (app + workspace + every west-managed module
# present on disk) and a .vscode/tasks.json with build/flash/monitor
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
	# Use Python (in the activated venv) to build the JSON, since we want
	# to inject west-managed folders dynamically. Falls back to a basic
	# 2-folder workspace if `west list` fails.
	APP_NAME="$APP_NAME" CW_PATH="$CW" WORKSPACE_DIR="$WORKSPACE_DIR" python3 - <<'PYEOF'
import json, os, subprocess

app = os.environ['APP_NAME']
cw_path = os.environ['CW_PATH']
ws = os.environ['WORKSPACE_DIR']

folders = [
    {"name": app, "path": app},
    {"name": "workspace", "path": "."},
]

try:
    out = subprocess.check_output(
        ['west', 'list', '-f', '{name} {path}'],
        cwd=ws, stderr=subprocess.DEVNULL, text=True,
    )
    seen = {f["name"] for f in folders}
    for line in out.splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) != 2:
            continue
        name, path = parts
        # 'manifest' is the self-entry (the app); already in folders.
        if name == 'manifest' or name in seen:
            continue
        if not os.path.isdir(os.path.join(ws, path)):
            continue
        folders.append({"name": name, "path": path})
        seen.add(name)
except (subprocess.CalledProcessError, FileNotFoundError):
    pass

config = {
    "folders": folders,
    "settings": {
        "clangd.arguments": [
            "--compile-commands-dir=${workspaceFolder:workspace}/build/" + app,
            "--background-index",
            "--header-insertion=never",
            "--clang-tidy",
        ],
        "files.exclude": {
            "build": True, "modules": True, "zephyr": True,
            ".venv": True, ".west": True,
        },
        "files.watcherExclude": {
            "**/build/**": True, "**/modules/**": True,
            "**/zephyr/**": True, "**/.venv/**": True,
        },
        "C_Cpp.intelliSenseEngine": "disabled",
    },
    "extensions": {
        "recommendations": [
            "llvm-vs-code-extensions.vscode-clangd",
            "marus25.cortex-debug",
        ]
    },
}

with open(cw_path, 'w') as f:
    json.dump(config, f, indent=4)

print(f"  wrote {cw_path} ({len(folders)} folders)")
PYEOF
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

  Each west-managed module appears as its own folder in the multi-root
  workspace -- no digging through modules/ to find HAL sources.
EOF
