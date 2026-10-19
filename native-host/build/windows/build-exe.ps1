# Builds the AutoTISS2FA Windows installer with Inno Setup 6.3+.
# Checks for the host binary (x64 required, ARM64 optional), stages them under
# arch-specific names, drops README.txt next to them and compiles the .iss.
#
# NOTE: inno-setup.iss uses the IsARM64 support function and the boolean
# architecture list "x64compatible arm64" - both need Inno Setup 6.3 or newer.

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$NativeHostDir = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$ProjectRoot = Split-Path -Parent $NativeHostDir

$BinaryName = "autotiss2fa-native.exe"
$StagedX64 = Join-Path $ScriptDir "autotiss2fa-native-x64.exe"
$StagedArm64 = Join-Path $ScriptDir "autotiss2fa-native-arm64.exe"

# Clean stale staged binaries from an earlier run first - otherwise a binariy
# that was since deleted can be shipped by accident.
Remove-Item $StagedX64, $StagedArm64 -ErrorAction SilentlyContinue

$x64Paths = @(
  (Join-Path $NativeHostDir "target\x86_64-pc-windows-msvc\release\$BinaryName"),
  (Join-Path $NativeHostDir "target\x86_64-pc-windows-gnu\release\$BinaryName"),
  (Join-Path $NativeHostDir "target\release\$BinaryName")
)

$x64 = $x64Paths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $x64) {
  Write-Error @"
x64 binary not found. Build one of:
  cargo xwin build --release --target x86_64-pc-windows-msvc
  cargo build --release --target x86_64-pc-windows-gnu
  cargo build --release
"@
  exit 1
}

$arm64 = Join-Path $NativeHostDir "target\aarch64-pc-windows-msvc\release\$BinaryName"
if (Test-Path $arm64) {
  Copy-Item $arm64 $StagedArm64
  Write-Host "ARM64 binary found: $arm64"
} else {
  Write-Warning "ARM64 binary not found, skipping (installer will support x64 only)"
}

Copy-Item $x64 $StagedX64
$ReadmeTxt = @"
AutoTISS2FA - native messaging host for Firefox
================================================

This is NOT an official tool by TU Wien. Provided AS IS.
You are responsible for whatever happens when you use it.

The installer registers the native messaging host with Firefox and starts the
configuration console. Then:

  1. Install the .xpi extension in Firefox (about:addons > Install Add-on
     From File or search for it on the Builds channel).
  2. Click the extension icon and paste your TOTP secret.

Your TOTP seed is stored in Windows Credential Manager and never leaves this
computer.

Uninstall: Settings > Apps > AutoTISS2FA > Uninstall.
"@
Set-Content -Path (Join-Path $ScriptDir "README.txt") -Value $ReadmeTxt -Encoding UTF8

$isccCandidates = @("iscc.exe",
  "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
  "C:\Program Files (x86)\Inno Setup 6\iscc.exe",
  "C:\Program Files\Inno Setup 6\ISCC.exe",
  "C:\Program Files\Inno Setup 6\iscc.exe")
$iscc = $isccCandidates | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
if (-not $iscc) {
  Write-Error "Inno Setup compiler (iscc) not found. Install Inno Setup 6.3+ from https://jrsoftware.org/isdl.php"
  exit 1
}

& $iscc (Join-Path $ScriptDir "inno-setup.iss")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Created: $(Join-Path $ScriptDir 'AutoTISS2FA-Setup.exe')"
