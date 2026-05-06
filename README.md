# zephyr-workspace-tools

Reusable shell helpers for Zephyr T2 workspaces. Not specific to any single
application — drop into any workspace where you want a consistent
`source activate.sh` + `west flash` / `tools/serial-monitor.sh` workflow.

Licensed under [Apache-2.0](LICENSE), matching the Zephyr project itself.

## Workspace topology

What the bootstrap creates and how the three pieces — this tools repo,
the workspace it builds, and the host-installed Zephyr SDK — relate:

```mermaid
graph TB
    subgraph sdk["~/zephyr-sdk-1.0.1/  (Zephyr SDK, installed separately)"]
        arm["arm-zephyr-eabi/"]
        sdk_other["…other toolchains"]
    end

    subgraph tools_repo["~/projects/zephyr-workspace-tools/  (this repo)"]
        nw["new-workspace.{sh,ps1}"]
        seed["seed-ide-templates.{sh,ps1}"]
        act["activate.{sh,ps1}"]
        t_bin["tools/{flash,gdb-server,serial-monitor}.{sh,ps1}"]
        id_def["ide-defaults/{clion,vscode}-init.{sh,ps1}<br/>+ runConfigurations XMLs"]
    end

    subgraph ws["~/projects/&lt;workspace&gt;/  (Zephyr T2 workspace, created by bootstrap)"]
        ws_venv[".venv/  (Python venv with west)"]
        ws_west[".west/config"]
        ws_act["activate.{sh,ps1}  ⇒  link/copy"]
        ws_tools["tools/  ⇒  link/copy"]
        ws_zephyr["zephyr/  (fetched by west update)"]
        ws_modules["modules/…  (fetched by west update)"]
        subgraph app["&lt;app&gt;/  (your cloned Zephyr application)"]
            a_west["west.yml"]
            a_cmake["CMakeLists.txt"]
            a_prj["prj.conf"]
            a_src["src/"]
            a_idesetup["scripts/ide-setup/<br/>(optional; overrides defaults)"]
        end
    end

    nw -.->|bootstraps| ws
    nw -.->|builds against| sdk
    act -.->|symlinked / copied as| ws_act
    t_bin -.->|symlinked / copied as| ws_tools
    id_def -.->|fallback IDE init| app
    seed -.->|copies templates into| a_idesetup
```

The tools repo lives once per machine; each new project gets its own
workspace dir that links back to it. The Zephyr SDK is shared across
all workspaces.

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
| `ide-defaults/{clion,vscode}-init.{sh,ps1}` | Fallback IDE setup used when the project doesn't ship its own. Generates `.idea/runConfigurations/` (CLion) or `.code-workspace` + `.vscode/tasks.json` (VSCode), skipping anything that already exists. |
| `seed-ide-templates.{sh,ps1}` | Copies the matching `ide-defaults/` files into a project's `scripts/ide-setup/` so you can fork them and customize. Once seeded, the bootstrap will run the project's copy instead of the in-repo defaults. |

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
look for an init script in this order:

1. `<workspace>/<app>/scripts/ide-setup/<ide>-init.{sh,ps1}` — project-shipped
2. `<tools-repo>/ide-defaults/<ide>-init.{sh,ps1}` — fallback bundled with this repo

The chosen script is run with **two arguments**: the workspace dir and
the cloned app dir.

Project-shipped scripts can do anything the project needs — drop
`.vscode/` into the workspace root, materialize a `.code-workspace`,
generate CLion `.idea/runConfigurations/` entries, etc.

If the project doesn't ship its own, the bundled defaults in
`ide-defaults/` produce a sensible baseline:

- **clion**: copies the standard `Flash`, `OpenOCD GDB Server`, and
  `Serial Monitor` run configs into `<app>/.idea/runConfigurations/`.
  Also runs `west list` and prints suggested **"Attach Directory to
  Project"** targets — Zephyr itself plus every fetched module — so
  the user can pull them into the project pane in one right-click each.
  (CLion stores attached directories in `workspace.xml`, which is
  per-user and not committable, so this stays a printed hint.)
- **vscode**: writes a multi-root `<app>.code-workspace` whose
  `folders` array is populated from `west list` — the app, the
  workspace itself, Zephyr, and every fetched module each get their
  own top-level entry in the Explorer (no digging through
  `modules/hal/...` to find HAL sources). Plus a `.vscode/tasks.json`
  (Build / Pristine Build / Flash / Serial Monitor / OpenOCD GDB
  Server) at the workspace root.

Either way, **existing files are never overwritten** — re-running the
bootstrap with `--ide` is an "update missing pieces" pass.

This bootstrap is intentionally IDE-agnostic — no layout conventions are
hard-coded here. Projects opt in by adding their own `ide-setup/` scripts.

### Forking the defaults into a project

If you want to override the defaults for a specific project rather than
write from scratch, run:

```sh
# Linux / macOS
./seed-ide-templates.sh path/to/your/zephyr-app
# or only one IDE
./seed-ide-templates.sh path/to/your/zephyr-app --ide vscode
```

```powershell
# Windows
.\seed-ide-templates.ps1 C:\path\to\your\zephyr-app
.\seed-ide-templates.ps1 C:\path\to\your\zephyr-app -Ide vscode
```

This copies `ide-defaults/<ide>-init.{sh,ps1}` (and CLion's
`runConfigurations/*.xml` data dir) into the project's
`scripts/ide-setup/`, never overwriting anything already there. After
that, the bootstrap finds the seeded copy first, so your edits to the
seeded files take effect.

### Writing a project init script from scratch

A skeleton project init script:

```sh
#!/usr/bin/env bash
# scripts/ide-setup/vscode-init.sh
set -euo pipefail
WORKSPACE_DIR="$1"
APP_DIR="$2"

# example: drop a curated .vscode/ into the workspace root
mkdir -p "$WORKSPACE_DIR/.vscode"
cp -n "$APP_DIR"/scripts/ide-setup/vscode/*.json "$WORKSPACE_DIR/.vscode/"
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
