[Setup]
AppName=TU Wien Auto 2FA
AppVersion=1.0.3
AppPublisher=TU Wien Auto 2FA
AppComments=This is NOT an official tool by TU Wien. Provided AS IS.
DefaultDirName={pf64}\TU Wien 2FA
DefaultGroupName=TU Wien Auto 2FA
UninstallDisplayIcon={app}\tuwien-2fa-native.exe
OutputBaseFilename=TUWien-Auto-2FA-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64 arm64
ArchitecturesInstallIn64BitMode=x64 arm64
WizardStyle=modern

[Files]
; x64 binary (default)
Source: "tuwien-2fa-native-x64.exe"; DestDir: "{app}"; DestName: "tuwien-2fa-native.exe"; Check: not IsARM64; Flags: ignoreversion
; ARM64 binary
Source: "tuwien-2fa-native-arm64.exe"; DestDir: "{app}"; DestName: "tuwien-2fa-native.exe"; Check: IsARM64; Flags: ignoreversion
Source: "launcher.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "README.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\TU Wien Auto 2FA"; Filename: "{app}\launcher.bat"
Name: "{group}\Uninstall TU Wien Auto 2FA"; Filename: "{uninstallexe}"

[Registry]
Root: HKCU; Subkey: "Software\Mozilla\NativeMessagingHosts\com.tuwien.2fa"; ValueType: string; ValueData: "{app}\tuwien-2fa-native.exe"; Flags: uninsdeletekey

[Run]
Filename: "{app}\launcher.bat"; Description: "Configure TU Wien 2FA"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "{app}\tuwien-2fa-native.exe"; Parameters: "--delete-credential"; Flags: runhidden
