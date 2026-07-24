[Setup]
AppName=TU Wien Auto 2FA
AppVersion=1.1.0
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
; Firefox reads the *default* value of this key as a path to the native
; messaging manifest JSON file (not the binary). The manifest is written by
; the [Code] step below and additionally by the launcher on manual runs.
Root: HKCU; Subkey: "Software\Mozilla\NativeMessagingHosts\com.tuwien.2fa"; ValueType: string; ValueData: "{app}\com.tuwien.2fa.json"; Flags: uninsdeletekey

[Run]
Filename: "{app}\launcher.bat"; Description: "Configure TU Wien 2FA"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "{app}\tuwien-2fa-native.exe"; Parameters: "--delete-credential"; Flags: runhidden

[Code]
function GetAppPath(Param: String): String;
begin
  Result := ExpandConstant('{app}');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ManifestPath, AppDir, BinaryPath, ManifestContent: String;
begin
  if CurStep = ssPostInstall then
  begin
    AppDir := ExpandConstant('{app}');
    BinaryPath := AppDir + '\tuwien-2fa-native.exe';
    ManifestPath := AppDir + '\com.tuwien.2fa.json';
    ManifestContent :=
      '{' + #13#10 +
      '  "name": "com.tuwien.2fa",' + #13#10 +
      '  "description": "Native host for TU Wien Auto 2FA",' + #13#10 +
      '  "path": "' + BinaryPath + '",' + #13#10 +
      '  "type": "stdio",' + #13#10 +
      '  "allowed_extensions": ["tuwien-auto-2fa@aGreatTUWienStudent"]' + #13#10 +
      '}';
    SaveStringToFile(ManifestPath, ManifestContent, False);
  end;
end;
