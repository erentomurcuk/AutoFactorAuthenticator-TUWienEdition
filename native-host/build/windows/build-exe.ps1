# TU Wien 2FA — Windows EXE installer build script
# Requires: Inno Setup 6 installed

$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
$NativeHostDir = Split-Path $ScriptDir -Parent
$ProjectRoot = Split-Path $NativeHostDir -Parent

# Find Windows binary
$BinaryPaths = @(
    "$NativeHostDir\target\x86_64-pc-windows-msvc\release\tuwien-2fa-native.exe",
    "$NativeHostDir\target\x86_64-pc-windows-gnu\release\tuwien-2fa-native.exe",
    "$NativeHostDir\target\release\tuwien-2fa-native.exe"
)

$Binary = $null
foreach ($path in $BinaryPaths) {
    if (Test-Path $path) {
        $Binary = $path
        break
    }
}

if (-not $Binary) {
    Write-Error "Windows binary not found. Build with one of:"
    Write-Error "  cargo xwin build --release --target x86_64-pc-windows-msvc"
    Write-Error "  cargo build --release --target x86_64-pc-windows-gnu"
    exit 1
}

# Stage files
Copy-Item $Binary "$ScriptDir\tuwien-2fa-native.exe" -Force
Copy-Item "$ScriptDir\launcher.bat" "$ScriptDir\launcher.bat" -Force

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
