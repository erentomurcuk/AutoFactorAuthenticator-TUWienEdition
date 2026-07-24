Name: tuwien-auto-2fa
Version: 1.1.0
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
# Do not write the native messaging manifest here: rpm runs %post as root
# with HOME=/root, so the manifest would end up in /root/.mozilla and the
# real user's Firefox would not see it. Instruct the user to launch the
# app once so launcher.sh writes the manifest for their own $HOME.
echo "TU Wien Auto 2FA installed."
echo "Launch 'TU Wien 2FA' from your application menu to register it with Firefox."

%preun
rm -f "$HOME/.mozilla/native-messaging-hosts/com.tuwien.2fa.json" 2>/dev/null || true
/opt/tuwien-2fa/tuwien-2fa-native --delete-credential 2>/dev/null || true

%files
/opt/tuwien-2fa/tuwien-2fa-native
/opt/tuwien-2fa/launcher.sh
/usr/share/applications/tuwien-2fa.desktop
/usr/share/icons/hicolor/256x256/apps/tuwien-2fa.svg
