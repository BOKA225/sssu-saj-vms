; SSSU-SAJ VMS - installateur du poste central (Inno Setup 6).
; Installe en une seule procédure : l'application, PostgreSQL 16 (service
; Windows), Tesseract avec le français, le runtime Visual C++, les fichiers de
; mise à jour du schéma ; configure la base, le pare-feu et les raccourcis.
; Construction : construire_poste.ps1 (télécharge les dépendances, compile l'application).

#ifndef VersionApp
  #define VersionApp "1.0.0"
#endif
#define NomApp "SSSU-SAJ VMS - Poste central"
#define Racine "..\.."
#define Build Racine + "\sssu_windows\build\windows\x64\runner\Release"
#define Dep "dependances"

[Setup]
AppId={{6E0B6D1E-5C2A-4D63-9F0A-55A1B3C0D7E1}
AppName={#NomApp}
AppVersion={#VersionApp}
AppPublisher=SSSU-SAJ - District sanitaire de Kouassi-Kouassikro
DefaultDirName={autopf}\SSSU-SAJ VMS
DefaultGroupName=SSSU-SAJ VMS
DisableProgramGroupPage=yes
OutputDir=sortie
OutputBaseFilename=SSSU-SAJ-VMS-Poste-{#VersionApp}
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
MinVersion=10.0
WizardStyle=modern
UninstallDisplayIcon={app}\sssu_windows.exe
SetupLogging=yes
CloseApplications=yes

[Languages]
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "bureau"; Description: "Créer un raccourci sur le Bureau"; Flags: checkedonce

[Files]
; Application Flutter (exécutable, DLL, données, polices).
Source: "{#Build}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Fichiers de mise à jour du schéma, appliqués par l'application au démarrage.
Source: "{#Racine}\sql\postgres\*.sql"; DestDir: "{app}\sql"; Flags: ignoreversion
; PostgreSQL 16 (bin, lib, share).
Source: "{#Dep}\pgsql\*"; DestDir: "{app}\pgsql"; Flags: ignoreversion recursesubdirs createallsubdirs
; Installateurs tiers, utilisés pendant l'installation puis supprimés.
Source: "{#Dep}\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "{#Dep}\tesseract-setup.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "{#Dep}\fra.traineddata"; DestDir: "{app}\tesseract\tessdata"; Flags: ignoreversion
; Scripts de configuration.
Source: "configurer_poste.ps1"; DestDir: "{app}\installation"; Flags: ignoreversion
Source: "desinstaller_poste.ps1"; DestDir: "{app}\installation"; Flags: ignoreversion
Source: "{#Racine}\docs\*.md"; DestDir: "{app}\documentation"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\SSSU-SAJ VMS - Poste central"; Filename: "{app}\sssu_windows.exe"
Name: "{group}\Guide d'utilisation"; Filename: "{app}\documentation\guide_utilisation.md"
Name: "{autodesktop}\SSSU-SAJ VMS"; Filename: "{app}\sssu_windows.exe"; Tasks: bureau

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installation du runtime Visual C++…"; Flags: waituntilterminated
Filename: "{tmp}\tesseract-setup.exe"; Parameters: "/S /D={app}\tesseract"; StatusMsg: "Installation de Tesseract (reconnaissance de texte)…"; Flags: waituntilterminated
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installation\configurer_poste.ps1"" -DossierApplication ""{app}"""; StatusMsg: "Configuration de la base de données et du pare-feu…"; Flags: runhidden waituntilterminated
Filename: "{app}\sssu_windows.exe"; Description: "Lancer SSSU-SAJ VMS"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "{app}\tesseract\tesseract-uninstall.exe"; Parameters: "/S"; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "Tesseract"
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installation\desinstaller_poste.ps1"""; Flags: runhidden waituntilterminated; RunOnceId: "ArretPostgres"

[Code]
// La configuration doit réussir : sinon l'installation est signalée en échec.
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if not FileExists(ExpandConstant('{commonappdata}\SSSU-SAJ VMS\sssu_config.json')) then
    begin
      MsgBox('La configuration du poste n''a pas abouti. Consultez le journal :' + #13#10 +
        ExpandConstant('{commonappdata}\SSSU-SAJ VMS\installation.log'), mbError, MB_OK);
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    MsgBox('Les données du poste central (base, photographies, sauvegardes) sont conservées dans :' + #13#10 +
      ExpandConstant('{commonappdata}\SSSU-SAJ VMS') + #13#10 +
      'Supprimez ce dossier manuellement seulement si vous êtes sûr de ne plus en avoir besoin.', mbInformation, MB_OK);
end;
