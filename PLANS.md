# TU Wien Auto 2FA — Development Notes

## Current state

- [x] Extension scaffold (manifest.json, background.js, content_script.js, popup)
- [x] Rust native host (native-host/) — builds, installed, macOS universal binary
- [x] pnpm + web-ext@10.4.0 (0 vulnerabilities)
- [x] Git repo initialized
- [x] Renamed TUWEL → TU Wien throughout
- [x] Native host installed in ~/Library/Application Support/Mozilla/NativeMessagingHosts/ (current: hidden install via install.sh → will be replaced by proper OS-native installers)

## Architecture

```
Content Script (watches #totp) → Background (TOTP via Web Crypto) ↔ Native Messaging ↔ Rust binary ↔ OS Keychain
```

## Key identifiers

| Item | Value |
|------|-------|
| Extension ID | `tuwien-auto-2fa@tuwien.ac.at` |
| Native host name | `com.tuwien.2fa` |
| Rust binary name | `tuwien-2fa-native` |
| Manifest location | `~/Library/Application Support/Mozilla/NativeMessagingHosts/com.tuwien.2fa.json` |

## Next tasks

### [ ] Proper OS-native installers (replace hidden install method)

Current state: binary lives in project directory, installed via `install.sh` that writes a 
hidden Firefox native manifest. This is fragile — binary path changes if project moves, 
unsigned binary triggers Keychain prompts on every access, no proper uninstall path.

Goal: each OS gets a **proper installable package** with no hidden surprises.

#### macOS

**Package**: `.app` bundle delivered via `.dmg` disk image.

```
TU Wien 2FA.app/
├── Contents/
│   ├── Info.plist                    # Bundle metadata
│   ├── MacOS/
│   │   ├── tuwien-2fa-native         # Rust binary
│   │   └── install-helper            # Small helper that writes native manifest
│   └── Resources/
│       ├── icon.icns                 # App icon
│       └── FirefoxNativeHost/        # Bundled native manifest template
│           └── com.tuwien.2fa.json
```

**Install flow**:
1. User downloads `.dmg`, opens it
2. Drags `TU Wien 2FA.app` to `/Applications`
3. On first launch, `install-helper` writes the native manifest to `~/Library/Application Support/Mozilla/NativeMessagingHosts/com.tuwien.2fa.json`
4. Path in manifest points to the immutable `.app` bundle path — survives reboots
5. Extension installs from AMO or user loads via about:debugging

**Signing**:
- Code-sign with Apple Developer ID (`security-framework` needs this for Keychain access)
- Notarize the `.dmg` so Gatekeeper doesn't block it
- Hardened runtime entitlement: `com.apple.security.cs.disable-library-validation` (if needed)
- Without signing: Keychain dialog appears once, access is path-based — but `.app` path is stable

**Uninstall**: Drag `.app` to Trash + run bundled uninstall script that removes manifest.

---

#### Windows

**Package**: `.msi` installer (via WiX toolset) or self-extracting `.exe` (via Inno Setup).

```
C:\Program Files\TU Wien 2FA\
├── tuwien-2fa-native.exe            # Rust binary
├── install-helper.exe                # Writes native manifest to registry
└── uninstall.exe                     # Removes registry entries
```

**Install flow**:
1. User runs `.msi` / `.exe` installer
2. Binary installed to `C:\Program Files\TU Wien 2FA\`
3. Installer writes registry key:
   ```
   HKEY_CURRENT_USER\Software\Mozilla\NativeMessagingHosts\com.tuwien.2fa
   ```
   with path to the binary
4. Extension installs from AMO or sidebar-loaded

**Signing**:
- Code-sign with EV certificate or self-sign for personal use
- Windows SmartScreen won't block signed packages

**Uninstall**: via Windows Add/Remove Programs or `uninstall.exe`.

---

#### Linux

**Package(s)**: `.deb` (Debian/Ubuntu), `.rpm` (Fedora), AppImage, or Flatpak.

```
/opt/tuwien-2fa/
├── tuwien-2fa-native                # Rust binary
├── install-helper                    # Shell script: writes native manifest
└── uninstall.sh
```

**Install flow** (`.deb` / `.rpm`):
1. User installs via `sudo dpkg -i` / `sudo rpm -i` or via GUI package manager
2. Binary installed to `/opt/tuwien-2fa/`
3. Post-install script writes manifest to:
   - User: `~/.mozilla/native-messaging-hosts/com.tuwien.2fa.json`
   - System-wide: `/etc/chromium/native-messaging-hosts/com.tuwien.2fa.json` (Firefox also checks `/usr/lib/mozilla/native-messaging-hosts/`)
4. Dependency declared: `libsecret-1-0` (runtime library for keyring backend)

**AppImage**:
- Single self-contained binary, no extraction needed
- User runs once, it spawns `install-helper` to write manifest, then daemonizes

**Flatpak**:
- Sandboxing may prevent stdin/stdout Native Messaging — needs investigation
- Might need a D-Bus socket bridge instead

**Uninstall**: via package manager (`dpkg -r`, `rpm -e`) or delete `/opt/tuwien-2fa/` + manifest.

---

#### Common considerations for all platforms

| Aspect | Plan |
|--------|------|
| **Binary stability** | Binary lives in OS-standard path (not project dir), never moves |
| **Manifest path** | Points to stable install path, survives updates |
| **Code signing** | macOS: Apple Developer ID; Windows: EV cert; Linux: GPG signing for repos |
| **Auto-update** | Not in v1 — manual update via package reinstall |
| **Firefox extension** | Published on AMO for easy install; `.xpi` bundled with installer as fallback |
| **Silent install** | Install helpers run silently, no GUI, just writes a JSON file to the right place |
| **Keychain access** | Signed binary → no repeated Keychain prompts on macOS |

### [ ] Content script improvements
- Currently watches body for #totp — works for single-page navigation
- Should also listen for `popstate` / `hashchange` events
- Consider debounce to avoid multiple TOTP generations on same page

### [ ] Distribution
- Test `pnpm run build` (web-ext build) for extension .zip
- `web-ext sign` for Mozilla add-on signing (requires AMO account)
- Build native installers for all three platforms (GitHub Actions CI)

## Fixed issues

- **2025-06-20**: `keyring` crate was using **mock backend** on macOS (no `apple-native` feature).
  `set_password` returned `Ok(())` but stored nothing — data lost on process exit.
  Fixed: added `features = ["apple-native"]` for macOS, `["windows-native"]` for Windows,
  `["sync-secret-service"]` for Linux in `Cargo.toml` via target-specific dependencies.

## Security notes

| Concern | Current approach |
|---------|-----------------|
| TOTP seed at rest | OS Keychain (Apple Keychain via `keyring-rs`) |
| TOTP seed in transit | Firefox Native Messaging (stdin/stdout, per-extension access control) |
| TOTP seed in memory | Used only during `generateTOTP()`, not persisted to extension storage |
| Network | No outbound network requests from extension or native host |
| macOS Keychain access | Binary is unsigned — user gets "allow/deny" popup on first access |

## Cross-platform notes

| Platform | Keychain backend | Build target |
|----------|-----------------|-------------|
| macOS | Apple Keychain (Security.framework) | Universal (x86_64 + arm64) via lipo |
| Linux | libsecret (GNOME Keyring / KDE Wallet) | cargo build --release |
| Windows | Windows Credential Manager | cargo build --release |

- Linux build requires `libsecret-1-dev`
- Windows build should work out of the box (no special deps)
