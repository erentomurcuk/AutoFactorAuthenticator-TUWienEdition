# Auto Factor Authenticator

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
        ▼  get_code — never the seed
Rust Native Host → OS Keychain
        │  HMAC-SHA1 TOTP (RFC 6238), generated in Rust
        ▼  returns { code: "123456", ttl: seconds }
Background Script
        │
        ▼  fills the code in
Content Script  ←  you still hit submit yourself
```

Key properties:

- Your TOTP seed **never leaves your machine** — and since 1.2, **Firefox
  never sees it at all**. The seed is stored in your OS keychain (Apple
  Keychain, Windows Credential Manager, or the Linux Secret Service providers
  — GNOME Keyring, KDE Wallet, KeePassXC) via the Rust native-messaging host,
  which generates the RFC 6238 codes itself. The extension only receives a
  finished 6-digit code plus its seconds-to-expiry.
- Nothing is sent anywhere: no cloud, no telemetry, no network access at all.
  The extension's `connect-src 'none'` CSP forbids even it from opening a
  connection.
- The keyring entry is namespaced per variant (`AutoTISS2FA`), so site-variant
  forks can coexist on one machine. Upgrading from the pre-1.2 name
  (`TU Wien Auto 2FA`) transparently cleans up the old entry.

## Upgrading from a pre-1.2 version

Update by **fully uninstalling, then installing the new version** — an in-place
upgrade is not supported:

1. Remove the seed first if you want a clean slate: open the extension popup →
   *Remove Seed* (or skip this; the keychain entry under the old name is
   deleted by the new uninstaller).
2. Uninstall the old native host and uninstall/remove the old extension in
   Firefox.
   - macOS: open **TU Wien 2FA.app** → *Uninstall* → remove the app.
   - Windows: *Settings → Apps → TU Wien Auto 2FA → Uninstall*.
   - Linux: `sudo dpkg -r tuwien-auto-2fa` / `sudo rpm -e tuwien-auto-2fa`,
     or `./TUWien-Auto-2FA-x86_64.AppImage --uninstall` for the AppImage.
3. Install the 1.2.1 package (per-OS instructions below) and the fresh `.xpi`
   (it is a *new* add-on — a new ID — so it installs as a separate entry).
4. Re-paste your TOTP seed in the popup once.

Why a full reinstall: 1.2 renames the identity of everything (extension ID,
native-messaging host name, keyring service; and the Windows registration was
written incorrectly in 1.1), so the old host is not compatible with the new
extension ID and vice versa. On Windows this reinstall is what fixes the
"app installed but the extension does not see it" bug.

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
sudo dpkg -i autotiss2fa_1.2.1_amd64.deb
```

**Fedora / RHEL**

```bash
sudo rpm -i autotiss2fa-1.2.1-1.x86_64.rpm
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
pnpm run lint      # must stay at 0 errors / 0 warnings
pnpm run build     # → web-ext-artifacts/autotiss2fa-1.2.1.xpi
```

The artifact is an ordinary ZIP named `.xpi`; the filename template
`autotiss2fa-{version}.xpi` takes the version from `extension/manifest.json`,
so it cannot drift from the release.

#### Load it locally

Unsigned builds install **temporarily** only (they disappear when Firefox
restarts):

```bash
open -a Firefox "about:debugging#/runtime/this-firefox"
```

Then **Load Temporary Add-on...** → pick `extension/manifest.json` (or the
built `.xpi`). For a permanent unsigned install you need Firefox Developer
Edition / Nightly with `xpinstall.signatures.required = false` in
`about:config`, then `about:addons` → gear → **Install Add-on From File...**.

#### Submit for signing / AMO approval

1. Create API credentials at
   <https://addons.mozilla.org/developers/addon/api/key/> (JWT issuer + secret)
   and drop them into `.env` in the repo root — it is git-ignored and loaded
   automatically by the sign scripts (fresh clone: `cp .env.example .env`):

   ```dotenv
   WEB_EXT_API_KEY=user:12345678:90
   WEB_EXT_API_SECRET=…
   ```

2. Upload the package; `listed` puts it in the human review queue:

   ```bash
   pnpm run sign          # = --channel=listed
   ```

   (Node 22.9+ is needed for the sign scripts, which use
   `--env-file-if-exists`; on older Node export the two variables and run
   `pnpm exec web-ext sign --source-dir extension --channel=listed` instead.)

   Add `--approval-timeout=0` (`pnpm run sign --approval-timeout=0`) to return
   immediately instead of blocking until a reviewer finishes. Use
   `pnpm run sign:unlisted` only for self-hosted/GitHub-release builds: it is
   signed instantly without review and is *not* installable from AMO.
   You can also upload `web-ext-artifacts/autotiss2fa-1.2.1.xpi` by hand at
   <https://addons.mozilla.org/developers/> — same file, no CLI needed.
3. The very first listed submission goes through the web form (name, summary,
   screenshots); later versions can be pushed with `pnpm run sign`.
4. After approval, install the AMO-signed `.xpi` permanently via
   `about:addons` → gear → **Install Add-on From File...**, or
   `open web-ext-artifacts/autotiss2fa-1.2.1.xpi`.

### 3. Save your TOTP seed

Click the extension icon in the toolbar, paste your base32 TOTP secret, hit
**Save**. Done. (Whitespace, dashes and `=` padding are cleaned automatically.)

## Build your own installers

```bash
# macOS DMG
cd native-host/build && bash build-packages.sh macos
# → native-host/build/macos/AutoTISS2FA.dmg

# Windows EXE (needs Inno Setup 6.3+, NOT 6.0-6.2: the .iss uses
# 'x64compatible' and, for the dual-arch build, IsARM64)
cd native-host/build && bash build-packages.sh windows
# → native-host/build/windows/AutoTISS2FA-Setup.exe   (x64 only)

# ...or directly, from Windows (PowerShell):
#   powershell -ExecutionPolicy Bypass -File native-host/build/windows/build-exe.ps1
#   powershell -ExecutionPolicy Bypass -File native-host/build/windows/build-exe.ps1 -Arm64
# The x64-only build needs just the x86_64 host binary; -Arm64 / --arm64
# additionally ships the aarch64 binary (requires building that target).

# Linux packaging
cd native-host/build && bash build-packages.sh linux
# → autotiss2fa_1.2.1_amd64.deb, autotiss2fa-1.2.1-1.x86_64.rpm,
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
| In memory | The seed never enters Firefox. The background page holds only the finished 6-digit code (and its TTL); the host computes codes one call at a time |
| Network | Nothing is sent anywhere; the CSP blocks outbound connections |
| Keyring delete | `--delete-credential` removes both the current and the pre-1.2 service name |

## Roadmap / TODO

- **Microsoft SSO support** for TU Wien mail (login.microsoftonline.com MFA) —
  under evaluation; a follow-up variant or a shared engine within this one.
- **Site-agnostic fork** for arbitrary websites is intentionally a separate
  project, not a feature of this one.

Done in 1.2: **host-side TOTP generation** — the seed no longer leaves the
native host at all; Firefox only receives finished 6-digit codes ("How it
works" above).

## Notes

Support of AI was used on this project.

## License

MIT — see `LICENSE`. Not an official TU Wien tool; no security audit; provided
AS IS.
