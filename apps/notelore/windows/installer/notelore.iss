; The Windows setup (Inno Setup 6). Notelore is one person's app: it installs for
; the signed-in user only (%LOCALAPPDATA%\Programs\Notelore), never needing admin
; rights; /ALLUSERS on the command line still installs for everyone (#493).
; The release workflow builds it with
;   iscc /DAppVersion=1.2.3 /DSourceDir=<flutter Release folder> /O<out> /F<name> notelore.iss
; The in-app updater runs it with /VERYSILENT /SUPPRESSMSGBOXES /NORESTART, after
; which it starts the app again. An earlier all-users copy is removed after one
; UAC prompt. The notes, in the user's app data, are never touched.

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
; {autopf}: Program Files for all users, %LOCALAPPDATA%\Programs for one.
DefaultDirName={autopf}\Notelore
DisableProgramGroupPage=yes
; One person's app: no admin, for the signed-in user; an update never keeps an
; earlier all-users choice (#493).
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline
UsePreviousPrivileges=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\notelore.exe
; The setup wears the app's mark, not Inno Setup's.
SetupIconFile=..\runner\resources\app_icon.ico
; An update lands in the same folder: tell Windows the icons changed, or the
; taskbar and Start keep the old one from the icon cache (#403).
ChangesAssociations=yes
; Installed apps shows the version in its own column: the name is just the name.
UninstallDisplayName=Notelore
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
; As the signed-in user, never as the elevated setup: started as admin after an
; update, the app failed to start (#488).
Filename: "{app}\notelore.exe"; Description: "{cm:LaunchProgram,Notelore}"; Flags: nowait postinstall skipifsilent runasoriginaluser
Filename: "{app}\notelore.exe"; Flags: nowait runasoriginaluser; Check: LaunchAfterSilentInstall

[Code]
const
  AllUsersKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{8F3C2A51-6E2B-4D7A-9C1E-5B0A7D3E9F42}_is1';

// An earlier all-users copy in Program Files goes once this per-user one is in,
// after one UAC prompt; declined, it stays (#493).
procedure CurStepChanged(CurStep: TSetupStep);
var
  Uninstaller: String;
  Code: Integer;
begin
  if (CurStep = ssPostInstall) and not IsAdminInstallMode and
     RegQueryStringValue(HKLM, AllUsersKey, 'UninstallString', Uninstaller) then
    ShellExec('runas', RemoveQuotes(Uninstaller), '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART',
      '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

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
