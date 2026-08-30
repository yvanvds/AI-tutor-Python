; windows/packaging/exe/installer.iss
; Custom Inno Setup script for Python Teacher.
; SourceDir is set to the repo root, so [Files] Source: paths AND
; SetupIconFile are repo-relative. OutputDir is relative to this ISS file's
; directory (resolved before SourceDir is applied).
; Run via: tooling/build_release.ps1  (which cd's to this directory first)

; --- version, passed in by the build script (#55) ----------------------------
; AppVersion was hardcoded here and never bumped, so every installer ever built
; registered itself with Windows as 1.0.1: Apps & Features and the uninstall
; key's DisplayVersion said 1.0.1 no matter which release was actually
; installed. pubspec.yaml is the single source of truth, and
; tooling/build_release.ps1 passes it through after the step-1 bump:
;
;   ISCC /DAppVersion=2.0.0+17 /DAppVersionInfo=2.0.0.17 installer.iss
;
; Two defines because they are not interchangeable: AppVersion is free text and
; carries the full `x.y.z+build` exactly as the app's own About panel shows it,
; while VersionInfoVersion (the .exe's file properties) must be numeric
; `a.b.c.d` — a '+' there is a compile error. Both default so that a bare
; `ISCC installer.iss` still compiles for a syntax check.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AppVersionInfo
  #define AppVersionInfo "0.0.0.0"
#endif

#define AppName "Python Teacher"
#define AppPublisher "yvan vander sanden"
#define AppURL "https://github.com/yvanvds/AI-tutor-Python"
#define AppExeName "ai_tutor_python.exe"

[Setup]
AppId={{4B3F2E7A-9C41-4D92-BF5E-91D9B7D2A68C}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
VersionInfoVersion={#AppVersionInfo}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}

; --- per-user install (#49) --------------------------------------------------
; The load-bearing decision, not a preference. A machine-wide install under
; Program Files needs UAC elevation for every single update, so the silent
; installer the updater launches raised a prompt a student without local admin
; rights could not answer — and the app had already exited by then, which made
; the failure invisible. Installing into the student's own %LOCALAPPDATA% lets
; the running app replace its own files with no elevation at all, so /SILENT
; really is silent. No Dart-side change can fix that; it has to be fixed here.
;
; Already-installed machines are not migrated: an existing machine-wide install
; keeps its Program Files location and its UAC prompt until it is uninstalled
; and reinstalled once. The AppId below must not change either way.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={localappdata}\Programs\{#AppName}
UsePreviousAppDir=yes
DefaultGroupName={#AppName}
AllowNoIcons=yes

; --- upgrade behaviour (#49) -------------------------------------------------
; Let the restart manager close the running copy rather than failing on a
; locked .exe. RestartApplications is off on purpose: the [Run] section below
; brings the app back itself when the updater passes /RELAUNCH=1, and letting
; the restart manager *also* do it is how a student ends up with two windows.
CloseApplications=yes
RestartApplications=no
; OutputDir is relative to SourceDir (set below to the repo root) because
; SourceDir overrides the default '.iss-file directory' base for OutputDir too.
OutputDir=public
OutputBaseFilename=PythonTeacherSetup
; SetupIconFile is relative to SourceDir.
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
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
; {autodesktop}, not {commondesktop}: an unelevated install cannot write to the
; all-users desktop, and this setup no longer elevates (#49).
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
; Two mutually exclusive relaunches, kept exclusive by the Check guards (#49).
;
; The first is the ordinary "run it now?" checkbox of an interactive install.
; `skipifsilent` means it never fires under /SILENT — which is exactly why the
; second one has to exist: the updater runs this installer silently, so without
; it the app updated and simply never came back.
Filename: "{app}\{#AppExeName}"; \
    Description: "{cm:LaunchProgram,{#AppName}}"; \
    Flags: nowait postinstall skipifsilent; \
    Check: not WantsRelaunch
Filename: "{app}\{#AppExeName}"; Flags: nowait; Check: WantsRelaunch

[Code]
{ True when this installer was started by the app's own updater, which passes
  /RELAUNCH=1 (see kSilentInstallArguments in lib/core/update_bootstrap.dart). }
function WantsRelaunch: Boolean;
begin
  Result := ExpandConstant('{param:RELAUNCH|0}') = '1';
end;
