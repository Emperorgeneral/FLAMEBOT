; Inno Setup Script for FlameBot
; Builds installer from dist\FlameBot

#define MyAppName "FlameBot Telegram Copier"
#ifndef MyAppVersion
  #define MyAppVersion "1.0"
#endif
#define MyAppExeName "FlameBot.exe"

[Setup]
AppId={{A5C8D6E4-2E1B-4AF1-9C31-5D8A9C1B7F42}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=FlameCore
AppPublisherURL=https://github.com/Emperorgeneral/FLAMEBOT

DefaultDirName={autopf}\FlameBot
DefaultGroupName=FlameBot
DisableProgramGroupPage=yes

OutputDir=dist
OutputBaseFilename=FlameBot-Setup-v{#MyAppVersion}

Compression=lzma2/ultra64
SolidCompression=yes

ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
SetupLogging=no
PrivilegesRequired=admin

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: desktopicon
Description: Create a desktop shortcut
GroupDescription: Additional icons
Flags: unchecked

[Files]
Source: "..\dist\FlameBot\*"
DestDir: "{app}"
Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\FlameBot"
Filename: "{app}\{#MyAppExeName}"
Description: "Launch FlameBot"
IconFilename: "{app}\{#MyAppExeName}"

Name: "{commondesktop}\FlameBot"
Filename: "{app}\{#MyAppExeName}"
Description: "Launch FlameBot"
Tasks: desktopicon
IconFilename: "{app}\{#MyAppExeName}"

[Run]
Filename: "{app}\{#MyAppExeName}"
Description: Launch FlameBot
Flags: nowait postinstall skipifsilent runasoriginaluser
