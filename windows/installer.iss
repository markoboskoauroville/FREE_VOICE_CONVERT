; installer.iss: the Windows installer (Inno Setup 6). It copies the app and the engine, then runs engine\setup.ps1
; in a visible window: uv, Python 3.11, torch (CUDA when an NVIDIA card is present), Seed-VC and every model.
; If that is interrupted, the app's INSTALL button goes on from where it stopped.
#ifndef AppVersion
  #define AppVersion "1"
#endif
[Setup]
AppId={{15906414-034A-46A1-9FF9-74DC4D187F59}
AppName=Free Voice Convert Equalizer
AppVersion={#AppVersion}
AppPublisher=Mantra Productions
AppPublisherURL=https://freevoiceconvert.pages.dev
DefaultDirName={localappdata}\Programs\Free Voice Convert
DefaultGroupName=Free Voice Convert
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=FreeVoiceConvert-{#AppVersion}-Setup
SetupIconFile=icon.ico
UninstallDisplayIcon={app}\FreeVoiceConvert.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
LicenseFile=..\LICENSE

[Files]
Source: "bin\Release\net48\FreeVoiceConvert.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "bin\Release\net48\FreeVoiceConvert.exe.config"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "..\engine\*.py"; DestDir: "{app}\engine"; Flags: ignoreversion
Source: "..\engine\setup.ps1"; DestDir: "{app}\engine"; Flags: ignoreversion
Source: "..\engine\requirements.txt"; DestDir: "{app}\engine"; Flags: ignoreversion
Source: "..\engine\PINS"; DestDir: "{app}\engine"; Flags: ignoreversion

[Icons]
Name: "{group}\Free Voice Convert Equalizer"; Filename: "{app}\FreeVoiceConvert.exe"
Name: "{userdesktop}\Free Voice Convert Equalizer"; Filename: "{app}\FreeVoiceConvert.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "A shortcut on the desktop"; Flags: unchecked

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\engine\setup.ps1"""; StatusMsg: "Downloading Python, torch, Seed-VC and the voice models (about 3 GB, once)..."; Flags: waituntilterminated
Filename: "{app}\FreeVoiceConvert.exe"; Description: "Open Free Voice Convert Equalizer"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{localappdata}\FreeVoiceConvert\venv"
Type: filesandordirs; Name: "{localappdata}\FreeVoiceConvert\python"
Type: filesandordirs; Name: "{localappdata}\FreeVoiceConvert\uv-cache"
Type: filesandordirs; Name: "{localappdata}\FreeVoiceConvert\seed-vc"
Type: filesandordirs; Name: "{localappdata}\FreeVoiceConvert\models"
Type: filesandordirs; Name: "{localappdata}\FreeVoiceConvert\bin"
