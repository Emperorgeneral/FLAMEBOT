; Inno Setup Script for FlameBot
; Builds installer from portable build in dist\FlameBot

#define MyAppName "FlameBot Telegram Copier"
#ifndef MyAppVersion
  #define MyAppVersion "1.0"
#endif
#define MyAppExeName "FlameBot.exe"

[Setup]
AppId={{A5C8D6E4-2E1B-4AF1-9C31-5D8A9C1B7F42}} ; fixed missing closing brace
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=FlameCore
AppPublisherURL=https://github.com/Emperorgeneral/FLAMEBOT
DefaultDirName={autopf}\FlameBot
DefaultGroupName=FlameBot
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=FlameBot-Setup-v{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
SetupLogging=yes
PrivilegesRequired=admin

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "..\dist\FlameBot\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\FlameBot"; Filename: "{app}\{#MyAppExeName}"
Name: "{commondesktop}\FlameBot"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "cmd.exe"; Parameters: /c netsh advfirewall firewall delete rule name=FlameBot_Outbound program="{app}\{#MyAppExeName}"; Flags: runhidden; StatusMsg: "Removing previous Windows Firewall rule (if any)..."

Filename: "cmd.exe"; Parameters: /c netsh advfirewall firewall add rule name=FlameBot_Outbound dir=out action=allow program="{app}\{#MyAppExeName}" enable=yes; Flags: runhidden; StatusMsg: "Creating Windows Firewall rule for FlameBot (outbound allow)..."

Filename: "{app}\{#MyAppExeName}"; Description: "Launch FlameBot"; Flags: nowait postinstall skipifsilent runasoriginaluser

[UninstallRun]
Filename: "cmd.exe"; Parameters: /c netsh advfirewall firewall delete rule name=FlameBot_Outbound program="{app}\{#MyAppExeName}"; Flags: runhidden
