; ملف تثبيت نادي جيم لويندوز (Inno Setup 6)
; يُبنى آلياً في GitHub Actions: iscc /DAppVersion=1.0.N installer\nadi_gym.iss

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6E2B7A31-4C1D-4F5E-9A8B-2D3C4E5F6071}
AppName=Nadi Gym
AppVersion={#AppVersion}
AppPublisher=Nadi Gym
DefaultDirName={autopf}\Nadi Gym
DefaultGroupName=Nadi Gym
; تثبيت للمستخدم الحالي بدون صلاحيات مدير
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\dist
OutputBaseFilename=nadi-gym-windows-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\nadi_gym.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; بيانات النادي في AppData لا تُحذف عند إلغاء التثبيت أو التحديث

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Nadi Gym"; Filename: "{app}\nadi_gym.exe"
Name: "{group}\{cm:UninstallProgram,Nadi Gym}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Nadi Gym"; Filename: "{app}\nadi_gym.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\nadi_gym.exe"; Description: "{cm:LaunchProgram,Nadi Gym}"; Flags: nowait postinstall skipifsilent
