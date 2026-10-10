; The Windows setup (Inno Setup 6). Per-user: no admin rights, installs into
; %LOCALAPPDATA%\Programs\Notelore. The release workflow builds it with
;   iscc /DAppVersion=1.2.3 /DSourceDir=<flutter Release folder> /O<out> /F<name> notelore.iss
; The in-app updater runs it with /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
; /DIR=<the current folder>, after which it starts the app again.
; Notes in ~/Notelore are never touched, not even by the uninstaller.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
; Never change the AppId: Windows recognises installed versions by it.
AppId={{8F3C2A51-6E2B-4D7A-9C1E-5B0A7D3E9F42}
AppName=Notelore
AppVersion={#AppVersion}
AppPublisher=mfozmen
AppPublisherURL=https://github.com/mfozmen/notelore
DefaultDirName={localappdata}\Programs\Notelore
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\notelore.exe
; An update runs while the old app may still be closing: close it, never ask.
CloseApplications=force
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputBaseFilename=notelore-setup

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "tr"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Notelore"; Filename: "{app}\notelore.exe"
Name: "{autodesktop}\Notelore"; Filename: "{app}\notelore.exe"; Tasks: desktopicon

[Run]
; A person installing gets the usual "Launch Notelore" box; the silent update starts it itself.
Filename: "{app}\notelore.exe"; Description: "{cm:LaunchProgram,Notelore}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\notelore.exe"; Flags: nowait; Check: LaunchAfterSilentInstall

[Code]
// /NOLAUNCH: a silent install that does not start the app (CI's install check).
function LaunchAfterSilentInstall(): Boolean;
var
  I: Integer;
begin
  Result := WizardSilent;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/NOLAUNCH') = 0 then
      Result := False;
end;
