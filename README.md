# zephyr-workspace-tools

Reusable shell helpers for Zephyr T2 workspaces. Not specific to any single
application — drop into any workspace where you want a consistent
`source activate.sh` + `west flash` / `tools/serial-monitor.sh` workflow.

Licensed under [Apache-2.0](LICENSE), matching the Zephyr project itself.

## What's here

| File | Purpose |
|------|---------|
| `new-workspace.sh` | Bootstrap script. Given a target directory and a Zephyr-app git URL, creates the workspace, clones the app, makes a venv, runs `west init -l` + `west update`, installs Zephyr's Python deps, and symlinks `activate.sh` + `tools/`. Safe to `curl ... | bash`. |
| `activate.sh` | Activates the workspace's `.venv` and exports `ZEPHYR_BASE` / `ZEPHYR_SDK_INSTALL_DIR`. Source it from the workspace root. |
| `tools/flash.sh` | `west flash` wrapper that sources `activate.sh` first. Wired into CLion run configs. |
| `tools/gdb-server.sh` | Starts openocd as a GDB server on `:3333` for the Nucleo-H753ZI. Adjust the `-f board/...cfg` line for other boards. |
| `tools/serial-monitor.sh` | Opens the ST-Link VCP. Prefers `tio` / `picocom`, falls back to `stty + cat`. |

## Bootstrap a new workspace

```sh
# Local clone of this repo:
./new-workspace.sh ~/projects/foo-workspace https://github.com/me/foo.git

# Or one-shot from the published repo (after you've pushed it):
curl -sL https://raw.githubusercontent.com/Assar63/zephyr-workspace-tools/main/new-workspace.sh \
    | bash -s -- ~/projects/foo-workspace https://github.com/me/foo.git
```

`<app-repo-url>` must point at a Zephyr application that contains a
`west.yml` manifest at its root (T2 manifest-in-app topology).

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
