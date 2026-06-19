# TUWien Auto 2FA

Firefox extension that automatically fills the Multi-Factor Authentication code
for TUWien login.

The TOTP seed is stored securely in your **OS keychain** (Apple Keychain /
KDE Wallet / GNOME Keyring / Windows Credential Manager) via a tiny Rust native
messaging host. It never leaves your device and is never sent to the cloud.

## How it works

```
TUWien login page (idp.zid.tuwien.ac.at)
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
- **Rust toolchain** (to build the native host):
  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  ```
- **Linux only**: `libsecret` development headers:
  ```bash
  # Debian/Ubuntu
  sudo apt install libsecret-1-dev
  # Fedora
  sudo dnf install libsecret-devel
  ```

## Installation

### 1. Build & install the native host

```bash
cd native-host
bash install.sh
```

This builds the Rust binary and installs the Firefox native messaging manifest
to the correct location for your OS. On macOS it builds a universal binary
(Intel + Apple Silicon).

### 2. Install the extension temporarily (development)

```bash
# From the project root
pnpm install
pnpm run dev
```

Or manually:
1. Open `about:debugging#/runtime/this-firefox` in Firefox
2. Click **Load Temporary Add-on**
3. Select `extension/manifest.json`

### 3. Configure your TOTP seed

1. Click the extension icon (blue checkmark) in the toolbar
2. Paste your TOTP secret key (base32) into the text area
3. Click **Save to Keychain**
4. The seed is now stored in your OS keychain

## Usage

After configuration, visit `https://idp.zid.tuwien.ac.at/` and log in as usual.
When the 2FA code input field appears, the extension will automatically fill
the TOTP code. You still need to click the login/submit button yourself.

## Project structure

```
TUWien-Auto-2FA/
├── extension/              # Firefox extension (plain JS, no bundler)
│   ├── manifest.json       # MV3 extension manifest
│   ├── background.js       # TOTP generation, native messaging bridge
│   ├── content_script.js   # Detects #totp field on TUWien pages
│   ├── popup/              # Extension popup UI
│   │   ├── popup.html
│   │   └── popup.js
│   └── icons/              # Extension icons
├── native-host/            # Rust native messaging host
│   ├── src/main.rs         # stdin/stdout JSON protocol + keyring
│   ├── Cargo.toml
│   ├── install.sh          # Build + install script
│   └── uninstall.sh
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

```bash
pnpm run build
# Creates a .zip in web-ext-artifacts/
```

To sign the extension for permanent installation, use `web-ext sign` with
Mozilla Add-on Developer credentials.

## License

MIT
