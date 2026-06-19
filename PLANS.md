# TUWien Auto 2FA — Development Notes

## Current state

- [x] Extension scaffold (manifest.json, background.js, content_script.js, popup)
- [x] Rust native host (native-host/) — builds, installed, macOS universal binary
- [x] pnpm + web-ext@10.4.0 (0 vulnerabilities)
- [x] Git repo initialized
- [x] Renamed TUWEL → TUWien throughout
- [x] Native host installed in ~/Library/Application Support/Mozilla/NativeMessagingHosts/

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

### [ ] Wrap native host as proper macOS .app bundle
- Create `.app` bundle structure with Info.plist, icons
- Binary inside `Contents/MacOS/`
- Install script copies app to `/Applications` and sets up native manifest
- Code signing / hardened runtime so Keychain doesn't prompt each access

### [ ] Native host: handle stdin EOF gracefully
- Currently `loop { read_message() }` — on EOF the loop breaks and main() returns
- Need to ensure clean exit so Firefox doesn't report "native host exited unexpectedly"

### [ ] Add error handling in the Rust host
- Current code uses basic match/continue
- Should add rate-limiting / timeout / backoff to prevent abuse

### [ ] Content script improvements
- Currently watches body for #totp — works for single-page navigation
- Should also listen for `popstate` / `hashchange` events
- Consider debounce to avoid multiple TOTP generations on same page

### [ ] Distribution
- Test `pnpm run build` (web-ext build) for extension .zip
- `web-ext sign` for Mozilla add-on signing (requires AMO account)
- Could bundle the .app + extension in a single .dmg

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
