# TU Wien Auto 2FA

A Firefox extension that auto-fills the 2FA code when you log into TU Wien.

> **Disclaimer:** This is *not* an official TU Wien tool. It's a side project, provided AS IS. You're responsible for whatever happens when you use it.

Your TOTP secret never leaves your machine. It's stored in your OS keychain (Apple Keychain, KDE Wallet, GNOME Keyring, or Windows Credential Manager) via a tiny Rust native messaging host.

## How it works

```
TU Wien login page (idp.zid.tuwien.ac.at)
        │
        ▼  spots the #totp field
Content Script
        │
        ▼  asks for a TOTP code
Background Script
        │
        ▼  grabs the seed from the keychain
Rust Native Host → OS Keychain
        │
        ▼  generates TOTP (RFC 6238) with Web Crypto API
Background Script
        │
        ▼  fills the code in
Content Script  ←  you still hit submit yourself
```

## Requirements

- Firefox 128 or newer

## Install (quick way)

Each installer includes the native host. You still need to install the `.xpi` in Firefox separately.

### macOS

1. Grab `TUWien-Auto-2FA.dmg`.
2. Open it and drag **TU Wien 2FA.app** into **Applications**.
3. Launch the app, click **Install**.
4. In Firefox, go to `about:addons`, click the gear → **Install Add-on From File...**.
5. Pick the signed `tu_wien_auto_2fa-1.0.3.xpi`.
6. Click the extension icon and paste your TOTP secret.

### Windows

1. Grab `TUWien-Auto-2FA-Setup.exe`.
2. Run it (admin rights needed).
3. The launcher pops up — press **Y** to register with Firefox.
4. In Firefox, go to `about:addons`, click the gear → **Install Add-on From File...`.
5. Pick the signed `.xpi`.
6. Click the extension icon and paste your TOTP secret.

### Linux

**Debian / Ubuntu**
```bash
sudo dpkg -i tuwien-auto-2fa_1.0.3_amd64.deb
```

**Fedora / RHEL**
```bash
sudo rpm -i tuwien-auto-2fa-1.0.3-1.x86_64.rpm
```

**AppImage** (any distro)
```bash
chmod +x TUWien-Auto-2FA-x86_64.AppImage
./TUWien-Auto-2FA-x86_64.AppImage
```

After installing, launch **TU Wien 2FA** from your app menu, click **Install**, then install the `.xpi` in Firefox via `about:addons` → gear → **Install Add-on From File...**.

## Build from source

If you'd rather roll your own, or your platform doesn't have a pre-built package:

### 1. Native messaging host (Rust)

You need the Rust toolchain first:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

On Linux you also need `libsecret` development headers:

```bash
# Debian/Ubuntu
sudo apt install libsecret-1-dev
# Fedora
sudo dnf install libsecret-devel
# Arch
sudo pacman -S libsecret
```

Then build and register the native host:

```bash
cd native-host
bash install.sh
```

This builds the binary, copies the native messaging manifest into the right place so Firefox can find it. Restart Firefox if it was running.

### 2. Firefox extension

```bash
pnpm install
pnpm run dev     # runs extension in a temporary Firefox profile
```

Or load it manually from `about:debugging#/runtime/this-firefox` → pick `extension/manifest.json`.

### 3. Save your TOTP seed

Click the extension icon in the toolbar, paste your base32 TOTP secret, hit **Save to Keychain**. Done.

## Build platform installers

Want to make the DMG / EXE / DEB / RPM / AppImage yourself? Here's how.

### Prerequisites

**All platforms:**
- Rust toolchain (see above)
- `pnpm` (for the extension build)

**macOS:**
- Xcode Command Line Tools: `xcode-select --install`

**Windows:**
- Visual Studio Build Tools with the C++ workload + Rust Cargo
- Inno Setup 6 from [jrsoftware.org](https://jrsoftware.org/isdl.php)
- PowerShell (comes with Windows 10+)

**Linux:**
- `libsecret` headers (see above)
- Debian/Ubuntu: `sudo apt install dpkg-dev`
- Fedora/RHEL: `sudo dnf install rpm-build`
- AppImage: `wget` (usually pre-installed)

### Extension

```bash
pnpm install
pnpm run build
```

This drops an unsigned `.zip` in `web-ext-artifacts/`. For a signed `.xpi` (permanent install without developer warnings):

```bash
pnpm exec web-ext sign \
  --source-dir extension \
  --channel unlisted \
  --api-key=YOUR_JWT_ISSUER \
  --api-secret=YOUR_JWT_SECRET
```

Get API credentials at [addons.mozilla.org](https://addons.mozilla.org/en-US/developers/addon/api/key/).

### macOS — DMG

```bash
cd native-host/build
bash build-packages.sh macos
```

Or step by step:

```bash
# 1. Build a universal binary (x86_64 + arm64) and wrap it in a .app
cd native-host/build/macos
bash create-app-bundle.sh

# 2. Turn the .app into a DMG
bash create-dmg.sh
```

The DMG lands in `native-host/build/macos/TUWien-Auto-2FA.dmg`.

### Windows — EXE installer

```powershell
cd native-host\build\windows
powershell -ExecutionPolicy Bypass -File build-exe.ps1
```

Under the hood this:
1. Looks for the Rust cross-compiled binary at `target/x86_64-pc-windows-msvc/release/tuwien-2fa-native.exe`
2. Bundles it with `inno-setup.iss` into an installer
3. Outputs `TUWien-Auto-2FA-Setup.exe` in the same directory

Cross-compile from Linux/macOS:

```bash
cargo xwin build --release --target x86_64-pc-windows-msvc
```

Or build natively on Windows with the MSVC toolchain:

```bash
cargo build --release
```

### Linux — DEB, RPM, and AppImage

**All three at once:**

```bash
cd native-host/build
bash build-packages.sh linux
```

**Or one at a time:**

```bash
# First build the Linux binary
cd native-host
cargo build --release

# DEB package
cd build/linux
bash build-deb.sh        # needs dpkg-deb

# RPM package
bash build-rpm.sh        # needs rpmbuild

# AppImage
bash build-appimage.sh   # downloads linuxdeploy automatically
```

Artifacts land in `native-host/build/linux/`:
- `tuwien-auto-2fa_1.0.3_amd64.deb`
- `tuwien-auto-2fa-1.0.3-1.x86_64.rpm`
- `TUWien-Auto-2FA-x86_64.AppImage`

**Build everything for all platforms:**

```bash
cd native-host/build
bash build-packages.sh all
```

## Usage

Once set up, just visit `https://idp.zid.tuwien.ac.at/` and log in. When the 2FA field shows up, the extension fills the code automatically. You still click the submit button yourself.

## Uninstall

- **macOS:** Open **TU Wien 2FA.app** from Applications and click **Uninstall**.
- **Windows:** Go to **Settings > Apps > TU Wien Auto 2FA > Uninstall**.
- **Linux deb/rpm:** `sudo dpkg -r tuwien-auto-2fa` or `sudo rpm -e tuwien-auto-2fa`.
- **Linux AppImage:** `./TUWien-Auto-2FA-x86_64.AppImage --uninstall`.
- **Source install:** `cd native-host && bash uninstall.sh`.

## Project structure

```
TUWEL-Auto-2FA/
├── extension/              # Firefox extension (plain JS, no bundler)
│   ├── manifest.json       # MV3 manifest
│   ├── background.js       # TOTP generation, talks to native host
│   ├── content_script.js   # Detects #totp on the login page
│   ├── popup/              # Popup UI
│   │   ├── popup.html
│   │   └── popup.js
│   └── icons/
├── native-host/            # Rust native messaging host
│   ├── src/main.rs         # stdin/stdout JSON protocol + keyring access
│   ├── Cargo.toml
│   ├── install.sh          # Build + register with Firefox
│   ├── uninstall.sh
│   ├── build/              # Installer builders per platform
│   │   ├── macos/
│   │   ├── windows/
│   │   └── linux/
│   └── scripts/
└── package.json            # web-ext config
```

## Security

| Layer | How it works |
|-------|-------------|
| At rest | TOTP seed in OS keychain (Apple Keychain / libsecret / Credential Manager) |
| In transit | Seed fetched via Native Messaging (stdin/stdout, only accessible to this extension) |
| In memory | Seed used only during TOTP generation, never saved in extension storage |
| Network | Nothing is sent anywhere. No cloud, no telemetry. |

## Notes
Support of AI was used on this project.

## License

UNLICENSED for now. Use at your own risk. I haven't audited this for security, and I'm not responsible if something breaks or data gets lost. You've been warned.
