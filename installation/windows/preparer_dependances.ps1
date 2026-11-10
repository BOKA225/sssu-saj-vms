<#
  Télécharge les composants tiers inclus dans l'installateur du poste central
  (à lancer une fois sur le PC de construction, ou par l'intégration continue) :
  - binaires PostgreSQL 16 pour Windows x64 (EDB, archive « binaries ») ;
  - Tesseract OCR 5 (UB Mannheim) et le modèle de langue française ;
  - redistribuable Visual C++ 2015-2022 (x64).
  Les versions sont des paramètres : vérifiez les dernières versions publiées.
#>
param(
  [string]$VersionPostgres = '16.10-1',
  [string]$VersionTesseract = '5.5.0.20241111',
  [string]$Sortie = (Join-Path $PSScriptRoot 'dependances')
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force -Path $Sortie | Out-Null

function Telecharger([string]$url, [string]$fichier) {
  $cible = Join-Path $Sortie $fichier
  if (Test-Path $cible) { Write-Host "Déjà présent : $fichier"; return $cible }
  Write-Host "Téléchargement : $url"
  Invoke-WebRequest -Uri $url -OutFile $cible -UseBasicParsing
  Write-Host ("  SHA-256 : " + (Get-FileHash $cible -Algorithm SHA256).Hash)
  return $cible
}

# PostgreSQL : seuls bin, lib et share sont gardés (ni pgAdmin, ni StackBuilder, ni documentation).
$zip = Telecharger "https://get.enterprisedb.com/postgresql/postgresql-$VersionPostgres-windows-x64-binaries.zip" "postgresql-$VersionPostgres.zip"
$pg = Join-Path $Sortie 'pgsql'
if (-not (Test-Path (Join-Path $pg 'bin\pg_ctl.exe'))) {
  $tmp = Join-Path $Sortie 'pgsql_tmp'
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  New-Item -ItemType Directory -Force -Path $pg | Out-Null
  foreach ($d in 'bin', 'lib', 'share') { Copy-Item -Recurse -Force (Join-Path $tmp "pgsql\$d") (Join-Path $pg $d) }
  Remove-Item -Recurse -Force $tmp
}
foreach ($outil in 'initdb.exe', 'pg_ctl.exe', 'psql.exe', 'pg_dump.exe', 'pg_restore.exe', 'pg_isready.exe') {
  if (-not (Test-Path (Join-Path $pg "bin\$outil"))) { throw "Outil PostgreSQL manquant : $outil" }
}
if (-not (Test-Path (Join-Path $pg 'share\extension\unaccent.control'))) { throw 'Extension unaccent absente des binaires PostgreSQL.' }

# Tesseract (installateur NSIS, installé en silence dans le dossier de l'application).
Telecharger "https://github.com/tesseract-ocr/tesseract/releases/download/5.5.0/tesseract-ocr-w64-setup-$VersionTesseract.exe" 'tesseract-setup.exe' | Out-Null
Telecharger 'https://github.com/tesseract-ocr/tessdata_fast/raw/main/fra.traineddata' 'fra.traineddata' | Out-Null

# Visual C++ (requis par l'application Flutter et par PostgreSQL).
Telecharger 'https://aka.ms/vs/17/release/vc_redist.x64.exe' 'vc_redist.x64.exe' | Out-Null
Write-Host 'Dépendances prêtes.'
