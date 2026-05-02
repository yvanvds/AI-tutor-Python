; windows/packaging/exe/installer.iss
; Custom Inno Setup script for Python Teacher.
; SourceDir is set to the repo root so [Files] Source: paths are repo-relative.
; OutputDir and SetupIconFile use paths relative to this ISS file.
; Run via: tooling/build_release.ps1  (preferred)
;          iscc.exe windows\packaging\exe\installer.iss  (direct)

#define AppName "Python Teacher"
#define AppVersion "1.0.1"
#define AppPublisher "yvan vander sanden"
#define AppURL "https://github.com/yvanvds/AI-tutor-Python"
#define AppExeName "ai_tutor_python.exe"

[Setup]
AppId={{4B3F2E7A-9C41-4D92-BF5E-91D9B7D2A68C}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
AllowNoIcons=yes
; OutputDir and SetupIconFile are relative to the ISS file directory.
OutputDir=..\..\..\public
OutputBaseFilename=PythonTeacherSetup
SetupIconFile=..\..\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
; SourceDir is relative to the ISS file directory; sets base for [Files] Source: paths.
SourceDir=..\..\..

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Flutter release output (exe + DLLs + data/)
Source: "build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

; Bundled Python interpreter (python-build-standalone, pre-installed packages)
Source: "build\python_bundle\python\*"; \
    DestDir: "{app}\python"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

; Long-lived host script — argv-passed to python.exe by PyRunner
Source: "packages\py_runner\python\host.py"; \
    DestDir: "{app}\py_runner"; \
    Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; \
    Description: "{cm:LaunchProgram,{#AppName}}"; \
    Flags: nowait postinstall skipifsilent
