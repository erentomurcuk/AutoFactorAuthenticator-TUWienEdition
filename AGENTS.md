# AGENTS.md — AutoFactorAuthenticator / AutoTISS2FA

> **Mandate:** update this file in the same session whenever you change a
> command, path, name, version or behaviour described here, before you declare
> the work done. Add user-visible behaviour notes to the README instead of
> duplicating them here; this file is for the *working system*, not for users.

## 1. Identity (v1.2.1)

| Thing | Value |
|---|---|
| Brand / repo | **AutoFactorAuthenticator** |
| This variant / app | **AutoTISS2FA** (the TU Wien login build) |
| Version (all synced) | **1.2.1** |
| Rust crate + binary | `autotiss2fa-native` |
| Native messaging host name | `com.autofactor.autotiss2fa` |
| Firefox add-on ID | `autotiss2fa@autofactorauthenticator` |
| Keychain service | `AutoTISS2FA` (old `TU Wien Auto 2FA` entries are also deleted by `--delete-credential`) |
| License | MIT, see `LICENSE` |

A **version bump means all four** of: `extension/manifest.json`,
`package.json`, `native-host/Cargo.toml` **and `Cargo.lock`**, plus
`build/deb/control`+`build-deb.sh`, `build/rpm/spec`+`build-rpm.sh`,
`inno-setup.iss`, `Info.plist` (two keys), and the names hard-coded inside the
`build-{deb,rpm}.sh` output filenames. Grep for the old version string to
prove you got them all.

## 2. What this is

Firefox MV3 extension (`extension/`, plain JS) + Rust native-messaging host
(`native-host/`). The host stores ONE TOTP seed in the OS keyring **and
generates the RFC 6238 codes itself** (HMAC-SHA1 in Rust, unit-tested against
RFC 4226 vectors via `cargo test`). Since the 1.2 `get_code` protocol change
Firefox never receives the seed — only finished codes; the extension has no
crypto at all. The content script fills the TOTP field on
`idp.zid.tuwien.ac.at`; the user submits.

## 3. Layout

```
extension/             the add-on
  manifest.json        MV3; gecko id, nativeMessaging perm, +host_permissions
  background.js        TOTP generation, native host calls, message routing
  content_script.js    field detection (#totp + fallbacks) & fill logic
  popup/               seed setup / code dashboard UI
native-host/
  src/main.rs          stdio JSON protocol; keyring read/write/delete; probe
  install.sh           build + user-level registration (macOS/Linux/MSYS-Win)
  uninstall.sh         inverse of install.sh (+ Windows registry via reg.exe)
  build/
    build-packages.sh  orchestrator: macos | windows | linux | all
    macos/             .app bundle + DMG + icns pipeline
    windows/           Inno Setup EXE (x64/ARM64) + launcher.bat
    linux/             DEB / RPM / AppImage builders + user launcher + AppRun
```

Commands:

```bash
pnpm run dev      # web-ext run on a temp profile
pnpm run build    # → web-ext-artifacts/autotiss2fa-<version>.xpi (delete after a release)
pnpm run lint     # web-ext lint; MUST be clean: 0 errors, 0 warnings
pnpm run sign     # AMO --channel=listed (review); keys from .env (git-ignored, auto-loaded)
pnpm run sign:unlisted   # instant self-signing, no review, not installable from AMO
pnpm run install-host / uninstall-host

cd native-host && cargo build --release   # the Linux/mac/MSYS build
cd native-host/build && bash build-packages.sh linux   # installers
cd native-host/build/windows && bash build-exe.sh      # → x64-only Setup.exe (--arm64 for dual-arch)
```

Validation before pushing anything:
`cargo build --release`, `pnpm run lint`, `bash -n` every changed `.sh`
(including `appimage/AppRun`), `node --check` every changed `.js`.

## 4. Hard rules

1. **Never weaken the keychain story.** The seed lives in the OS keyring and
   nowhere else. No `browser.storage` fallback, no plain-text file.
2. **`allowed_extensions` must name exactly one add-on id**, and that id must
   equal `browser_specific_settings.gecko.id`. When you rename one side you
   MUST rename both and every installer that writes the manifest.
3. **Never ship the seed-naming key ("old service") removal as a fix you can
   forget**: `--delete-credential` deletes BOTH `AutoTISS2FA` and the
   pre-rename `TU Wien Auto 2FA` entries on purpose (upgrade path).
4. **MIT for everything new** (`Cargo.toml` already carries `license = "MIT"`).

## 5. Traps — each has cost time once; do not re-learn

1. **Windows · raw backslashes in the manifest JSON are the v1.1 bug.** The
   old installers (inno `[Code]`, `launcher.bat`, install.sh-on-MSYS) wrote
   `"path": "C:\Program Files\..."`; `\P`/`\T` are invalid JSON escapes, so
   Firefox never loaded the host: "app installed, extension blind". JSON
   paths always carry FORWARD slashes (`!BINARY_PATH:\=/!` in the .bat,
   `'/'`-joined Pascal strings, `cygpath -m` in bash). Also remember:
   Firefox-on-Windows finds the manifest ONLY through the registry key
   `HKCU\Software\Mozilla\NativeMessagingHosts\<host>`; the JSON file is just
   the file the registry points to.
2. **`zenity --question` returns 1 on "No"** — under `set -e` the call must
   itself be the `if` condition. Writing `show_dialog …; if [ $? -eq 0 ]` is
   dead code on the very branch it was written for (the v1.1 AppRun did
   exactly that). Same shape anywhere a dialog/CLI returns rc-as-answer.
3. **Inno Setup 6.3+ is required** for `x64compatible` (and for `IsARM64`,
   which only the dual-arch build uses). 6.0–6.2 fail to compile; say so
   wherever the requirement appears. The compiler is **per-user by default**
   (`%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe`, what winget installs) and
   is on neither PATH nor under Program Files — both build scripts search that
   path, the registry and `$ISCC`. A readable version below 6.3 is refused;
   an unreadable one only warns, because `FileVersionInfo` returns `0.0.0.0`
   on some perfectly good 6.x installs (ISCC itself then rejects the script).
4. **Every `@2x` icon must be a real double-size render**, not a copy of the
   same-size PNG; and the canonical iconset sizes are 16/32/128/256/512 —
   1024 only appears as `512@2x`. `iconutil` accepts extra sizes but validates
   the @2x dimensions.
5. **linuxdeploy writes the output into its own CWD** (`cd "$OUT_DIR" &&
   linuxdeploy …`). Selecting "the new AppImage" by name inside the same dir
   as linuxdeploy + earlier builds can grab the wrong file and `mv` it onto
   itself (race, and fatal under `set -e`).
6. **`runtime.sendNativeMessage` warnings that flood web-ext lint mean your
   manifest is broken, not the code.** A single `JSON_DUPLICATE_KEY` error
   makes the schema lookup fail and turns every `runtime.*` call into
   `UNSUPPORTED_API` warnings. Fix the JSON first; a clean manifest lints
   silent even with native messaging.
7. **The manifest version must agree with `Cargo.lock`** (`sed` the local
   package entry, or `cargo build` rewrites the lock).
8. **Rust: `env!["CARGO_PKG_VERSION"]`** is the single truth for `--version`
   in the host; do not hard-code a number there.
9. **A trailing `\x00` inside a bash command substitution is stripped
   silently** (`$(printf '...\x00')`); frames built like that corrupt the
   native-messaging length prefix. printf directly into a pipe instead.
10. **Deleting old identity strings requires a full grep** of
    `tuwien|TU Wien Auto 2FA|com\.tuwien|aGreatTUWienStudent` — four separate
    spellings exist in installers and each misses others silently.
11. **Never `exec "$BINARY"` from a desktop-facing AppRun/launcher tail** —
    the host is a stdio server; double-clicking an already-installed AppImage
    that execs it blocks a terminal-less session until killed. Desktop
    entry-points show status and exit.
12. **`dpkg-deb` control files are not shell-config files**: description
    continuation lines must start with a single space, and `#` comments are
    illegal inside `DEBIAN/control` (rationale goes in the build script).
    Always build with `--root-owner-group`, or the installed files keep the
    build user's uid:gid.
13. **linuxdeploy's bundled strip goes stale against newer distro libcs**
    (`.relr.dyn` rejected: `[0x13] unknown type`). If an AppImage build dies
    on strip, delete the checked-in `linuxdeploy-x86_64.AppImage` and let
    `build-appimage.sh` download a fresh one — that is also what happens on
    any machine where it is simply missing.
14. **`printf '\x%02x…'` is invalid bash** — `%` is not a hex digit, so the
    escape is dropped with "missing hex digit for \x" and the length prefix
    the host reads is garbage (`message too large`). This shipped as the
    REAL cause of "An error has occurred / keyring daemon unreachable" in the
    launcher's first-run probe even after the trap-9 fix. Bash printf also
    cannot nest `%02x` inside `\x`; build the escapes into a format string
    first and expand with a `%b` pass:
    `esc=$(printf '\\x%02x\\x00\\x00\\x00' $len); printf '%b%s' "$esc" "$payload"`.
15. **Never trust `target/release/<bin>` without a `test -x` check** in
    packaging scripts after any interruption: twice today the final artifact
    was absent while `cargo build` still reported "Finished" in 0.02 s
    (fresh fingerprint, no relink). `build-deb.sh` guards it, but any tool
    that just assumes the file will save a broken run. When in doubt:
    `test -x target/release/autotiss2fa-native || cargo build --release`.

## 6. Protocol contract (extension ↔ host)

Request: u32-LE length + JSON `{"command": …}` on stdin.
Response: same framing, `{"status":"ok"|"error","data":?,"message":?}`.

| command | meaning |
|---|---|
| `ping` | health check → `data:"pong"` |
| `probe` | exercises the keyring backend (NoEntry = reachable-and-empty = pass); used by `build/linux/launcher.sh` |
| `check` | is a seed configured (`data:"configured"` / null + message) |
| `get_code` | **the** data command: generates the current 6-digit code in Rust → `data:{"code":"123456","ttl":seconds}` (ttl 1–30); error `No seed configured` |
| `store_seed` | `{seed: …}`; validated & canonicalised (padding/whitespace/dashes stripped, chars A–Z/2–7 only, len 16–256) |
| `delete_seed` | removes the keyring entry (idempotent on NoEntry) |

**`get_seed` was REMOVED in 1.2** — asking the host for the raw seed
contradicts the keychain story once the host can generate codes itself. If an
old build still sends it, it gets `Unknown command`. Do not re-add it casually;
it would also require re-testing the extension's error paths.

TOTP constants: SHA-1, 6 digits, 30 s window; base32 decode drops a trailing
partial byte (same rule as every RFC 4648 decoder), so non-canonical
(8-char-multiple) seeds behave like everywhere else. `Response.data` is a JSON
value (string for ping/probe/check, object for `get_code`, `null` elsewhere).

CLI flags on the host binary: `--delete-credential`, `--version`, `--help`;
plus the manifest-path-arg-first convention Firefox passes on macOS
(ignore argv except the known flags).

## 7. Smoke tests (no browser-driven suite exists — this is the minimum bar)

```bash
# Rust unit tests NOW EXIST (base32 + RFC 4226 vectors + validator):
cd native-host && cargo test --release

# protocol round-trip incl. hostile inputs + a live get_code cross-check
# against a python RFC-6238 reference (python script from session log)

# Windows-shaped manifest must parse as JSON (forward slashes):
#   simulate cygpath -m output manually and json.loads it

# Lint + package the add-on:
pnpm run lint        # 0 errors 0 warnings
pnpm run build

# Keyring delete of BOTH service names:
./target/release/autotiss2fa-native --delete-credential
```

> ⚠️ **`cargo test` does NOT rebuild the shipped binary.** The DT-truncation
> bug above shipped because a `cargo test --release && cargo build` chain
> stopped at the failing test and the *stale* binary kept answering get_code
> with wrong values. After ANY main.rs change: run `cargo build --release`
> and re-run the protocol smoke against the fresh binary.

## 8. AMO submission notes (recorded, not to be re-derived)

- The add-on is plain JS/HTML/CSS; **no code generators, minifiers, bundlers
  or template engines** — `web-ext build` only zips `extension/`. Answer
  "No" to the processing-tools question on the submission form.
- Because the extension declares `nativeMessaging`, provide reviewers a
  link to this repo, highlighting `native-host/src/main.rs` (the full host
  surface: 6 commands, no network, no telemetry) and point out the host
  binary installs separately from the .xpi.
- `pnpm run lint` must be 0 errors / 0 warnings *before* submitting; a
  broken manifest.json poisons the whole lint (trap 6) and reviewers'
  first impression.
- `pnpm run build` emits `web-ext-artifacts/autotiss2fa-<version>.xpi`
  (`--filename=autotiss2fa-{version}.xpi`, version read from the manifest), and
  that file is what AMO gets: by hand at
  <https://addons.mozilla.org/developers/>, or via `pnpm run sign`
  (`--channel=listed`, i.e. review) / `pnpm run sign:unlisted`. The API
  credentials live in `.env` (git-ignored, template `.env.example`), which the
  sign scripts load with `--env-file-if-exists=.env`; Node 22.9+ is required
  for that flag.
- `.env` holds secrets: it is git-ignored, `.env.example` is the tracked
  template, and neither the keys nor the signed artifact may be committed.
- Re-signing a version that AMO already has fails with `409 Version <x>
  already exists` (the version, not the bytes, is unique). Do **not** bump the
  version just to get a "fresh" signature; fetch the already-signed file from
  `https://addons.mozilla.org/api/v5/addons/addon/<guid>/versions/?filter=all_with_unlisted`
  (JWT auth with the `.env` credentials) and hand that out.

## 9. Roadmap (do not implement casually)

- **Microsoft SSO (login.microsoftonline.com) 2FA** for TU Wien mail — the
  acknowledged next feature; may become its own variant rather than a
  second content script here.
- ~~Host-side TOTP generation~~ **DONE in 1.2** (`get_code`; `get_seed`
  removed). Any new seed-sensitive command must re-justify why the browser
  needs the data.
- **Per-variant keyring labels** are already the pattern
  (`AutoTISS2FA` / any future fork) — keep it when forking.

## 10. Change log (v1.2.1)

### 1.2.1

- Version bump that carries the host-side `get_code` work + popup redesign +
  new icon (all done in the same session, previously committed unpushed as
  `a669fde`). Identity unchanged; upgrade 1.2.0 → 1.2.1 is a normal update,
  only ≤1.1 needs the full uninstall/reinstall dance.
- `build/windows/setup-and-build.ps1` added: one stop script for a fresh
  Windows box — installs Git, Rustup/stable-msvc, VS Build Tools (VC++) and
  Inno Setup 6.3+ via winget, clones/pulls the repo, `cargo build --release`,
  stages and runs `build-exe.ps1`, and drops `AutoTISS2FA-Setup.exe` on the
  Desktop. Re-runnable; every step is skipped when already done.
- Extension packaging now emits an installable `.xpi` instead of a `.zip`:
  `pnpm run build` → `web-ext-artifacts/autotiss2fa-1.2.1.xpi` (filename
  template `autotiss2fa-{version}.xpi`, version from the manifest), plus
  `pnpm run sign` (AMO listed/review) and `pnpm run sign:unlisted`
  (instant self-signing). Credentials come from `.env` (git-ignored, loaded via
  `--env-file-if-exists`; tracked template `.env.example`).
- 1.2.1 is already signed on the unlisted channel (file id 5141356,
  sha256 `bdfba59c…fbb53`); its payload is byte-identical to `extension/`
  except manifest whitespace. Re-running `sign` returns 409 — see §8.
- Windows installer is **x64-only by default** (`build-exe.ps1` /
  `build-exe.sh`, and `setup-and-build.ps1` without `-Arm64`): no ARM64
  probing and no "ARM64 binary not found" noise. `inno-setup.iss` gates the
  ARM64 file + architecture behind `#ifdef Arm64` (`/DArm64` is passed only by
  `-Arm64` / `--arm64`). ISCC lookup now covers the per-user winget location
  (`%LOCALAPPDATA%\Programs\Inno Setup 6`), the registry and `$ISCC`; a
  readable version < 6.3 is refused, an unreadable one only warns (some real
  6.x installs report `0.0.0.0` via FileVersionInfo).

### 1.2.0

- Full rebrand: AutoFactorAuthenticator (repo) / AutoTISS2FA (this build);
  new add-on id, new host name, new binary/deb/rpm/AppImage/DMG/EXE names.
- Windows: fixed the invalid-JSON backslash manifest bug (extension could
  never see the host); `launcher.bat` and Inno now also uninstall the
  registry key; forward-slash paths in every manifest writer.
- Linux: corrected deb dependency `libsecret-1-0` → `libdbus-1-3`
  (the binary links only libdbus) and added `Recommends: zenity | kdialog`;
  rpm `dbus-libs` + `Recommends: zenity`; icons under `hicolor/scalable`;
  AppRun consent-dialog `set -e` bug fixed (declining used to kill the
  script); AppRun no longer execs the stdio host after install; AppImage
  rename race gone (linuxdeploy output isolated in its own dir).
- Linux packaging verified end-to-end on-device for 1.2.0 (deb + rpm +
  AppImage built, contents + NEEDED libs + keyring round-trip checked);
  fixes surfaced by the real build are in traps 12–13.
- macOS: `@2x` icns sizes are real double-size renders; DMG no longer writes
  a fake hand-rolled `.DS_Store` (Finder layout applied on the mounted volume
  where possible; failures non-fatal and honest).
- Rust host: `--version`; seed cleaner strips `=`/whitespace/dashes and keeps
  a canonical uppercase alphabet (padding used to survive into the keyring);
  `--delete-credential` also removes the pre-rename keychain entry.
- Extension: fallback field detection (`#totp`, then
  `input[autocomplete="one-time-code"]`, then `input[name*="totp" i]`);
  disabled/readOnly fields are skipped; popup validation matches host
  semantics; popup retry loop cannot double-fire; response shape guarded.
- Repo: MIT license file added (was none); stale 1.0.3 build artifacts
  (deb staging tree with a 590 KB binary, rpm, xpi zip) removed from git;
  `.gitignore` template leftovers gone; unused `scripts/write-manifest.sh`
  and `scripts/cleanup.sh` deleted; version 1.2.0 everywhere; README +
  AGENTS.md rewritten.
- Upgrades from ≤1.1 require a FULL uninstall+reinstall (README "Upgrading
  from a pre-1.2 version"): identity rename means old host ↔ new extension
  ID cannot connect.
- **Host-side TOTP generation (get_code) landed in 1.2**: HMAC-SHA1 in Rust,
  `cargo test` pins RFC 4226 vectors; `get_seed` removed — Firefox never
  receives the seed, only `{code, ttl}`. The DT-truncation bug this
  introduced (shift 32 + 5 bytes instead of the RFC's shift 24 + 4) was
  caught by those vectors and is why the stale-binary warning in §7 exists.
- Popup redesigned (token-driven light/dark, ring countdown, grouped code,
  live validation feedback, inline delete confirm) and the icon replaced
  (icon.svg v2: gradient shield carrying digit bars; feeds Firefox, icns,
  hicolor + AppImage from one file).
