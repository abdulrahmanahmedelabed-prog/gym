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
; التحديث يثبت فوق النسخة القديمة ولا يمس بيانات النادي (AppData\Nadi Gym).
; عند إلغاء التثبيت: يُحذف البرنامج كاملاً، ويُسأل المستخدم هل يحذف بيانات النادي أيضاً (الافتراضي: لا).

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

[UninstallDelete]
; ملفات ينشئها البرنامج بجانبه (إن وُجدت)
Type: filesandordirs; Name: "{app}"

[Code]
// سؤال حذف البيانات عند إلغاء التثبيت (لا يُسأل في الإلغاء الصامت، ولا تُحذف البيانات فيه)
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    DataDir := ExpandConstant('{userappdata}\Nadi Gym');
    if DirExists(DataDir) and not UninstallSilent then
    begin
      if MsgBox('Also delete all gym data (members, invoices, backups) from this computer?' + #13#10 +
                'This cannot be undone. Choose No if you plan to reinstall.' + #13#10#13#10 +
                'هل تريد حذف بيانات النادي أيضاً (الأعضاء، الفواتير، النسخ الاحتياطية) من هذا الجهاز؟' + #13#10 +
                'لا يمكن التراجع. اختر «لا» إن كنت ستعيد التثبيت.',
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(DataDir, True, True, True);
    end;
  end;
end;
