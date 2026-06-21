# TU Wien Auto 2FA

Firefox extension that automatically fills the Multi-Factor Authentication code
for TU Wien login.

> **Disclaimer:** This is **not** an official tool by TU Wien. It is a
> self-made project provided **AS IS**. You are responsible for any possible
> damages or problems arising from its use.

The TOTP seed is stored securely in your **OS keychain** (Apple Keychain /
KDE Wallet / GNOME Keyring / Windows Credential Manager) via a tiny Rust native
messaging host. It never leaves your device and is never sent to the cloud.

## How it works

```
TU Wien login page (idp.zid.tuwien.ac.at)
       │
       ▼  detects #totp input field
Content Script
       │
       ▼  requests TOTP code
Background Script
       │
       ▼  retrieves seed via Native Messaging
Rust Native Host → OS Keychain
       │
       ▼  generates TOTP (RFC 6238) via Web Crypto API
Background Script
       │
       ▼  fills the code
Content Script (user clicks submit manually)
```

## Prerequisites

- **Firefox** 128 or later

## Installation

### Quick install (recommended)

Each installer bundles the native host. The Firefox extension must be installed
separately from the signed `.xpi` file.

#### macOS

1. Download `TUWien-Auto-2FA.dmg`.
2. Open the DMG and drag **TU Wien 2FA.app** to your **Applications** folder.
3. Launch **TU Wien 2FA.app** and click **Install** in the dialog.
4. In Firefox, open `about:addons`, click the gear icon, and choose **Install Add-on From File...**.
5. Select the signed `tu_wien_auto_2fa-1.0.3.xpi` file.
6. Click the extension icon and paste your TOTP secret key.

#### Windows

1. Download `TUWien-Auto-2FA-Setup.exe`.
2. Run the installer (requires administrator rights).
3. After installation, the launcher opens automatically. Press **Y** to register with Firefox.
4. In Firefox, open `about:addons`, click the gear icon, and choose **Install Add-on From File...**.
5. Select the signed `tu_wien_auto_2fa-1.0.3.xpi` file.
6. Click the extension icon and paste your TOTP secret key.

#### Linux

**Debian / Ubuntu**
```bash
sudo dpkg -i tuwien-auto-2fa_1.0.3_amd64.deb
```

**Fedora / RHEL**
```bash
sudo rpm -i tuwien-auto-2fa-1.0.3-1.x86_64.rpm
```

**AppImage**
```bash
chmod +x TUWien-Auto-2FA-x86_64.AppImage
./TUWien-Auto-2FA-x86_64.AppImage
```

After installation, launch **TU Wien 2FA** from your applications menu and click **Install** in the dialog.

Then in Firefox, open `about:addons`, click the gear icon, and choose **Install Add-on From File...**.
Select the signed `tu_wien_auto_2fa-1.0.3.xpi` file.

### Build & install from source (developers)

If you prefer to build everything yourself, or if no pre-built package exists for your system:

1. Install the Rust toolchain:
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```
2. On Linux, install `libsecret` development headers:
   ```bash
   # Debian/Ubuntu
   sudo apt install libsecret-1-dev
   # Fedora
   sudo dnf install libsecret-devel
   ```
3. Build and install the native host:
   ```bash
   cd native-host
   bash install.sh
   ```
4. Install the extension temporarily:
   ```bash
   cd ..
   pnpm install
   pnpm run dev
   ```
   Or load `extension/manifest.json` manually at `about:debugging#/runtime/this-firefox`.

### Configure your TOTP seed

1. Click the extension icon in the toolbar
2. Paste your TOTP secret key (base32) into the text area
3. Click **Save to Keychain**
4. The seed is now stored in your OS keychain

## Usage

After configuration, visit `https://idp.zid.tuwien.ac.at/` and log in as usual.
When the 2FA code input field appears, the extension will automatically fill the TOTP code. You still need to click the login/submit button yourself.

## Uninstallation

- **macOS:** Open **TU Wien 2FA.app** from Applications and click **Uninstall**.
- **Windows:** Use **Settings > Apps > TU Wien Auto 2FA > Uninstall**. The uninstaller removes the registry key and your stored credential.
- **Linux deb/rpm:** `sudo dpkg -r tuwien-auto-2fa` or `sudo rpm -e tuwien-auto-2fa`.
- **Linux AppImage:** Run `./TUWien-Auto-2FA-x86_64.AppImage --uninstall`.
- **Source install:** `cd native-host && bash uninstall.sh`.

## Project structure

```
TUWEL-Auto-2FA/
├── extension/              # Firefox extension (plain JS, no bundler)
│   ├── manifest.json       # MV3 extension manifest
│   ├── background.js       # TOTP generation, native messaging bridge
│   ├── content_script.js   # Detects #totp field on TU Wien pages
│   ├── popup/              # Extension popup UI
│   │   ├── popup.html
│   │   └── popup.js
│   └── icons/              # Extension icons
── native-host/            # Rust native messaging host
│   ├── src/main.rs         # stdin/stdout JSON protocol + keyring
│   ├── Cargo.toml
│   ├── install.sh          # Build + install script
│   ├── uninstall.sh
│   ├── build/              # Platform installer build scripts
│   │   ├── macos/
│   │   ├── windows/
│   │   └── linux/
│   └── scripts/            # Shared manifest/cleanup helpers
└── package.json            # web-ext dev configuration
```

## Security

| Layer | Mechanism |
|-------|-----------|
| At rest | TOTP seed stored in OS keychain (Apple Keychain / libsecret / Credential Manager) |
| In transit | Seed retrieved via Native Messaging (stdin/stdout, only accessible to this extension) |
| In memory | Seed used only during TOTP generation, not persisted in extension storage |
| Extension | No data sent over network. No cloud. No telemetry. |

## Building for distribution

### Extension

You have two options:

**Option A: Use the pre-signed extension**

A signed `.xpi` is provided in `web-ext-artifacts/`. Install it directly in Firefox via `about:addons` → gear icon → "Install Add-on From File...".

**Option B: Build and sign yourself**

1. Build the extension:
   ```bash
   pnpm install
   pnpm run build
   ```
   This creates a `.zip` in `web-ext-artifacts/`.

2. Sign it with your Mozilla Add-on Developer credentials:
   ```bash
   pnpm exec web-ext sign \
     --source-dir extension \
     --channel unlisted \
     --api-key=YOUR_JWT_ISSUER \
     --api-secret=YOUR_JWT_SECRET
   ```
   Get your API key/secret at `https://addons.mozilla.org/en-US/developers/addon/api/key/`.

   This produces a signed `.xpi` in `web-ext-artifacts/` that you can install permanently.

### Platform installers (native host)

If you want to sign the installers yourself (e.g., notarize the macOS app or code-sign the Windows EXE), you must build them on the respective platform.

#### Prerequisites

**All platforms:**
- Rust toolchain: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`

**macOS:**
- Xcode Command Line Tools: `xcode-select --install`
- No additional dependencies

**Windows:**
- Visual Studio Build Tools (with C++ workload)
- Inno Setup 6: https://jrsoftware.org/isdl.php
- PowerShell (included with Windows 10+)

**Linux:**
- `libsecret` development headers:
  ```bash
  # Debian/Ubuntu
  sudo apt install libsecret-1-dev
  # Fedora/RHEL
  sudo dnf install libsecret-devel
  # Arch
  sudo pacman -S libsecret
  ```
- `dpkg-deb` (Debian/Ubuntu): `sudo apt install dpkg-dev`
- `rpmbuild` (Fedora/RHEL): `sudo dnf install rpm-build`
- `wget` (for AppImage): usually pre-installed

#### Build commands

**macOS**

```bash
cd native-host/build
bash build-packages.sh macos
```

**Windows** (run on Windows with PowerShell)

```powershell
cd native-host\build\windows
powershell -ExecutionPolicy Bypass -File build-exe.ps1
```

**Linux** (run on Linux)

```bash
cd native-host/build
bash build-packages.sh linux
```

Built artifacts are placed in `native-host/build/{macos,windows,linux}/`.

## License

Currently UNLICENSED. Use at your own risk. The code is given AS IS and may contain bugs or security issues. I have not audited it for security and do not take responsibility for any damage or data loss that may occur. You have been warned.