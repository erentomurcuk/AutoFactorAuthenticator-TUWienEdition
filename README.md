# AutoTISS2FA

**AutoFactorAuthenticator — TU Wien variant.**

A Firefox extension that auto-fills the 2FA code on the TU Wien login
(`idp.zid.tuwien.ac.at`). This variant is deliberately TU Wien-only; a separate
fork handles arbitrary websites.

> **Disclaimer:** This is *not* an official TU Wien tool, and it has *not* been
> security-audited. It is provided AS IS (see `LICENSE`). You are responsible
> for whatever happens when you use it.

## How it works

```
TU Wien login page (idp.zid.tuwien.ac.at)
        │
        ▼  spots the TOTP field (#totp, with fallbacks)
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

Key properties:

- Your TOTP seed **never leaves your machine**. It is stored in your OS
  keychain (Apple Keychain, Windows Credential Manager, or the Linux Secret
  Service providers — GNOME Keyring, KDE Wallet, KeePassXC) via the Rust
  native-messaging host.
- Nothing is sent anywhere: no cloud, no telemetry, no network access at all.
  The extension's `connect-src 'none'` CSP forbids even it from opening a
  connection.
- The keyring entry is namespaced per variant (`AutoTISS2FA`), so site-variant
  forks can coexist on one machine. Upgrading from the pre-1.2 name
  (`TU Wien Auto 2FA`) transparently cleans up the old entry.

## Requirements

- Firefox 142 or newer (or a Chromium-compatible fork of this project — not a
  goal for this one).
- **Linux**: a Secret Service keyring daemon (GNOME Keyring, KDE Wallet or
  KeePassXC's Secret Service plugin) and `zenity` or `kdialog`.

## Install

Each installer includes the native host. You still need to install the `.xpi`
in Firefox separately.

### macOS

1. Grab `AutoTISS2FA.dmg` from the releases.
2. Open it and drag **AutoTISS2FA.app** into **Applications**.
3. First launch: right-click the app → **Open** (macOS Gatekeeper warns about
   unsigned apps; a one-time Open confirms). Click **Install** in the dialog.
4. In Firefox, `about:addons` → gear → **Install Add-on From File...** → pick
   the signed `.xpi`.
5. Click the extension icon and paste your TOTP secret.

### Windows

1. Grab `AutoTISS2FA-Setup.exe` from the releases.
2. Run it (admin rights needed) — the console asks to register the host, press
   **Y**.
3. In Firefox, `about:addons` → gear → **Install Add-on From File...** → pick
   the signed `.xpi`.
4. Click the extension icon and paste your TOTP secret.

> **Note for 1.1 users:** Windows 1.1 installers wrote the native-messaging
> manifest with raw backslashes inside the JSON `"path"` value, which is
> invalid JSON, so Firefox could not load the host ("app installed but the
> extension does not see it"). 1.2 fixes this. Reinstall the host and pasted
> seeds are unaffected (same keychain entry name).

### Linux

**Debian / Ubuntu**

```bash
sudo dpkg -i autotiss2fa_1.2.0_amd64.deb
```

**Fedora / RHEL**

```bash
sudo rpm -i autotiss2fa-1.2.0-1.x86_64.rpm
```

**AppImage** (any distro)

```bash
chmod +x AutoTISS2FA-x86_64.AppImage
./AutoTISS2FA-x86_64.AppImage        # registers with Firefox on first run
```

After installing, launch **AutoTISS2FA** from your app menu and click
**Install**, then install the `.xpi` in Firefox.

## Build from source

You need the Rust toolchain (and on Linux nothing beyond your distro's
default dev base for the D-Bus linker):

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### 1. Native messaging host (Rust)

```bash
cd native-host
bash install.sh     # builds + registers with Firefox for the current user
```

`install.sh` works on macOS (universal build), Linux, and Windows-from-Git-Bash.
It refuses to run without cargo and prints the reason.

### 2. Firefox extension

```bash
pnpm install
pnpm run dev       # runs the extension in a temporary Firefox profile
```

Or load it manually: `about:debugging#/runtime/this-firefox` → **Load
Temporary Add-on...** → pick `extension/manifest.json`.

### 3. Save your TOTP seed

Click the extension icon in the toolbar, paste your base32 TOTP secret, hit
**Save**. Done. (Whitespace, dashes and `=` padding are cleaned automatically.)

## Build your own installers

```bash
# macOS DMG
cd native-host/build && bash build-packages.sh macos
# → native-host/build/macos/AutoTISS2FA.dmg

# Windows EXE (needs Inno Setup 6.3+, NOT 6.0-6.2: the .iss uses the
# IsARM64 function and the boolean architecture list)
cd native-host/build && bash build-packages.sh windows
# → native-host/build/windows/AutoTISS2FA-Setup.exe   (x64 + ARM64 in one)

# Linux packaging
cd native-host/build && bash build-packages.sh linux
# → autotiss2fa_1.2.0_amd64.deb, autotiss2fa-1.2.0-1.x86_64.rpm,
#   AutoTISS2FA-x86_64.AppImage
```

Windows cross-compile from macOS/Linux:

```bash
cargo xwin build --release --target x86_64-pc-windows-msvc
cargo xwin build --release --target aarch64-pc-windows-msvc
```

## Uninstall

- **macOS:** open **AutoTISS2FA.app** → **Uninstall**.
- **Windows:** *Settings → Apps → AutoTISS2FA → Uninstall* (or the Start-menu
  entry → confirms → removes manifest, registry key, keychain seed).
- **Linux deb/rpm:** `sudo dpkg -r autotiss2fa` / `sudo rpm -e autotiss2fa`
  then run the installed app once and answer yes (drops the user's manifest +
  keyring seed).
- **Linux AppImage:** `./AutoTISS2FA-x86_64.AppImage --uninstall`.
- **Source install:** `cd native-host && bash uninstall.sh`.

## Project structure

```
AutoFactorAuthenticator/
├── extension/              # Firefox extension (plain JS, no bundler)
│   ├── manifest.json       # MV3 manifest (gecko id autotiss2fa@autofactorauthenticator)
│   ├── background.js       # TOTP generation, talks to native host
│   ├── content_script.js   # Finds the TOTP field on the login page
│   └── popup/              # Popup UI (seed setup / code display)
├── native-host/
│   ├── src/main.rs         # stdio JSON protocol + keyring access
│   ├── Cargo.toml
│   ├── install.sh          # Build + register with Firefox
│   ├── uninstall.sh
│   └── build/              # Platform installer builders
│       ├── macos/          # .app bundle + DMG
│       ├── windows/        # Inno Setup EXE (x64 + ARM64)
│       └── linux/          # DEB / RPM / AppImage
└── package.json            # web-ext scripts (dev/build/lint/sign)
```

## Security model

| Layer | How it works |
|-------|--------------|
| At rest | TOTP seed in the OS keychain under service name `AutoTISS2FA` |
| In transit | Native messaging over stdio, only to this extension id |
| In memory | Seed cached in the background page never longer than ~31 s, cleared on the window boundary |
| Network | Nothing is sent anywhere; the CSP blocks outbound connections |
| Keyring delete | `--delete-credential` removes both the current and the pre-1.2 service name |

## Roadmap / TODO

- **Microsoft SSO support** for TU Wien mail (login.microsoftonline.com MFA) —
  under evaluation; a follow-up variant or a shared engine within this one.
- **Host-side TOTP generation** — currently Firefox generates the 6-digit code
  from the seed fetched over native messaging; moving generation into the Rust
  host would mean Firefox never touches the seed at all (defense in depth).
- **Site-agnostic fork** for arbitrary websites is intentionally a separate
  project, not a feature of this one.

## Notes

Support of AI was used on this project.

## License

MIT — see `LICENSE`. Not an official TU Wien tool; no security audit; provided
AS IS.
