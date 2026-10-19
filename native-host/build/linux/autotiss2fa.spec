Name: autotiss2fa
Version: 1.2.0
Release: 1
Summary: Firefox extension for automatic TU Wien 2FA
License: MIT
Requires: dbus-libs
Recommends: zenity

# Dependency note (fixed in 1.2): the host links libdbus-1.so.3 (via dbus-libs)
# and nothing else. The old "Requires: libsecret" was fictional - libsecret
# was never linked. Run-time keyring access needs a Secret Service provider
# (GNOME Keyring, KDE Wallet or KeepassXC's Secret Service plugin).

%description
AutoFactorAuthenticator / AutoTISS2FA.
Auto-fills TOTP codes for TU Wien login.
The TOTP seed is stored in the system keyring.
This is NOT an official tool by TU Wien.

%install
mkdir -p %{buildroot}/opt/autotiss2fa
mkdir -p %{buildroot}/usr/share/applications
mkdir -p %{buildroot}/usr/share/icons/hicolor/scalable/apps

cp %{_sourcedir}/autotiss2fa-native %{buildroot}/opt/autotiss2fa/
cp %{_sourcedir}/launcher.sh %{buildroot}/opt/autotiss2fa/
chmod 755 %{buildroot}/opt/autotiss2fa/autotiss2fa-native
chmod 755 %{buildroot}/opt/autotiss2fa/launcher.sh

cp %{_sourcedir}/autotiss2fa.desktop %{buildroot}/usr/share/applications/

if [ -f %{_sourcedir}/autotiss2fa.svg ]; then
  cp %{_sourcedir}/autotiss2fa.svg %{buildroot}/usr/share/icons/hicolor/scalable/apps/
fi

%post
# Do not write the native messaging manifest here: rpm runs %post as root
# with HOME=/root, so the manifest would end up in /root/.mozilla and the
# real user's Firefox would not see it. Instruct the user to launch the
# app once so launcher.sh writes the manifest for their own $HOME.
echo "AutoTISS2FA installed."
echo "Launch 'AutoTISS2FA' from your application menu to register it with Firefox."

%preun
rm -f "$HOME/.mozilla/native-messaging-hosts/com.autofactor.autotiss2fa.json" 2>/dev/null || true
/opt/autotiss2fa/autotiss2fa-native --delete-credential 2>/dev/null || true

%files
/opt/autotiss2fa/autotiss2fa-native
/opt/autotiss2fa/launcher.sh
/usr/share/applications/autotiss2fa.desktop
/usr/share/icons/hicolor/scalable/apps/autotiss2fa.svg
