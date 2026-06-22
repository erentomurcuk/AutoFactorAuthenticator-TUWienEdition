# TU Wien 2FA — Windows EXE installer build script
# Requires: Inno Setup 6 installed
# Builds a single installer for x64 and ARM64.

$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
$NativeHostDir = Split-Path $ScriptDir -Parent
$ProjectRoot = Split-Path $NativeHostDir -Parent

# Find x64 binary
$x64Paths = @(
    "$NativeHostDir\target\x86_64-pc-windows-msvc\release\tuwien-2fa-native.exe",
    "$NativeHostDir\target\x86_64-pc-windows-gnu\release\tuwien-2fa-native.exe",
    "$NativeHostDir\target\release\tuwien-2fa-native.exe"
)

$x64Binary = $null
foreach ($path in $x64Paths) {
    if (Test-Path $path) {
        $x64Binary = $path
        break
    }
}

if (-not $x64Binary) {
    Write-Error "x64 binary not found. Build with one of:"
    Write-Error "  cargo xwin build --release --target x86_64-pc-windows-msvc"
    Write-Error "  cargo build --release --target x86_64-pc-windows-gnu"
    Write-Error "  cargo build --release (native x64 Windows only)"
    exit 1
}

# Find ARM64 binary (optional — installer will still build for x64 only if missing)
$arm64Paths = @(
    "$NativeHostDir\target\aarch64-pc-windows-msvc\release\tuwien-2fa-native.exe"
)

$arm64Binary = $null
foreach ($path in $arm64Paths) {
    if (Test-Path $path) {
        $arm64Binary = $path
        break
    }
}

# Stage files
Copy-Item $x64Binary "$ScriptDir\tuwien-2fa-native-x64.exe" -Force
if ($arm64Binary) {
    Copy-Item $arm64Binary "$ScriptDir\tuwien-2fa-native-arm64.exe" -Force
    Write-Host "ARM64 binary found — building dual-architecture installer."
} else {
    Write-Host "ARM64 binary not found — building x64-only installer."
}

$ReadmeContent = @"
TU Wien Auto 2FA
================

This is NOT an official tool by TU Wien. It is a self-made project
provided AS IS. You are responsible for any possible damages or problems.

Installation
------------
1. Run the installer.
2. After installation, the launcher will open automatically.
3. Click "Y" to register with Firefox.
4. Click the extension icon in Firefox and paste your TOTP secret key.

Uninstallation
--------------
Use Windows Settings > Apps > TU Wien Auto 2FA > Uninstall.
Your TOTP seed will be removed from Windows Credential Manager.
"@

Set-Content -Path "$ScriptDir\README.txt" -Value $ReadmeContent -Encoding UTF8

# Find Inno Setup
$InnoPaths = @(
    "iscc",
    "C:\Program Files (x86)\Inno Setup 6\iscc.exe",
    "C:\Program Files\Inno Setup 6\iscc.exe"
)

$Iscc = $null
foreach ($path in $InnoPaths) {
    try {
        & $path --version 2>$null
        $Iscc = $path
        break
    } catch {}
}

if (-not $Iscc) {
    Write-Error "Inno Setup compiler (iscc) not found."
    Write-Error "Install Inno Setup 6 from https://jrsoftware.org/isdl.php"
    exit 1
}

& $Iscc "$ScriptDir\inno-setup.iss"

Write-Host "Created: $ScriptDir\TUWien-Auto-2FA-Setup.exe"
