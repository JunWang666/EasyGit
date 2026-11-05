; Inno Setup script for EasyGit.
; Build first:  flutter build windows --release
; Then compile: ISCC.exe windows\installer\easygit.iss

#define AppName "EasyGit"
#define AppVersion "0.2.0"
#define AppExe "easygit.exe"
#define ReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{6B0E2C1A-4E7D-4B8F-9C2A-EA5761F0A1B3}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppName}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=EasyGit-{#AppVersion}-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; "Open in EasyGit" in the Windows 11 Explorer context menu. Only when the
; signed package exists (windows\shell_extension\package.ps1); otherwise users
; can install it from Settings > External Tools.
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""Add-AppxPackage -Path '{app}\shell\EasyGit.ExplorerMenu.msix' -ExternalLocation '{app}' -ForceUpdateFromAnyVersion"""; Flags: runhidden; StatusMsg: "Adding the Explorer context menu..."; Check: FileExists(ExpandConstant('{app}\shell\EasyGit.ExplorerMenu.msix'))
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""Get-AppxPackage -Name EasyGit.ExplorerMenu | Remove-AppxPackage"""; Flags: runhidden; RunOnceId: "RemoveExplorerMenu"
Filename: "reg.exe"; Parameters: "delete HKCU\Software\Classes\Directory\shell\EasyGit /f"; Flags: runhidden; RunOnceId: "RemoveClassicMenu1"
Filename: "reg.exe"; Parameters: "delete HKCU\Software\Classes\Directory\Background\shell\EasyGit /f"; Flags: runhidden; RunOnceId: "RemoveClassicMenu2"
