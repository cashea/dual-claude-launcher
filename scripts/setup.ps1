# setup.ps1
# First-time setup for dual Claude Desktop launcher
# Run once after cloning the repo
#
#   .\scripts\setup.ps1                      # auto-detect Claude.exe
#   .\scripts\setup.ps1 -ClaudeExe "<path>"  # use an explicit path
#   .\scripts\setup.ps1 -Force               # overwrite an existing Instance 2 config

param(
    [string]$ClaudeExe,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "=== Dual Claude Launcher Setup ===" -ForegroundColor Cyan

# 1. Find current Claude exe
#    Order: -ClaudeExe param, running MSIX process, installed MSIX package.
#    The WindowsApps root is not listable without admin, so it is not scanned.
Write-Host "`nFinding Claude executable..." -ForegroundColor Yellow

if (-not $ClaudeExe) {
    # Filter on WindowsApps so the Claude Code CLI (also claude.exe) is not matched
    $ClaudeExe = Get-Process -Name "claude" -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -like "*\WindowsApps\*" } |
        Select-Object -First 1 -ExpandProperty Path
}

if (-not $ClaudeExe) {
    $pkg = Get-AppxPackage -Name "Claude" -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($pkg) {
        $ClaudeExe = Get-ChildItem $pkg.InstallLocation -Filter "Claude.exe" -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }
}

if (-not $ClaudeExe -or -not (Test-Path $ClaudeExe)) {
    Write-Host "ERROR: Could not find Claude.exe." -ForegroundColor Red
    Write-Host "Start Claude Desktop and re-run, or pass -ClaudeExe <path>." -ForegroundColor Red
    exit 1
}
Write-Host "Found: $ClaudeExe" -ForegroundColor Green

# 2. Create Instance 2 profile dir
$instance2Dir = "$env:APPDATA\Claude-Instance2"
if (-not (Test-Path $instance2Dir)) {
    New-Item -ItemType Directory -Path $instance2Dir -Force | Out-Null
    Write-Host "Created: $instance2Dir" -ForegroundColor Green
} else {
    Write-Host "Exists: $instance2Dir" -ForegroundColor Green
}

# 3. Write Instance 2 config (existing config is kept unless -Force)
$configSrc = "$PSScriptRoot\..\config\claude_desktop_config.instance2.json"
$configDst = "$instance2Dir\claude_desktop_config.json"

if ((Test-Path $configDst) -and -not $Force) {
    Write-Host "Config exists, not overwritten: $configDst (use -Force to replace)" -ForegroundColor Yellow
} else {
    if (Test-Path $configDst) {
        $backup = "$configDst.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $configDst $backup
        Write-Host "Backed up existing config: $backup" -ForegroundColor Green
    }

    $cfg = Get-Content $configSrc -Raw | ConvertFrom-Json

    # Resolve uvx.exe for OfficeMCP instead of leaving the YOUR_USERNAME placeholder
    $uvx = Get-Command "uvx.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if (-not $uvx -and (Test-Path "$env:USERPROFILE\.local\bin\uvx.exe")) {
        $uvx = "$env:USERPROFILE\.local\bin\uvx.exe"
    }
    if ($uvx) {
        $cfg.mcpServers.officemcp.command = $uvx
        Write-Host "OfficeMCP uvx: $uvx" -ForegroundColor Green
    } else {
        Write-Host "WARNING: uvx.exe not found; set mcpServers.officemcp.command in $configDst" -ForegroundColor Yellow
    }

    # UTF-8 without BOM; Set-Content -Encoding UTF8 on PS 5.1 adds a BOM that breaks JSON.parse
    [System.IO.File]::WriteAllText($configDst, ($cfg | ConvertTo-Json -Depth 10))
    Write-Host "Config written to Instance 2" -ForegroundColor Green
}

# 4. Create desktop shortcuts (GetFolderPath honors OneDrive Desktop redirection)
$desktop = [Environment]::GetFolderPath("Desktop")
$workDir = Split-Path $ClaudeExe -Parent
$sh = New-Object -ComObject WScript.Shell

$sc1 = $sh.CreateShortcut("$desktop\Claude Instance 1.lnk")
$sc1.TargetPath = $ClaudeExe
$sc1.Arguments = ""
$sc1.WorkingDirectory = $workDir
$sc1.Description = "Claude Desktop - Instance 1 (desktop-commander)"
$sc1.Save()
Write-Host "Shortcut created: $desktop\Claude Instance 1.lnk" -ForegroundColor Green

$sc2 = $sh.CreateShortcut("$desktop\Claude Instance 2.lnk")
$sc2.TargetPath = $ClaudeExe
$sc2.Arguments = "--user-data-dir=`"$instance2Dir`""
$sc2.WorkingDirectory = $workDir
$sc2.Description = "Claude Desktop - Instance 2 (desktop-commander-2)"
$sc2.Save()
Write-Host "Shortcut created: $desktop\Claude Instance 2.lnk" -ForegroundColor Green

Write-Host "`n=== Setup complete ===" -ForegroundColor Cyan
Write-Host "1. Launch both shortcuts and confirm each window opens."
Write-Host "2. Instance 1 config is not modified by this script. Merge the mcpServers block from"
Write-Host "   config\claude_desktop_config.instance1.json into:"
Write-Host "   $env:LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\claude_desktop_config.json"
