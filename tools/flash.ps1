# Flash the current build via `west flash`.
# Wired into VSCode tasks.json and CLion run configs.

$ErrorActionPreference = 'Stop'

$Ws = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $Ws 'activate.ps1') | Out-Null

& west flash @args
exit $LASTEXITCODE
