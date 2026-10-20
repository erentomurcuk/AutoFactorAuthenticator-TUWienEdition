[Setup]
AppName=AutoTISS2FA
AppVersion=1.2.1
AppPublisher=AutoFactorAuthenticator
AppComments=This is NOT an official tool by TU Wien. Provided AS IS.
DefaultDirName={pf64}\AutoTISS2FA
DefaultGroupName=AutoTISS2FA
UninstallDisplayIcon={app}\autotiss2fa-native.exe
OutputBaseFilename=AutoTISS2FA-Setup
Compression=lzma2
SolidCompression=yes
; NOTE: 'x64compatible' and the IsARM64 support function require Inno Setup 6.3
; or newer (2024). 6.0-6.2 fail to compile this script. 'x64compatible'
; replaces the now-deprecated 'x64' identifier.
;
; The build scripts pass /DArm64 only when the ARM64 host binary is being
; shipped (build-exe.ps1 -Arm64 / build-exe.sh --arm64). Without it this is an
; x64-only installer: one 64-bit binary, no ARM64 file reference at all.

#ifdef Arm64
ArchitecturesAllowed=x64compatible arm64
ArchitecturesInstallIn64BitMode=x64compatible arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
WizardStyle=modern

[Files]
#ifdef Arm64
; dual-architecture build: pick the binary matching the CPU
Source: "autotiss2fa-native-x64.exe"; DestDir: "{app}"; DestName: "autotiss2fa-native.exe"; Check: not IsARM64; Flags: ignoreversion
Source: "autotiss2fa-native-arm64.exe"; DestDir: "{app}"; DestName: "autotiss2fa-native.exe"; Check: IsARM64; Flags: ignoreversion
#else
; x64-only build (ARM64 Windows runs this binary through x64 emulation)
Source: "autotiss2fa-native-x64.exe"; DestDir: "{app}"; DestName: "autotiss2fa-native.exe"; Flags: ignoreversion
#endif
Source: "launcher.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "README.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\AutoTISS2FA"; Filename: "{app}\launcher.bat"
Name: "{group}\Uninstall AutoTISS2FA"; Filename: "{uninstallexe}"

[Registry]
; Firefox reads the *default* value of this key as a path to the native
; messaging manifest JSON file (not the binary). The manifest is written by
; the [Code] step below and additionally by the launcher on manual runs.
; HKCU works for a per-user Firefox regardless of installer elevation.
Root: HKCU; Subkey: "Software\Mozilla\NativeMessagingHosts\com.autofactor.autotiss2fa"; ValueType: string; ValueData: "{app}\com.autofactor.autotiss2fa.json"; Flags: uninsdeletekey

[Run]
Filename: "{app}\launcher.bat"; Description: "Configure AutoTISS2FA"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "{app}\autotiss2fa-native.exe"; Parameters: "--delete-credential"; Flags: runhidden

[Code]
// THE WINDOWS BUG FIXED IN 1.2: the manifest JSON used to be written with the
// path inline ("path": "C:\Program Files\AutoTISS2FA\autotiss2fa-native.exe").
// A single backslash before a letter is an INVALID JSON escape (\P, \T are
// undefined, \t is a tab), so Firefox failed to parse the file and the
// extension could never see the host - "the app is installed but the
// extension does not find it". JSON paths therefore always use FORWARD
// slashes; Windows APIs accept them and JSON needs no escaping.
procedure CurStepChanged(CurStep: TSetupStep);
var
  ManifestPath, AppDir, BinaryPath, ManifestContent: String;
begin
  if CurStep = ssPostInstall then
  begin
    AppDir := ExpandConstant('{app}');
    // Forward slashes: JSON-legal, accepted by CreateProcess on Windows.
    BinaryPath := AppDir + '/autotiss2fa-native.exe';
    ManifestPath := AppDir + '\com.autofactor.autotiss2fa.json';
    ManifestContent :=
      '{' + #13#10 +
      '  "name": "com.autofactor.autotiss2fa",' + #13#10 +
      '  "description": "Native host for AutoTISS2FA",' + #13#10 +
      '  "path": "' + BinaryPath + '",' + #13#10 +
      '  "type": "stdio",' + #13#10 +
      '  "allowed_extensions": ["autotiss2fa@autofactorauthenticator"]' + #13#10 +
      '}';
    SaveStringToFile(ManifestPath, ManifestContent, False);
  end;
end;

