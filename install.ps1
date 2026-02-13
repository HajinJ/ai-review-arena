# AI Review Arena v2.1 - Installer (Windows PowerShell)
# Requires: Claude Code CLI, WSL or Git Bash (for shell scripts)

$ErrorActionPreference = "Stop"

$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
$PluginDir = Join-Path $ClaudeDir "plugins\ai-review-arena"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  AI Review Arena v2.1 - Windows Installer" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

# Check prerequisites
Write-Host "[1/5] Checking prerequisites..." -ForegroundColor Yellow

$claudeExists = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeExists) {
    Write-Host "  ERROR: Claude Code CLI not found." -ForegroundColor Red
    Write-Host "  Install: https://docs.anthropic.com/en/docs/claude-code"
    exit 1
}
Write-Host "  ✓ Claude Code CLI" -ForegroundColor Green

# Check for WSL or Git Bash (needed for shell scripts)
$wslExists = Get-Command wsl -ErrorAction SilentlyContinue
$bashExists = Get-Command bash -ErrorAction SilentlyContinue
if ($wslExists) {
    Write-Host "  ✓ WSL detected" -ForegroundColor Green
} elseif ($bashExists) {
    Write-Host "  ✓ Bash detected (Git Bash)" -ForegroundColor Green
} else {
    Write-Host "  ! WSL or Git Bash not found" -ForegroundColor Yellow
    Write-Host "    Some features (external model review, debate) require bash." -ForegroundColor Yellow
    Write-Host "    Core functionality (Claude-only mode) will still work." -ForegroundColor Yellow
    Write-Host "    Install WSL: wsl --install" -ForegroundColor Yellow
}

$jqExists = Get-Command jq -ErrorAction SilentlyContinue
if ($jqExists) {
    Write-Host "  ✓ jq" -ForegroundColor Green
} else {
    Write-Host "  ! jq not found (optional)" -ForegroundColor Yellow
}

# Create directories
Write-Host ""
Write-Host "[2/5] Creating directories..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $PluginDir | Out-Null
Write-Host "  ✓ $PluginDir" -ForegroundColor Green

# Copy plugin files
Write-Host ""
Write-Host "[3/5] Installing plugin files..." -ForegroundColor Yellow

if (Test-Path $PluginDir) {
    $existingFiles = Get-ChildItem $PluginDir -ErrorAction SilentlyContinue
    if ($existingFiles) {
        Write-Host "  ! Existing installation found, updating..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force $PluginDir
        New-Item -ItemType Directory -Force -Path $PluginDir | Out-Null
    }
}

$items = @(".claude-plugin", "agents", "commands", "config", "hooks", "scripts", "CLAUDE.md")
foreach ($item in $items) {
    $source = Join-Path $ScriptDir $item
    if (Test-Path $source) {
        $dest = Join-Path $PluginDir $item
        if (Test-Path $source -PathType Container) {
            Copy-Item -Recurse -Force $source $dest
        } else {
            Copy-Item -Force $source $dest
        }
        Write-Host "  ✓ $item" -ForegroundColor Green
    }
}

# Install ARENA-ROUTER.md
Write-Host ""
Write-Host "[4/5] Installing ARENA-ROUTER.md..." -ForegroundColor Yellow

$routerSource = Join-Path $ScriptDir "ARENA-ROUTER.md"
$routerDest = Join-Path $ClaudeDir "ARENA-ROUTER.md"

if (Test-Path $routerDest) {
    Write-Host "  ! ARENA-ROUTER.md already exists, backing up..." -ForegroundColor Yellow
    Copy-Item $routerDest "$routerDest.bak"
}
Copy-Item -Force $routerSource $routerDest
Write-Host "  ✓ $routerDest" -ForegroundColor Green

# Update CLAUDE.md
Write-Host ""
Write-Host "[5/5] Updating CLAUDE.md..." -ForegroundColor Yellow

$claudeMd = Join-Path $ClaudeDir "CLAUDE.md"
if (-not (Test-Path $claudeMd)) {
    Set-Content -Path $claudeMd -Value "# Claude Code Configuration`n"
    Write-Host "  ✓ Created new CLAUDE.md" -ForegroundColor Green
}

$content = Get-Content $claudeMd -Raw
if ($content -match "@ARENA-ROUTER\.md") {
    Write-Host "  ✓ @ARENA-ROUTER.md already referenced" -ForegroundColor Green
} else {
    Add-Content -Path $claudeMd -Value "`n@ARENA-ROUTER.md"
    Write-Host "  ✓ Added @ARENA-ROUTER.md to CLAUDE.md" -ForegroundColor Green
}

# Create cache directory
New-Item -ItemType Directory -Force -Path (Join-Path $PluginDir "cache") | Out-Null

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Note: Shell scripts require WSL or Git Bash on Windows."
Write-Host "  Core features (commands, agents, routing) work natively."
Write-Host ""
Write-Host "  Usage: Open any project with Claude Code and type naturally."
Write-Host ""
