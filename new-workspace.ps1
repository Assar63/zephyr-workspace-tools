<#
.SYNOPSIS
    Bootstrap a Zephyr T2 workspace from an app git repo (PowerShell port).

.DESCRIPTION
    Clones the app, creates a Python venv (uv if present, otherwise
    python+pip), runs west init/update, installs Zephyr Python deps,
    and copies activate.ps1 + tools\ from the tools repo into the
    workspace root.

    With -Ide, after the workspace is otherwise ready, looks for an
    init script in this order:
        1. <workspace>\<app>\scripts\ide-setup\<ide>-init.ps1  (project)
        2. <tools-repo>\ide-defaults\<ide>-init.ps1           (fallback)
    and invokes it with two args: the workspace dir and the cloned app
    dir.

.PARAMETER WorkspaceDir
    Directory to create for the new workspace.

.PARAMETER AppRepoUrl
    Git URL of the Zephyr app (must contain west.yml).

.PARAMETER ManifestSubdir
    Optional. Subdirectory under the workspace where the app is cloned.
    Defaults to the basename of the URL with .git stripped.

.PARAMETER Ide
    Optional. 'vscode' or 'clion'. Triggers the project's
    ide-setup\<ide>-init.ps1 if present.

.EXAMPLE
    .\new-workspace.ps1 -WorkspaceDir C:\dev\foo -AppRepoUrl https://github.com/me/foo.git
.EXAMPLE
    .\new-workspace.ps1 C:\dev\foo https://github.com/me/foo.git -Ide vscode

.NOTES
    Env vars TOOLS_REPO_URL and TOOLS_REPO_DIR override the defaults
    for the helper repo. Existing TOOLS_REPO_DIR is reused as-is.

    Unlike the bash bootstrap, this PowerShell version copies activate.ps1
    and tools\ into the workspace rather than symlinking, so creating
    symlinks on Windows doesn't require Developer Mode or admin. Re-run
    new-workspace.ps1 to refresh after the tools repo is updated.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$WorkspaceDir,
    [Parameter(Mandatory = $true, Position = 1)][string]$AppRepoUrl,
    [Parameter(Position = 2)][string]$ManifestSubdir = '',
    [ValidateSet('', 'vscode', 'clion')][string]$Ide = '',
    # Comma-separated short names: arm, arm64, riscv, or "all" (full SDK).
    # Off by default. Validation happens in Install-ZephyrSdk.
    [string]$Toolchain = ''
)

$ErrorActionPreference = 'Stop'

# In PS 7.3+ this surfaces native-command failures as terminating errors.
# Older PS just ignores it.
$PSNativeCommandUseErrorActionPreference = $true

$DefaultToolsRepoUrl = 'https://github.com/Assar63/zephyr-bootstrap.git'
$DefaultToolsRepoDir = Join-Path $env:USERPROFILE 'projects\zephyr-bootstrap'

$ToolsRepoUrl = if ($env:TOOLS_REPO_URL) { $env:TOOLS_REPO_URL } else { $DefaultToolsRepoUrl }
$ToolsRepoDir = if ($env:TOOLS_REPO_DIR) { $env:TOOLS_REPO_DIR } else { $DefaultToolsRepoDir }

function Log([string]$msg) { Write-Host "==> $msg" }

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$Cmd,
        [Parameter(ValueFromRemainingArguments)][string[]]$Arguments
    )
    & $Cmd @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Cmd $($Arguments -join ' ') failed with exit $LASTEXITCODE"
    }
}

# Host deps
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Missing required tool: git'
}

# Validate -Toolchain early so we don't get to a bad name after a 5-min west update.
if ($Toolchain -and $Toolchain -ne 'all') {
    foreach ($tc in $Toolchain.Split(',')) {
        if ($tc -notin @('arm', 'arm64', 'riscv')) {
            throw "Unknown -Toolchain entry: '$tc' (expected arm, arm64, riscv, or all)"
        }
    }
}

function Install-ZephyrSdk {
    param([string]$Req)

    $sdkVersionFile = Join-Path $WorkspaceDir 'zephyr\SDK_VERSION'
    if (-not (Test-Path $sdkVersionFile)) {
        throw "could not read $sdkVersionFile"
    }
    $sdkVersion = (Get-Content $sdkVersionFile).Trim()
    $sdkDir = Join-Path $env:USERPROFILE "zephyr-sdk-$sdkVersion"

    if (Test-Path $sdkDir) {
        Log "Zephyr SDK $sdkVersion already at $sdkDir; skipping install"
        return
    }

    if (-not (Get-Command 7z -ErrorAction SilentlyContinue)) {
        throw "-Toolchain on Windows requires 7-Zip on PATH (e.g. ``scoop install 7zip`` or download from 7-zip.org)"
    }

    $osarch = 'windows-x86_64'
    $baseUrl = "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v$sdkVersion"
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'zsdk-download.7z'

    Log "Installing Zephyr SDK $sdkVersion into $sdkDir"

    if ($Req -eq 'all') {
        Log '  downloading full SDK (large)'
        Invoke-WebRequest "$baseUrl/zephyr-sdk-${sdkVersion}_${osarch}.7z" -OutFile $tmp
        & 7z x -y -o"$env:USERPROFILE" $tmp | Out-Null
        Remove-Item $tmp
        Push-Location $sdkDir
        try { & cmd /c 'setup.cmd /h /c /t all' } finally { Pop-Location }
    } else {
        Log '  downloading minimal SDK'
        Invoke-WebRequest "$baseUrl/zephyr-sdk-${sdkVersion}_${osarch}_minimal.7z" -OutFile $tmp
        & 7z x -y -o"$env:USERPROFILE" $tmp | Out-Null
        Remove-Item $tmp

        $setupArgs = @('/h', '/c')
        foreach ($tc in $Req.Split(',')) {
            $tcFull = switch ($tc) {
                'arm'   { 'arm-zephyr-eabi' }
                'arm64' { 'aarch64-zephyr-elf' }
                'riscv' { 'riscv64-zephyr-elf' }
            }
            Log "  downloading toolchain: $tcFull"
            Invoke-WebRequest "$baseUrl/toolchain_gnu_${osarch}_${tcFull}.7z" -OutFile $tmp
            & 7z x -y -o"$sdkDir" $tmp | Out-Null
            Remove-Item $tmp
            $setupArgs += @('/t', $tcFull)
        }
        Push-Location $sdkDir
        try { & cmd /c "setup.cmd $($setupArgs -join ' ')" } finally { Pop-Location }
    }
}

$script:UseUv = [bool](Get-Command uv -ErrorAction SilentlyContinue)
if ($script:UseUv) {
    Log 'Using uv for venv and package installs'
} else {
    $py = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $py) { throw 'Missing required tool: python (or install uv)' }
    $script:PyExe = $py.Source
}

function New-Venv([string]$path) {
    if ($script:UseUv) { Invoke-Native uv venv $path }
    else { Invoke-Native $script:PyExe -m venv $path }
}

function Install-Pkg {
    param([Parameter(ValueFromRemainingArguments)][string[]]$PkgArgs)
    if ($script:UseUv) { Invoke-Native uv pip install --quiet @PkgArgs }
    else { Invoke-Native pip install --quiet @PkgArgs }
}

if (-not $ManifestSubdir) {
    # basename of URL with .git stripped
    $tail = ($AppRepoUrl -split '[\\/]')[-1]
    $ManifestSubdir = $tail -replace '\.git$', ''
}

Log "Creating workspace at $WorkspaceDir"
New-Item -ItemType Directory -Force -Path $WorkspaceDir | Out-Null
Set-Location $WorkspaceDir

if (Test-Path (Join-Path $ManifestSubdir '.git')) {
    Log "$ManifestSubdir already cloned; skipping"
} else {
    Log "Cloning $AppRepoUrl -> $ManifestSubdir"
    Invoke-Native git clone $AppRepoUrl $ManifestSubdir
}

if (-not (Test-Path .venv)) {
    Log 'Creating Python venv (.venv)'
    New-Venv .venv
}

. .\.venv\Scripts\Activate.ps1

if (-not $script:UseUv) { Install-Pkg --upgrade pip }
Install-Pkg west

if (Test-Path .west) {
    Log 'west already initialized; skipping init'
} else {
    Log "west init -l $ManifestSubdir"
    Invoke-Native west init -l $ManifestSubdir
}

Log 'west update (may take several minutes)'
Invoke-Native west update

Log 'Installing Zephyr Python deps'
Install-Pkg -r zephyr/scripts/requirements.txt

if ($Toolchain) {
    Install-ZephyrSdk -Req $Toolchain
}

if (-not (Test-Path $ToolsRepoDir)) {
    Log "Cloning workspace tools repo to $ToolsRepoDir"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ToolsRepoDir) | Out-Null
    Invoke-Native git clone $ToolsRepoUrl $ToolsRepoDir
}

if (-not (Test-Path 'activate.ps1')) {
    Log 'Copying activate.ps1 from tools repo'
    Copy-Item (Join-Path $ToolsRepoDir 'activate.ps1') -Destination 'activate.ps1'
}
if (-not (Test-Path 'tools')) {
    Log 'Copying tools\ from tools repo'
    Copy-Item (Join-Path $ToolsRepoDir 'tools') -Destination 'tools' -Recurse
}

if ($Ide) {
    $AppFull = Join-Path $WorkspaceDir $ManifestSubdir
    $ProjectInit = Join-Path $AppFull "scripts\ide-setup\$Ide-init.ps1"
    $DefaultInit = Join-Path $ToolsRepoDir "ide-defaults\$Ide-init.ps1"
    if (Test-Path $ProjectInit) {
        Log "Running project IDE init: $ProjectInit"
        & $ProjectInit $WorkspaceDir $AppFull
    } elseif (Test-Path $DefaultInit) {
        Log "No project IDE init found; using default: $DefaultInit"
        & $DefaultInit $WorkspaceDir $AppFull
    } else {
        Write-Warning "-Ide $Ide requested but no init script found (project nor default); skipping"
    }
}

@"

Workspace ready at: $WorkspaceDir

Next steps:
  cd $WorkspaceDir
  . .\activate.ps1
  west build $ManifestSubdir

Note: this script does NOT install the Zephyr SDK or board-specific host
tools (openocd, etc.). Install those separately for your target.
"@ | Write-Host
