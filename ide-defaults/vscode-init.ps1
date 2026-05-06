# Default VSCode init for Windows / PowerShell users -- used when the
# project doesn't ship its own scripts\ide-setup\vscode-init.ps1.
# Generates a multi-root .code-workspace at the workspace root and a
# .vscode\tasks.json with build/flash/monitor tasks. Existing files are
# never overwritten.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$WorkspaceDir,
    [Parameter(Mandatory = $true, Position = 1)][string]$AppDir
)

$ErrorActionPreference = 'Stop'

$AppName = Split-Path -Leaf $AppDir

$VscodeDir = Join-Path $WorkspaceDir '.vscode'
New-Item -ItemType Directory -Force -Path $VscodeDir | Out-Null

# Pick activate / tools script extensions based on what's actually present.
$ActivateScript = if (Test-Path (Join-Path $WorkspaceDir 'activate.ps1')) { 'activate.ps1' } else { 'activate.sh' }
$ToolsExt = if (Test-Path (Join-Path $WorkspaceDir 'tools\flash.ps1')) { 'ps1' } else { 'sh' }

$CodeWorkspace = Join-Path $WorkspaceDir "$AppName.code-workspace"
if (Test-Path $CodeWorkspace) {
    Write-Host "  $CodeWorkspace already exists; leaving alone"
} else {
    $folders = [System.Collections.Generic.List[object]]::new()
    $folders.Add([ordered]@{ name = $AppName; path = $AppName })
    $folders.Add([ordered]@{ name = 'workspace'; path = '.' })
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    [void]$seen.Add($AppName)
    [void]$seen.Add('workspace')

    $westOut = $null
    Push-Location $WorkspaceDir
    try {
        $westOut = & west list -f '{name} {path}' 2>$null
    } catch {
        # west not available or workspace not initialized -- keep base folders only
    } finally {
        Pop-Location
    }

    if ($westOut) {
        foreach ($line in $westOut) {
            $parts = $line -split '\s+', 2
            if ($parts.Count -ne 2) { continue }
            $name, $path = $parts
            if ($name -eq 'manifest' -or $seen.Contains($name)) { continue }
            if (-not (Test-Path (Join-Path $WorkspaceDir $path))) { continue }
            $folders.Add([ordered]@{ name = $name; path = $path })
            [void]$seen.Add($name)
        }
    }

    $cw = [ordered]@{
        folders = $folders.ToArray()
        settings = [ordered]@{
            'clangd.arguments' = @(
                "--compile-commands-dir=`${workspaceFolder:workspace}/build/$AppName"
                '--background-index'
                '--header-insertion=never'
                '--clang-tidy'
            )
            'files.exclude' = [ordered]@{
                build = $true; modules = $true; zephyr = $true
                '.venv' = $true; '.west' = $true
            }
            'files.watcherExclude' = [ordered]@{
                '**/build/**' = $true; '**/modules/**' = $true
                '**/zephyr/**' = $true; '**/.venv/**' = $true
            }
            'C_Cpp.intelliSenseEngine' = 'disabled'
        }
        extensions = [ordered]@{
            recommendations = @(
                'llvm-vs-code-extensions.vscode-clangd'
                'marus25.cortex-debug'
            )
        }
    }
    $cw | ConvertTo-Json -Depth 10 | Set-Content -Path $CodeWorkspace -Encoding UTF8
    Write-Host "  wrote $CodeWorkspace"
}

$TasksJson = Join-Path $VscodeDir 'tasks.json'
if (Test-Path $TasksJson) {
    Write-Host "  $TasksJson already exists; leaving alone"
} else {
    if ($ToolsExt -eq 'ps1') {
        $Shell = 'pwsh'
        $ShellArg = '-Command'
        $BuildCmd = ". `"`${workspaceFolder}/$ActivateScript`"; west build $AppName"
        $PristineCmd = ". `"`${workspaceFolder}/$ActivateScript`"; west build -p always $AppName"
    } else {
        $Shell = 'bash'
        $ShellArg = '-c'
        $BuildCmd = "source `"`${workspaceFolder}/$ActivateScript`" && west build $AppName"
        $PristineCmd = "source `"`${workspaceFolder}/$ActivateScript`" && west build -p always $AppName"
    }

    $tasks = [ordered]@{
        version = '2.0.0'
        tasks = @(
            [ordered]@{
                label = 'Build'; type = 'shell'; command = $Shell
                args = @($ShellArg, $BuildCmd)
                problemMatcher = @('$gcc')
                group = [ordered]@{ kind = 'build'; isDefault = $true }
            }
            [ordered]@{
                label = 'Pristine Build'; type = 'shell'; command = $Shell
                args = @($ShellArg, $PristineCmd)
                problemMatcher = @('$gcc')
            }
            [ordered]@{
                label = 'Flash'; type = 'shell'
                command = "`${workspaceFolder}/tools/flash.$ToolsExt"
                problemMatcher = @()
            }
            [ordered]@{
                label = 'Serial Monitor'; type = 'shell'
                command = "`${workspaceFolder}/tools/serial-monitor.$ToolsExt"
                problemMatcher = @()
                presentation = [ordered]@{ reveal = 'always'; panel = 'dedicated' }
            }
            [ordered]@{
                label = 'OpenOCD GDB Server'; type = 'shell'
                command = "`${workspaceFolder}/tools/gdb-server.$ToolsExt"
                isBackground = $true
                problemMatcher = [ordered]@{
                    pattern = @(
                        [ordered]@{ regexp = '.'; file = 1; location = 2; message = 3 }
                    )
                    background = [ordered]@{
                        activeOnStart = $true
                        beginsPattern = 'Open On-Chip Debugger'
                        endsPattern = 'Listening on port'
                    }
                }
            }
        )
    }
    $tasks | ConvertTo-Json -Depth 10 | Set-Content -Path $TasksJson -Encoding UTF8
    Write-Host "  wrote $TasksJson"
}

@"

VSCode default setup ready.

  Open this file in VSCode (NOT the directory):
    $CodeWorkspace

  Recommended extensions: clangd (code intel), Cortex-Debug (debugging).
  IntelliSense is disabled by design -- clangd handles indexing using the
  build's compile_commands.json.
"@ | Write-Host
