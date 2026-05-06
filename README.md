# zephyr-workspace-tools

Reusable shell helpers for Zephyr T2 workspaces. Not specific to any single
application — drop into any workspace where you want a consistent
`source activate.sh` + `west flash` / `tools/serial-monitor.sh` workflow.

Licensed under [Apache-2.0](LICENSE), matching the Zephyr project itself.

## What's here

Each helper has a bash and a PowerShell variant; pick whichever your shell
prefers. Both call into the same workspace state.

| File | Purpose |
|------|---------|
| `new-workspace.sh` / `new-workspace.ps1` | Bootstrap. Given a target directory and a Zephyr-app git URL, creates the workspace, clones the app, makes a venv, runs `west init -l` + `west update`, installs Zephyr's Python deps, and links `activate` + `tools/` from this repo. Bash version is `curl ... \| bash`-safe. |
| `activate.sh` / `activate.ps1` | Activates the workspace's `.venv` and exports `ZEPHYR_BASE` / `ZEPHYR_SDK_INSTALL_DIR`. Source from the workspace root. |
| `tools/flash.sh` / `tools/flash.ps1` | `west flash` wrapper. Wired into CLion run configs and VSCode tasks. |
| `tools/gdb-server.sh` / `tools/gdb-server.ps1` | Starts openocd as a GDB server on `:3333`. Adjust the `-f board/...cfg` line for other boards. |
| `tools/serial-monitor.sh` / `tools/serial-monitor.ps1` | Opens the board's serial console. Bash: prefers `tio`/`picocom`, falls back to `stty + cat`. PS: uses `[System.IO.Ports.SerialPort]`; override port with `$env:PORT`. |

## Bootstrap a new workspace

### Linux / macOS (bash)

```sh
# Local clone of this repo:
./new-workspace.sh ~/projects/foo-workspace https://github.com/me/foo.git

# With IDE setup hook:
./new-workspace.sh --ide clion ~/projects/foo-workspace https://github.com/me/foo.git

# Or one-shot from the published repo:
curl -sL https://raw.githubusercontent.com/Assar63/zephyr-workspace-tools/main/new-workspace.sh \
    | bash -s -- --ide vscode ~/projects/foo-workspace https://github.com/me/foo.git
```

### Windows (PowerShell)

```powershell
# Local clone of this repo:
.\new-workspace.ps1 C:\dev\foo-workspace https://github.com/me/foo.git

# With IDE setup hook:
.\new-workspace.ps1 C:\dev\foo-workspace https://github.com/me/foo.git -Ide vscode

# Or one-shot from the published repo:
iwr https://raw.githubusercontent.com/Assar63/zephyr-workspace-tools/main/new-workspace.ps1 -OutFile new-workspace.ps1
.\new-workspace.ps1 C:\dev\foo-workspace https://github.com/me/foo.git -Ide vscode
```

The PowerShell port copies `activate.ps1` + `tools\` into the workspace
instead of symlinking, so it works on stock Windows without Developer
Mode. Re-run `new-workspace.ps1` to refresh after the tools repo is
updated.

`<app-repo-url>` must point at a Zephyr application that contains a
`west.yml` manifest at its root (T2 manifest-in-app topology).

The script uses [`uv`](https://docs.astral.sh/uv/) for the venv and
package installs if it's on `PATH` (Zephyr's `requirements.txt` pulls
~80 packages, ~10× faster), and silently falls back to
`python3 -m venv` + `pip` otherwise.

## Project-supplied IDE setup (`--ide`)

Bootstrapping with `--ide vscode` or `--ide clion` causes the script to
look for an init script in the cloned project:

```
<workspace>/<app>/ide-setup/<ide>-init.sh
```

For Windows / PowerShell users the corresponding path is:

```
<workspace>\<app>\ide-setup\<ide>-init.ps1
```

In either case, the init script is run with the workspace dir as the
first argument. It can do whatever the project needs — drop `.vscode/`
into the workspace root, materialize a `.code-workspace`, generate CLion
`.idea/runConfigurations/` entries, copy launch configs, etc.

This bootstrap is intentionally IDE-agnostic — no layout conventions are
hard-coded here. Projects opt in by adding their own `ide-setup/` scripts.

A skeleton init script:

```sh
#!/usr/bin/env bash
# ide-setup/vscode-init.sh
set -euo pipefail
WORKSPACE_DIR="$1"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# example: drop a curated .vscode/ into the workspace root
mkdir -p "$WORKSPACE_DIR/.vscode"
cp -n "$APP_DIR"/ide-setup/vscode/*.json "$WORKSPACE_DIR/.vscode/"
```

## Install into a Zephyr workspace

From inside an existing workspace root (the dir containing `.west/`,
`zephyr/`, `modules/`, and your app subdir):

```sh
ln -s ~/projects/zephyr-workspace-tools/activate.sh activate.sh
ln -s ~/projects/zephyr-workspace-tools/tools tools
```

The scripts use `${BASH_SOURCE[0]}`-relative paths that resolve to the
workspace dir (not the symlink target), so the same files serve any
number of workspaces.

## Per-workspace assumptions

- `.venv/` exists at the workspace root with `west` installed.
- Zephyr SDK is at `~/zephyr-sdk-1.0.1` (override `ZEPHYR_SDK_INSTALL_DIR`
  before sourcing if not).
- For a different board, edit `tools/gdb-server.sh` (`-f board/<name>.cfg`)
  and `tools/serial-monitor.sh` (`PORT=` default).
