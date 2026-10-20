<#
.SYNOPSIS
    Build the AutoTISS2FA Windows installer with Inno Setup.

.DESCRIPTION
    Default: X64-ONLY installer.

      * requires target\x86_64-pc-windows-msvc\release\autotiss2fa-native.exe
        (or the -gnu / plain target\release fallback),
      * stages it as autotiss2fa-native-x64.exe,
      * compiles inno-setup.iss WITHOUT /DArm64, so the result carries a single
        64-bit host binary and AutoTISS2FA-Setup.exe installs on x64 Windows
        (ARM64 Windows runs it through x64 emulation).

    -Arm64 additionally needs the aarch64 binary and produces the
    dual-architecture installer (x64 + native ARM64).

    No ARM64 probing happens in the default path, so a machine that never
    built the aarch64 target no longer prints an "ARM64 binary not found"
    warning.

    Inno Setup 6.3+ is required for both modes: the .iss uses the
    'x64compatible' architecture identifier and, with -Arm64, IsARM64.

.PARAMETER Arm64
    Include the ARM64 host binary and build the dual-architecture installer.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build-exe.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build-exe.ps1 -Arm64
#>
param(
    [switch]$Arm64
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$NativeHostDir = Split-Path -Parent (Split-Path -Parent $ScriptDir)

$BinaryName = "autotiss2fa-native.exe"
$StagedX64 = Join-Path $ScriptDir "autotiss2fa-native-x64.exe"
$StagedArm64 = Join-Path $ScriptDir "autotiss2fa-native-arm64.exe"
$IssPath = Join-Path $ScriptDir "inno-setup.iss"
$SetupExe = Join-Path $ScriptDir "AutoTISS2FA-Setup.exe"

# Clean stale staged binaries from an earlier run first - otherwise a binary
# that was since deleted can be shipped by accident (and, for the x64-only
# build, a leftover arm64 file must not end up in the installer).
Remove-Item $StagedX64, $StagedArm64 -ErrorAction SilentlyContinue

$x64Paths = @(
    (Join-Path $NativeHostDir "target\x86_64-pc-windows-msvc\release\$BinaryName"),
    (Join-Path $NativeHostDir "target\x86_64-pc-windows-gnu\release\$BinaryName"),
    (Join-Path $NativeHostDir "target\release\$BinaryName")
)

$x64 = $x64Paths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $x64) {
    [Console]::Error.WriteLine(@"
x64 host binary not found. Build one of:
  cargo build --release
  cargo build --release --target x86_64-pc-windows-gnu
  cargo xwin build --release --target x86_64-pc-windows-msvc

(from native-host\, or run setup-and-build.ps1 which does this for you)
"@)
    exit 1
}

Copy-Item -LiteralPath $x64 -Destination $StagedX64
Write-Host "x64 binary:    $x64"

if ($Arm64) {
    $arm64Path = Join-Path $NativeHostDir "target\aarch64-pc-windows-msvc\release\$BinaryName"
    if (-not (Test-Path -LiteralPath $arm64Path)) {
        [Console]::Error.WriteLine(@"
-Arm64 was requested but the ARM64 host binary is missing:
  $arm64Path

Build it first:
  rustup target add aarch64-pc-windows-msvc
  cargo build --release --target aarch64-pc-windows-msvc

Or drop -Arm64 to build the x64-only installer.
"@)
        exit 1
    }
    Copy-Item -LiteralPath $arm64Path -Destination $StagedArm64
    Write-Host "ARM64 binary:  $arm64Path"
}
else {
    Write-Host "ARM64 binary:  not included (x64-only installer; use -Arm64 for dual-arch)"
}

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

# --- locate ISCC --------------------------------------------------------------
# Inno Setup's own installer (and the winget package JRSoftware.InnoSetup) is
# PER-USER by default and lands in %LOCALAPPDATA%\Programs\Inno Setup 6, which
# is neither on PATH nor under Program Files. Hence the wide search below.
function Find-Iscc {
    $candidates = New-Object System.Collections.Generic.List[string]

    if ($env:ISCC) { $candidates.Add($env:ISCC) }

    $cmd = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { $candidates.Add($cmd.Source) }

    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"))
    }
    if (${env:ProgramFiles(x86)}) {
        $candidates.Add((Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"))
    }
    if ($env:ProgramFiles) {
        $candidates.Add((Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"))
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }

    # Registry fallback: Inno Setup records its install directory here.
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1"
    )
    foreach ($key in $uninstallKeys) {
        $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($props -and $props."Inno Setup: App Path") {
            $candidate = Join-Path $props."Inno Setup: App Path" "ISCC.exe"
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }

    # Last resort: per-user programs directory.
    if ($env:LOCALAPPDATA) {
        $programs = Join-Path $env:LOCALAPPDATA "Programs"
        if (Test-Path -LiteralPath $programs) {
            $hit = Get-ChildItem -Path $programs -Filter "ISCC.exe" -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }

    return $null
}

$iscc = Find-Iscc
if (-not $iscc) {
    [Console]::Error.WriteLine(@"
Inno Setup compiler (ISCC.exe) not found.

Install Inno Setup 6.3 or newer, then re-run this script:
  winget install --id JRSoftware.InnoSetup -e --accept-package-agreements --accept-source-agreements

(or download it from https://jrsoftware.org/isdl.php)

Already installed somewhere unusual? Point this script at it:
  `$env:ISCC = 'D:\Tools\Inno Setup 6\ISCC.exe'
"@)
    exit 1
}
Write-Host "ISCC:          $iscc"

# Refuse to compile with an ancient Inno Setup: 'x64compatible' needs 6.3+.
# Version detection is best-effort: some real 6.x installs report 0.0.0.0 (or
# nothing) through FileVersionInfo, so an unreadable version must warn and
# continue - ISCC itself still rejects a script that is too new for it.
function Get-IsccVersion([string]$Path) {
    try {
        $v = (Get-Item -LiteralPath $Path).VersionInfo.FileVersion
        if ($v -and ($v -match "^(\d+)\.(\d+)") -and ([int]$Matches[1] -gt 0)) { return $v }
    }
    catch { }

    # Fallback: the version Inno Setup records in its uninstall key.
    $keys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1"
    )
    foreach ($key in $keys) {
        $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        $appPath = $props."Inno Setup: App Path"
        if (-not $appPath) { continue }
        $registered = Join-Path $appPath "ISCC.exe"
        if (-not (Test-Path -LiteralPath $registered)) { continue }
        try {
            if ((Resolve-Path -LiteralPath $registered).Path -ne (Resolve-Path -LiteralPath $Path).Path) { continue }
        }
        catch { continue }
        if ($props.DisplayVersion) { return [string]$props.DisplayVersion }
        if ($props.InnoSetupVersion) { return [string]$props.InnoSetupVersion }
    }

    return $null
}

$fileVersion = Get-IsccVersion $iscc
if ($fileVersion -and ($fileVersion -match "^(\d+)\.(\d+)")) {
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    if (($major -lt 6) -or (($major -eq 6) -and ($minor -lt 3))) {
        Write-Error "Inno Setup $fileVersion at $iscc is too old - 6.3 or newer is required (x64compatible / IsARM64)."
        exit 1
    }
    Write-Host "ISCC version:  $fileVersion"
}
else {
    Write-Host "ISCC version:  unknown (FileVersionInfo reported '$fileVersion'; skipping the 6.3 check - ISCC will refuse the script if it is too old)" -ForegroundColor Yellow
}

# Remove a stale artifact first, so a failed compile cannot "succeed" by
# leaving yesterday's installer in place.
Remove-Item -LiteralPath $SetupExe -ErrorAction SilentlyContinue

# --- compile ------------------------------------------------------------------
# /O pins the output directory. Without it ISCC honours OutputDir from the
# .iss (we do not set one), and depending on how it is launched the artifact
# can land in the CWD or an Output\ subfolder instead of next to the script.
$issArgs = @("/O$ScriptDir")
if ($Arm64) { $issArgs += "/DArm64" }
$issArgs += $IssPath

& $iscc @issArgs
$isccExit = $LASTEXITCODE
if ($null -ne $isccExit -and $isccExit -ne 0) {
    Write-Error "Inno Setup compiler failed (exit code $isccExit)"
    exit $isccExit
}

if (-not (Test-Path -LiteralPath $SetupExe)) {
    $searched = @($ScriptDir, (Get-Location).Path, (Join-Path (Get-Location).Path "Output")) |
        Select-Object -Unique
    $found = @(
        foreach ($dir in $searched) {
            if (Test-Path -LiteralPath $dir) {
                Get-ChildItem -LiteralPath $dir -Filter "*.exe" -File -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty FullName
            }
        }
    )
    $foundText = if ($found.Count -gt 0) { $found -join "; " } else { "(none)" }
    [Console]::Error.WriteLine(@"
ISCC reported success but did not produce:
  $SetupExe

ISCC exit code:  $isccExit
Directories:     $($searched -join '; ')
.exe files seen: $foundText

If the file was written elsewhere, check the ISCC output above; otherwise
run ISCC directly to see the full log:
  & '$iscc' /O'$ScriptDir' '$IssPath'
"@)
    exit 1
}

$archLabel = if ($Arm64) { "x64 + ARM64" } else { "x64 only" }
Write-Host ""
Write-Host "Created: $SetupExe ($archLabel)"
