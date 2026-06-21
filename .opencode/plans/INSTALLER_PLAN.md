# Implementation Plan: Cross-Platform Installers

## Overview
Create secure, easy-to-use installers for macOS (DMG), Windows (MSI + EXE), and Linux (deb, rpm, AppImage) that bundle both the native host and Firefox extension.

## Requirements Summary
- **Pre-built binaries** (no Rust toolchain needed for users)
- **macOS**: DMG with .app bundle, ad-hoc signed, includes extension
- **Windows**: Both MSI (WiX) and EXE (Inno Setup), includes extension
- **Linux**: deb, rpm, AppImage with GUI dialog, plus keep binary install
- **All installers**: Bundle Firefox extension (.xpi file)
- **Security**: Stable paths, keychain cleanup on uninstall, proper permissions

---

## Phase 1: Build Infrastructure

### 1.1 Create Build Scripts Directory
```
native-host/
├── build/
│   ├── build-packages.sh          # Main orchestrator
│   ├── macos/
│   │   ├── create-app-bundle.sh
│   │   ├── create-dmg.sh
│   │   └── Info.plist
│   ├── windows/
│   │   ├── build-msi.sh
│   │   ├── build-exe.sh
│   │   ├── wix-template.xml
│   │   └── inno-setup.iss
│   └── linux/
│       ├── build-deb.sh
│       ├── build-rpm.sh
│       ├── build-appimage.sh
│       └── appimage/
│           ├── AppRun
│           └── tuwien-2fa.desktop
└── scripts/
    ├── write-manifest.sh          # Shared manifest writing
    ├── cleanup.sh                 # Shared uninstall cleanup
    └── first-run-dialog.sh        # macOS/Linux GUI dialog
```

### 1.2 Shared Scripts

#### write-manifest.sh
```bash
#!/bin/bash
# Writes Firefox native messaging manifest
# Args: $1 = binary path, $2 = OS (macos/linux/windows)

EXTENSION_ID="tuwien-auto-2fa@tuwien.ac.at"
HOST_NAME="com.tuwien.2fa"

get_manifest_dir() {
  case "$1" in
    macos)  echo "$HOME/Library/Application Support/Mozilla/NativeMessagingHosts" ;;
    linux)  echo "$HOME/.mozilla/native-messaging-hosts" ;;
    windows) echo "$HOME/AppData/Local/Mozilla/NativeMessagingHosts" ;;
  esac
}

write_manifest() {
  local binary_path="$1"
  local os="$2"
  local manifest_dir=$(get_manifest_dir "$os")
  
  mkdir -p "$manifest_dir"
  cat > "$manifest_dir/$HOST_NAME.json" << EOF
{
  "name": "$HOST_NAME",
  "description": "Native host for TU Wien Auto 2FA",
  "path": "$binary_path",
  "type": "stdio",
  "allowed_extensions": ["$EXTENSION_ID"]
}
EOF
}
```

#### cleanup.sh
```bash
#!/bin/bash
# Removes manifest and keychain entry
# Args: $1 = OS (macos/linux/windows)

HOST_NAME="com.tuwien.2fa"
BINARY_NAME="tuwien-2fa-native"

get_manifest_dir() {
  case "$1" in
    macos)  echo "$HOME/Library/Application Support/Mozilla/NativeMessagingHosts" ;;
    linux)  echo "$HOME/.mozilla/native-messaging-hosts" ;;
    windows) echo "$HOME/AppData/Local/Mozilla/NativeMessagingHosts" ;;
  esac
}

cleanup() {
  local os="$1"
  local manifest_dir=$(get_manifest_dir "$os")
  local manifest="$manifest_dir/$HOST_NAME.json"
  
  # Remove manifest
  [ -f "$manifest" ] && rm "$manifest"
  
  # Remove keychain entry if binary exists
  if [ "$os" = "windows" ]; then
    [ -x "tuwien-2fa-native.exe" ] && ./tuwien-2fa-native.exe --delete-credential
  else
    [ -x "tuwien-2fa-native" ] && ./tuwien-2fa-native --delete-credential
  fi
}
```

---

## Phase 2: macOS DMG

### 2.1 App Bundle Structure
```
TU Wien 2FA.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/
    │   └── tuwien-2fa-native  (universal binary)
    └── Resources/
        ├── icon.icns
        └── install-helper.sh
```

### 2.2 Info.plist
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>tuwien-2fa-native</string>
    <key>CFBundleIdentifier</key>
    <string>com.tuwien.2fa</string>
    <key>CFBundleName</key>
    <string>TU Wien 2FA</string>
    <key>CFBundleIconFile</key>
    <string>icon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

### 2.3 install-helper.sh (First Run Dialog)
```bash
#!/bin/bash
# Shows GUI dialog asking user to install manifest
# Uses osascript for native macOS dialog

BINARY_PATH="/Applications/TU Wien 2FA.app/Contents/MacOS/tuwien-2fa-native"
MANIFEST_DIR="$HOME/Library/Application Support/Mozilla/NativeMessagingHosts"
MANIFEST_FILE="$MANIFEST_DIR/com.tuwien.2fa.json"

# Check if already installed
if [ -f "$MANIFEST_FILE" ]; then
    osascript -e 'display dialog "TU Wien 2FA is already configured." buttons {"OK"} default button "OK" with icon note'
    exit 0
fi

# Show explanation dialog
RESULT=$(osascript <<EOF
display dialog "TU Wien 2FA needs to register with Firefox.

This will create a configuration file that allows the Firefox extension to communicate with the native host.

No personal data is stored. Your TOTP seed will be saved securely in your macOS Keychain when you configure it.

Do you want to proceed?" buttons {"Cancel", "Install"} default button "Install" with icon caution
EOF
)

if echo "$RESULT" | grep -q "Install"; then
    mkdir -p "$MANIFEST_DIR"
    cat > "$MANIFEST_FILE" << MANIFEST
{
  "name": "com.tuwien.2fa",
  "description": "Native host for TU Wien Auto 2FA",
  "path": "$BINARY_PATH",
  "type": "stdio",
  "allowed_extensions": ["tuwien-auto-2fa@tuwien.ac.at"]
}
MANIFEST
    
    osascript -e 'display dialog "Installation complete!

You can now install the Firefox extension from the included .xpi file.

To uninstall, drag this app to Trash and run the cleanup script." buttons {"OK"} default button "OK" with icon note'
fi
```

### 2.4 Uninstall Script
```bash
#!/bin/bash
# Uninstall TU Wien 2FA

osascript -e 'display dialog "This will remove TU Wien 2FA from your system.

Your TOTP seed will be removed from the macOS Keychain.

Continue?" buttons {"Cancel", "Uninstall"} default button "Uninstall" with icon caution' || exit 0

# Remove manifest
rm -f "$HOME/Library/Application Support/Mozilla/NativeMessagingHosts/com.tuwien.2fa.json"

# Remove keychain entry
/Applications/TU\ Wien\ 2FA.app/Contents/MacOS/tuwien-2fa-native --delete-credential 2>/dev/null

# Remove app
rm -rf "/Applications/TU Wien 2FA.app"

osascript -e 'display dialog "Uninstall complete." buttons {"OK"} default button "OK" with icon note'
```

### 2.5 DMG Creation
```bash
#!/bin/bash
# Create DMG with app bundle and extension

# Build universal binary
rustup target add x86_64-apple-darwin aarch64-apple-darwin 2>/dev/null
cargo build --release --target x86_64-apple-darwin
cargo build --release --target aarch64-apple-darwin
lipo -create -output tuwien-2fa-native \
  target/x86_64-apple-darwin/release/tuwien-2fa-native \
  target/aarch64-apple-darwin/release/tuwien-2fa-native

# Convert SVG to ICNS
# (Use svg2icns or online converter)

# Create app bundle
mkdir -p "TU Wien 2FA.app/Contents/MacOS"
mkdir -p "TU Wien 2FA.app/Contents/Resources"
cp Info.plist "TU Wien 2FA.app/Contents/"
cp tuwien-2fa-native "TU Wien 2FA.app/Contents/MacOS/"
cp icon.icns "TU Wien 2FA.app/Contents/Resources/"
cp install-helper.sh "TU Wien 2FA.app/Contents/MacOS/"
cp uninstall.sh "TU Wien 2FA.app/Contents/MacOS/"

# Ad-hoc sign (no personal info)
codesign --sign - --force "TU Wien 2FA.app"

# Build extension
cd ../extension
pnpm install
web-ext build
cd ../build/macos

# Create DMG
mkdir -p dmg-temp
cp -r "TU Wien 2FA.app" dmg-temp/
cp ../extension/web-ext-artifacts/*.xpi dmg-temp/
cp README.txt dmg-temp/

hdiutil create -volname "TU Wien Auto 2FA" -srcfolder dmg-temp -ov -format UDZO TUWien-Auto-2FA.dmg
rm -rf dmg-temp
```

---

## Phase 3: Windows Installers

### 3.1 MSI (WiX Toolset)

#### Install cargo-wix
```bash
cargo install cargo-wix
```

#### WiX Template (wix-template.xml)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
    <Product Id="*" Name="TU Wien Auto 2FA" Language="1033" Version="1.0.0" 
             Manufacturer="TU Wien Auto 2FA" UpgradeCode="PUT-GUID-HERE">
        <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine" />
        
        <MajorUpgrade DowngradeErrorMessage="A newer version is already installed." />
        <MediaTemplate EmbedCab="yes" />
        
        <Directory Id="TARGETDIR" Name="SourceDir">
            <Directory Id="ProgramFilesFolder">
                <Directory Id="INSTALLFOLDER" Name="TU Wien 2FA">
                    <Component Id="ProductComponent" Guid="PUT-GUID-HERE">
                        <File Id="NativeHost" Source="tuwien-2fa-native.exe" KeyPath="yes" />
                        <File Id="Extension" Source="tuwien-auto-2fa.xpi" />
                        <File Id="README" Source="README.txt" />
                        
                        <!-- Registry entry for Firefox native messaging -->
                        <RegistryKey Root="HKCU" Key="Software\Mozilla\NativeMessagingHosts\com.tuwien.2fa">
                            <RegistryValue Type="string" Value="[INSTALLFOLDER]tuwien-2fa-native.exe" />
                        </RegistryKey>
                    </Component>
                </Directory>
            </Directory>
        </Directory>
        
        <Feature Id="ProductFeature" Title="TU Wien Auto 2FA" Level="1">
            <ComponentRef Id="ProductComponent" />
        </Feature>
        
        <!-- Custom action to run --delete-credential on uninstall -->
        <CustomAction Id="DeleteCredential" 
                      Directory="INSTALLFOLDER"
                      ExeCommand="[INSTALLFOLDER]tuwien-2fa-native.exe --delete-credential"
                      Return="ignore" />
        
        <InstallExecuteSequence>
            <Custom Action="DeleteCredential" Before="RemoveFiles">REMOVE="ALL"</Custom>
        </InstallExecuteSequence>
    </Product>
</Wix>
```

#### Build MSI
```bash
#!/bin/bash
# Build Windows MSI

# Build binary
cargo build --release

# Build extension
cd ../extension
pnpm install
web-ext build
cd ../build/windows

# Copy files
cp ../../target/release/tuwien-2fa-native.exe .
cp ../../extension/web-ext-artifacts/*.xpi .

# Build MSI
cargo wix --no-build --output TUWien-Auto-2FA.msi
```

### 3.2 EXE (Inno Setup)

#### Inno Setup Script (inno-setup.iss)
```iss
[Setup]
AppName=TU Wien Auto 2FA
AppVersion=1.0.0
DefaultDirName={pf}\TU Wien 2FA
DefaultGroupName=TU Wien Auto 2FA
UninstallDisplayIcon={app}\tuwien-2fa-native.exe
OutputBaseFilename=TUWien-Auto-2FA-Setup

[Files]
Source: "tuwien-2fa-native.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "tuwien-auto-2fa.xpi"; DestDir: "{app}"; Flags: ignoreversion
Source: "README.txt"; DestDir: "{app}"; Flags: ignoreversion

[Registry]
Root: HKCU; Subkey: "Software\Mozilla\NativeMessagingHosts\com.tuwien.2fa"; ValueType: string; Value: "{app}\tuwien-2fa-native.exe"; Flags: uninsdeletekey

[Run]
Filename: "{app}\tuwien-2fa-native.exe"; Parameters: "--delete-credential"; Flags: runhidden; StatusMsg: "Cleaning up old data..."

[UninstallRun]
Filename: "{app}\tuwien-2fa-native.exe"; Parameters: "--delete-credential"; Flags: runhidden
```

#### Build EXE
```bash
#!/bin/bash
# Build Windows EXE (requires Inno Setup on Windows)

# Build binary
cargo build --release

# Build extension
cd ../extension
pnpm install
web-ext build
cd ../build/windows

# Copy files
cp ../../target/release/tuwien-2fa-native.exe .
cp ../../extension/web-ext-artifacts/*.xpi .

# Compile with Inno Setup (Windows only)
iscc inno-setup.iss
```

---

## Phase 4: Linux Packages

### 4.1 Debian Package (.deb)

#### Package Structure
```
tuwien-auto-2fa_1.0.0_amd64/
├── DEBIAN/
│   ├── control
│   ├── postinst
│   └── prerm
└── opt/
    └── tuwien-2fa/
        ├── tuwien-2fa-native
        ├── tuwien-auto-2fa.xpi
        └── README.txt
```

#### control
```
Package: tuwien-auto-2fa
Version: 1.0.0
Architecture: amd64
Maintainer: TU Wien Auto 2FA
Depends: libsecret-1-0
Description: Firefox extension for automatic TU Wien 2FA
 Auto-fills TOTP codes for TU Wien login.
```

#### postinst
```bash
#!/bin/bash
# Write manifest after install
BINARY_PATH="/opt/tuwien-2fa/tuwien-2fa-native"
MANIFEST_DIR="$HOME/.mozilla/native-messaging-hosts"

mkdir -p "$MANIFEST_DIR"
cat > "$MANIFEST_DIR/com.tuwien.2fa.json" << EOF
{
  "name": "com.tuwien.2fa",
  "description": "Native host for TU Wien Auto 2FA",
  "path": "$BINARY_PATH",
  "type": "stdio",
  "allowed_extensions": ["tuwien-auto-2fa@tuwien.ac.at"]
}
EOF
```

#### prerm
```bash
#!/bin/bash
# Remove manifest and keychain entry before uninstall
rm -f "$HOME/.mozilla/native-messaging-hosts/com.tuwien.2fa.json"
/opt/tuwien-2fa/tuwien-2fa-native --delete-credential 2>/dev/null || true
```

#### Build deb
```bash
#!/bin/bash
# Build Debian package

# Build binary
cargo build --release

# Build extension
cd ../extension
pnpm install
web-ext build
cd ../build/linux

# Create package structure
mkdir -p tuwien-auto-2fa_1.0.0_amd64/DEBIAN
mkdir -p tuwien-auto-2fa_1.0.0_amd64/opt/tuwien-2fa

cp control tuwien-auto-2fa_1.0.0_amd64/DEBIAN/
cp postinst tuwien-auto-2fa_1.0.0_amd64/DEBIAN/
cp prerm tuwien-auto-2fa_1.0.0_amd64/DEBIAN/
chmod 755 tuwien-auto-2fa_1.0.0_amd64/DEBIAN/postinst
chmod 755 tuwien-auto-2fa_1.0.0_amd64/DEBIAN/prerm

cp ../../target/release/tuwien-2fa-native tuwien-auto-2fa_1.0.0_amd64/opt/tuwien-2fa/
cp ../../extension/web-ext-artifacts/*.xpi tuwien-auto-2fa_1.0.0_amd64/opt/tuwien-2fa/
cp README.txt tuwien-auto-2fa_1.0.0_amd64/opt/tuwien-2fa/

# Build package
dpkg-deb --build tuwien-auto-2fa_1.0.0_amd64
```

### 4.2 RPM Package (.rpm)

Similar to deb but uses rpmbuild. Structure:
```
rpmbuild/
├── SPECS/
│   └── tuwien-auto-2fa.spec
├── BUILD/
├── RPMS/
└── SOURCES/
```

#### tuwien-auto-2fa.spec
```spec
Name: tuwien-auto-2fa
Version: 1.0.0
Release: 1
Summary: Firefox extension for automatic TU Wien 2FA
License: MIT
Requires: libsecret

%description
Auto-fills TOTP codes for TU Wien login.

%install
mkdir -p %{buildroot}/opt/tuwien-2fa
cp tuwien-2fa-native %{buildroot}/opt/tuwien-2fa/
cp tuwien-auto-2fa.xpi %{buildroot}/opt/tuwien-2fa/

%post
BINARY_PATH="/opt/tuwien-2fa/tuwien-2fa-native"
MANIFEST_DIR="$HOME/.mozilla/native-messaging-hosts"
mkdir -p "$MANIFEST_DIR"
cat > "$MANIFEST_DIR/com.tuwien.2fa.json" << EOF
{
  "name": "com.tuwien.2fa",
  "description": "Native host for TU Wien Auto 2FA",
  "path": "$BINARY_PATH",
  "type": "stdio",
  "allowed_extensions": ["tuwien-auto-2fa@tuwien.ac.at"]
}
EOF

%preun
rm -f "$HOME/.mozilla/native-messaging-hosts/com.tuwien.2fa.json"
/opt/tuwien-2fa/tuwien-2fa-native --delete-credential 2>/dev/null || true

%files
/opt/tuwien-2fa/tuwien-2fa-native
/opt/tuwien-2fa/tuwien-auto-2fa.xpi
```

### 4.3 AppImage with GUI Dialog

#### AppRun
```bash
#!/bin/bash
# AppImage entry point

HERE="$(dirname "$(readlink -f "$0")")"

# Check if manifest exists
MANIFEST_DIR="$HOME/.mozilla/native-messaging-hosts"
MANIFEST_FILE="$MANIFEST_DIR/com.tuwien.2fa.json"

if [ ! -f "$MANIFEST_FILE" ]; then
    # Show GUI dialog (using zenity or kdialog)
    if command -v zenity &> /dev/null; then
        zenity --question \
            --title="TU Wien Auto 2FA" \
            --text="TU Wien 2FA needs to register with Firefox.\n\nThis will create a configuration file that allows the Firefox extension to communicate with the native host.\n\nNo personal data is stored. Your TOTP seed will be saved securely in your system keyring.\n\nDo you want to proceed?" \
            --width=400
        
        if [ $? -eq 0 ]; then
            mkdir -p "$MANIFEST_DIR"
            cat > "$MANIFEST_FILE" << EOF
{
  "name": "com.tuwien.2fa",
  "description": "Native host for TU Wien Auto 2FA",
  "path": "$HERE/tuwien-2fa-native",
  "type": "stdio",
  "allowed_extensions": ["tuwien-auto-2fa@tuwien.ac.at"]
}
EOF
            zenity --info --title="TU Wien Auto 2FA" --text="Installation complete!"
        fi
    elif command -v kdialog &> /dev/null; then
        kdialog --yesno "TU Wien 2FA needs to register with Firefox..."
        if [ $? -eq 0 ]; then
            mkdir -p "$MANIFEST_DIR"
            cat > "$MANIFEST_FILE" << EOF
{
  "name": "com.tuwien.2fa",
  "description": "Native host for TU Wien Auto 2FA",
  "path": "$HERE/tuwien-2fa-native",
  "type": "stdio",
  "allowed_extensions": ["tuwien-auto-2fa@tuwien.ac.at"]
}
EOF
            kdialog --msgbox "Installation complete!"
        fi
    else
        echo "Please run with --install to set up the manifest"
    fi
fi

# Run the native host
exec "$HERE/tuwien-2fa-native"
```

#### Build AppImage
```bash
#!/bin/bash
# Build AppImage

# Build binary
cargo build --release

# Build extension
cd ../extension
pnpm install
web-ext build
cd ../build/linux

# Create AppDir
mkdir -p AppDir/usr/bin
cp ../../target/release/tuwien-2fa-native AppDir/usr/bin/
cp ../../extension/web-ext-artifacts/*.xpi AppDir/usr/bin/
cp AppRun AppDir/
cp tuwien-2fa.desktop AppDir/
cp icon.png AppDir/  # Convert SVG to PNG

# Download linuxdeploy
wget https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
chmod +x linuxdeploy-x86_64.AppImage

# Build AppImage
./linuxdeploy-x86_64.AppImage --appdir AppDir --output appimage
```

---

## Phase 5: README Updates

Add comprehensive installation instructions for all methods:

```markdown
## Installation

### Quick Install (Recommended)

#### macOS
1. Download `TUWien-Auto-2FA.dmg`
2. Open the DMG and drag `TU Wien 2FA.app` to Applications
3. Launch the app and follow the setup dialog
4. Install the included `.xpi` extension in Firefox

#### Windows
1. Download `TUWien-Auto-2FA-Setup.exe` (or `.msi`)
2. Run the installer
3. Install the included `.xpi` extension in Firefox

#### Linux

**Debian/Ubuntu:**
```bash
sudo dpkg -i tuwien-auto-2fa_1.0.0_amd64.deb
```

**Fedora/RHEL:**
```bash
sudo rpm -i tuwien-auto-2fa-1.0.0.x86_64.rpm
```

**AppImage:**
```bash
chmod +x TUWien-Auto-2FA-x86_64.AppImage
./TUWien-Auto-2FA-x86_64.AppImage
```

**From Source (Developers):**
```bash
cd native-host && bash install.sh
```

### Installing the Firefox Extension

All installers include the Firefox extension file (`tuwien-auto-2fa.xpi`).

1. Open Firefox
2. Go to `about:addons`
3. Click the gear icon → "Install Add-on From File..."
4. Select the `.xpi` file from the install location

**Install locations:**
- macOS: `/Applications/TU Wien 2FA.app/Contents/MacOS/`
- Windows: `C:\Program Files\TU Wien 2FA\`
- Linux: `/opt/tuwien-2fa/`
```

---

## Phase 6: Testing Checklist

### macOS
- [ ] DMG opens correctly
- [ ] App bundle structure is valid
- [ ] Ad-hoc signing works
- [ ] First-run dialog appears
- [ ] Manifest is written correctly
- [ ] Extension installs from bundled .xpi
- [ ] Uninstall removes manifest and keychain entry

### Windows
- [ ] MSI installs to Program Files
- [ ] MSI adds Control Panel entry
- [ ] MSI writes registry key
- [ ] EXE installer works
- [ ] Both uninstall cleanly
- [ ] Extension installs from bundled .xpi
- [ ] Keychain entry removed on uninstall

### Linux
- [ ] deb installs to /opt/tuwien-2fa
- [ ] deb post-install writes manifest
- [ ] deb prerm removes manifest and keychain
- [ ] rpm installs correctly
- [ ] AppImage runs and shows dialog
- [ ] AppImage writes manifest when accepted
- [ ] Binary install (install.sh) still works

---

## Implementation Order

1. Create build infrastructure (scripts directory, shared scripts)
2. Implement macOS DMG
3. Implement Windows MSI and EXE
4. Implement Linux deb, rpm, AppImage
5. Update README with all installation methods
6. Test all installers on respective platforms

---

## Security Considerations

✅ **Stable paths**: All installers use OS-standard paths that survive reboots
✅ **Keychain cleanup**: All uninstallers remove TOTP seeds from keychain
✅ **Proper permissions**: Binaries executable, manifests readable
✅ **No embedded secrets**: Packages contain only binary and manifest template
✅ **Ad-hoc signing**: macOS signing uses no personal credentials
✅ **User consent**: All installers show dialogs explaining what they do
✅ **Manifest isolation**: Manifests only allow the specific extension ID
