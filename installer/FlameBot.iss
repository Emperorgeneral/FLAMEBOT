; Inno Setup Script for FlameBot
; Builds an installer from the portable build at dist\FlameBot

#define MyAppName "FlameBot Telegram Copier"
#ifndef MyAppVersion
  #define MyAppVersion "1.0"
#endif
#define MyAppExeName "FlameBot.exe"

[Setup]
; FIXED UUID (properly closed)
AppId={{A5C8D6E4-2E1B-4AF1-9C31-5D8A9C1B7F42}}

AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=FlameCore
AppPublisherURL=https://github.com/Emperorgeneral/FLAMEBOT

; Install into Program Files
DefaultDirName={autopf}\FlameBot
DefaultGroupName=FlameBot

DisableProgramGroupPage=yes

; Output location
OutputDir=dist
OutputBaseFilename=FlameBot-Setup-v{#MyAppVersion}

Compression=lzma2/ultra64
SolidCompression=yes

ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
SetupLogging=yes

; Installer requires admin only for install
PrivilegesRequired=admin

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon";
Description: "Create a &desktop shortcut";
GroupDescription: "Additional icons:";
Flags: unchecked

[Files]
; Copy everything from the built portable folder
Source: "..\dist\FlameBot\*";
DestDir: "{app}";
Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
; Start menu shortcut
Name: "{group}\FlameBot";
Filename: "{app}\{#MyAppExeName}"

; Desktop shortcut (optional)
Name: "{commondesktop}\FlameBot";
Filename: "{app}\{#MyAppExeName}";
Tasks: desktopicon

[Run]
; Launch after installation
Filename: "{app}\{#MyAppExeName}";
Description: "Launch FlameBot";
Flags: nowait postinstall skipifsilent runasoriginaluser
