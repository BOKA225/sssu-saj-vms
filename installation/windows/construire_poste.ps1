<#
  Construit l'installateur du poste central : SSSU-SAJ-VMS-Poste-<version>.exe
  Prérequis sur le PC de construction : Flutter 3.24 (Windows desktop activé),
  Visual Studio 2022 (charge « Développement Desktop en C++ »), Inno Setup 6.
#>
param([string]$Version = '1.0.0')
$ErrorActionPreference = 'Stop'
$racine = Resolve-Path (Join-Path $PSScriptRoot '..\..')
& (Join-Path $PSScriptRoot 'preparer_dependances.ps1')

Push-Location (Join-Path $racine 'sssu_windows')
try {
  if (-not (Test-Path 'windows')) {
    # Dossier natif Windows généré par Flutter (absent du dépôt).
    flutter create --platforms=windows --org ci.sssusaj --project-name sssu_windows .
    # Titre de la fenêtre.
    $main = 'windows\runner\main.cpp'
    (Get-Content $main -Raw) -replace 'L"sssu_windows"', 'L"SSSU-SAJ VMS - Poste central"' | Set-Content $main -Encoding UTF8
  }
  flutter pub get
  flutter build windows --release --build-name $Version
  if ($LASTEXITCODE -ne 0) { throw 'Échec de la construction Flutter.' }
} finally { Pop-Location }

$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 introuvable (https://jrsoftware.org/isdl.php).' }
& $iscc "/DVersionApp=$Version" (Join-Path $PSScriptRoot 'sssu_saj_vms.iss')
if ($LASTEXITCODE -ne 0) { throw 'Échec de la compilation de l''installateur.' }
Write-Host "Installateur produit dans $(Join-Path $PSScriptRoot 'sortie')"
