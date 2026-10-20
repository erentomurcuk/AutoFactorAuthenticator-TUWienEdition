# AutoTISS2FA - one-shot Windows setup + build script.
#
# Designed for a FRESH Windows machine: installs everything needed (Git,
# Rust stable-msvc, Visual Studio Build Tools with the VC++ workload, Inno
# Setup 6.3+) via winget, then clones/pulls the repo, builds the native host
# and produces AutoTISS2FA-Setup.exe on the Desktop.
#
# Re-runnable: every step reports "already installed/done" and skips.
#
# Usage (regular PowerShell; UAC prompt appears):
#   powershell -ExecutionPolicy Bypass -File setup-and-build.ps1
# Options:
#   -SkipDeps          skip the toolchain steps (already set up machine)
#   -SourceDir X       build from an existing checkout instead of cloning
#   -Arm64             additionally build the aarch64 binary (installer
#                      AutoTISS2FA-Setup.exe then covers both architectures);
#                      without it the installer is x64-only
#
# NOTE: inno-setup.iss requires Inno Setup 6.3+ ('x64compatible', IsARM64) -
# winget installs a current 6.x, which is fine. The packaging step finds a
# per-user install at %LOCALAPPDATA%\Programs\Inno Setup 6 as well.

#Requires -RunAsAdministrator
param(
  [switch]$SkipDeps,
  [switch]$Arm64,
  [string]$SourceDir,
  [string]$RepoUrl = "https://github.com/erentomurcuk/AutoFactorAuthenticator-TUWienEdition.git",
  [string]$CloneDir = "$env:USERPROFILE\src\TUWien-Auto-2FA"
)

$ErrorActionPreference = "Stop"

function Stage($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Have($id) {
  winget list --id $id -e --accept-source-agreements *> $null
  return ($LASTEXITCODE -eq 0)
}

# --- 1) winget itself ---------------------------------------------------------
Stage "winget availability"
try { Get-Command winget | Out-Null } catch {
  Write-Error "winget not found. Install 'App Installer' from the Microsoft Store and re-run."
}

if (-not $SkipDeps) {
  # --- 2) Git ---------------------------------------------------------------
  Stage "Git"
  if (Have "Git.Git") { Write-Host "Git: already installed" }
  else {
    winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) { Write-Error "Git install failed" }
  }
  $env:Path = "$env:ProgramFiles\Git\cmd;$env:ProgramFiles\Git\bin;$env:Path"

  # --- 3) Rust (stable, MSVC host) ------------------------------------------
  Stage "Rustup + stable-msvc toolchain"
  $rustup = "$env:USERPROFILE\.cargo\bin\rustup.exe"
  if (Test-Path $rustup) { Write-Host "Rustup: already installed" }
  else {
    winget install --id Rustlang.Rustup -e --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) { Write-Error "Rustup install failed" }
  }
  $env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"
  & $rustup default stable-x86_64-pc-windows-msvc
  & $rustup target add x86_64-pc-windows-msvc
  if ($Arm64) { & $rustup target add aarch64-pc-windows-msvc }

  # --- 4) Visual Studio Build Tools (the MSVC linker) ------------------------
  # The default rustup-msvc toolchain links with link.exe, which comes from
  # the "Desktop development with C++" workload's VC++ tools. It is a multi-GB
  # download and takes a while - that is normal.
  Stage "Visual Studio Build Tools (VC++ workload, several GB - be patient)"
  if (Have "Microsoft.VisualStudio.2022.BuildTools") {
    Write-Host "Build Tools: already installed (skipping workload check)"
  }
  else {
    # Earlier install that bailed out midway, plus the winget id check:
    $vsInstaller = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
    if (Test-Path $vsInstaller) {
      Write-Host "VS installer exists but the winget listing failed - running modify"
      & $vsInstaller modify --installPath "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools" `
        --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --quiet --norestart --wait
      if ($LASTEXITCODE -ne 0) { Write-Error "VS Build Tools workload install failed" }
    }
    else {
      winget install --id Microsoft.VisualStudio.2022.BuildTools -e `
        --accept-package-agreements --accept-source-agreements `
        --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
      if ($LASTEXITCODE -ne 0) { Write-Error "VS Build Tools install failed" }
    }
  }

  # --- 5) Inno Setup (6.3+) --------------------------------------------------
  Stage "Inno Setup"
  if (Have "JRSoftware.InnoSetup") { Write-Host "Inno Setup: already installed" }
  else {
    winget install --id JRSoftware.InnoSetup -e --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) { Write-Error "Inno Setup install failed" }
  }
}

# PATH extensions also help when deps were installed in a previous run of
# this script but were not yet visible in the current session.
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:ProgramFiles\Git\cmd;$env:Path"

# --- 6) Source -----------------------------------------------------------------
Stage "Source tree"
if (-not $SourceDir) {
  if (Test-Path "$CloneDir\.git") {
    git -C $CloneDir pull --ff-only origin main
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "pull failed; keeping the existing checkout as-is"
    }
    $SourceDir = $CloneDir
  }
  else {
    # Git Credential Manager opens a browser sign-in when the repo is private.
    git clone $RepoUrl $CloneDir
    if ($LASTEXITCODE -ne 0) {
      Write-Error @"
Clone failed. If the repo is private:
  - either sign in once with Git Credential Manager (it opens in a browser),
  - or download the source as a zip and re-run with -SourceDir <extracted path>.
"@
    }
    $SourceDir = $CloneDir
  }
}
Write-Host "Building from: $SourceDir"
$Commit = git -C $SourceDir rev-parse --short HEAD
Write-Host "Source commit: $Commit"

# --- 7) Build the native host ----------------------------------------------------
Stage "cargo build --release (x86_64-pc-windows-msvc)"
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
  Write-Error "cargo not found on PATH. Re-run WITHOUT -SkipDeps (or add %USERPROFILE%\.cargo\bin to PATH)."
}
Push-Location (Join-Path $SourceDir "native-host")
try {
  cargo build --release
  if ($LASTEXITCODE -ne 0) { Write-Error "cargo build --release failed" }

  if ($Arm64) {
    Stage "cargo build --release (aarch64-pc-windows-msvc)"
    cargo build --release --target aarch64-pc-windows-msvc
    if ($LASTEXITCODE -ne 0) { Write-Error "ARM64 build failed" }
  }
}
finally { Pop-Location }

# --- 8) Package with Inno Setup ---------------------------------------------------
# build-exe.ps1 stages the binaries under arch-specific names, writes
# README.txt and compiles inno-setup.iss. Without -Arm64 it never looks for
# the aarch64 binary, so the result is an x64-only installer.
Stage "Inno Setup packaging"
$buildExe = Join-Path $SourceDir "native-host\build\windows\build-exe.ps1"
if ($Arm64) {
  powershell -NoProfile -ExecutionPolicy Bypass -File $buildExe -Arm64
}
else {
  powershell -NoProfile -ExecutionPolicy Bypass -File $buildExe
}
if ($LASTEXITCODE -ne 0) { Write-Error "build-exe.ps1 failed" }

# --- 9) Deliver ---------------------------------------------------------------------
$Source = Join-Path $SourceDir "native-host\build\windows\AutoTISS2FA-Setup.exe"
if (-not (Test-Path $Source)) { Write-Error "Expected output $Source was not produced" }
$Dest = Join-Path $env:USERPROFILE "Desktop\AutoTISS2FA-Setup.exe"
Copy-Item $Source $Dest -Force

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Green
Write-Host "Installer copied to: $Dest"
Write-Host "Also kept at:        $Source"
Write-Host ""
Write-Host "Next steps on THIS machine:"
Write-Host "  1. Run the installer (it registers the native host and opens the console)"
Write-Host "  2. Install the .xpi extension in Firefox (about:addons - 'Install Add-on From File')"
Write-Host "  3. Click the AutoTISS2FA icon, paste your TOTP secret"
