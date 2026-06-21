Name: tuwien-auto-2fa
Version: 1.0.3
Release: 1
Summary: Firefox extension for automatic TU Wien 2FA
License: MIT
Requires: libsecret
BuildArch: x86_64

%description
Auto-fills TOTP codes for TU Wien login.
The TOTP seed is stored in the system keyring.
This is NOT an official tool by TU Wien.

%install
mkdir -p %{buildroot}/opt/tuwien-2fa
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/256x256/apps

cp %{_sourcedir}/tuwien-2fa-native %{buildroot}/opt/tuwien-2fa/
cp %{_sourcedir}/launcher.sh %{buildroot}/opt/tuwien-2fa/
chmod 755 %{buildroot}/opt/tuwien-2fa/tuwien-2fa-native
chmod 755 %{buildroot}/opt/tuwien-2fa/launcher.sh

cp %{_sourcedir}/tuwien-2fa.desktop %{buildroot}/usr/share/applications/

if [ -f %{_sourcedir}/tuwien-2fa.svg ]; then
  cp %{_sourcedir}/tuwien-2fa.svg %{buildroot}/usr/share/icons/hicolor/256x256/apps/
fi

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
  "allowed_extensions": ["tuwien-auto-2fa@aGreatTUWienStudent"]
}
EOF

%preun
rm -f "$HOME/.mozilla/native-messaging-hosts/com.tuwien.2fa.json"
/opt/tuwien-2fa/tuwien-2fa-native --delete-credential 2>/dev/null || true

%files
/opt/tuwien-2fa/tuwien-2fa-native
/opt/tuwien-2fa/launcher.sh
/usr/share/applications/tuwien-2fa.desktop
/usr/share/icons/hicolor/256x256/apps/tuwien-2fa.svg
