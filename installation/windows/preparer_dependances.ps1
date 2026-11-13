<#
  Télécharge les composants tiers inclus dans l'installateur du poste central
  (à lancer une fois sur le PC de construction, ou par l'intégration continue) :
  - binaires PostgreSQL 16 pour Windows x64 (EDB, archive « binaries ») ;
  - Tesseract OCR 5 (extrait de l'installateur UB Mannheim avec 7-Zip) et le
    modèle de langue française ;
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

# Tesseract : fichiers extraits de l'installateur officiel (NSIS) avec 7-Zip,
# livrés tels quels dans <application>\tesseract avec le modèle français.
# L'installateur officiel n'est plus lancé sur le poste : il ignore le dossier
# demandé (il s'installe toujours dans C:\Program Files\Tesseract-OCR), propose
# de désinstaller une version précédente en supprimant son dossier tessdata,
# et télécharge ses modèles de langue sur Internet.
$setup = Telecharger "https://github.com/tesseract-ocr/tesseract/releases/download/5.5.0/tesseract-ocr-w64-setup-$VersionTesseract.exe" 'tesseract-setup.exe'
$fra = Telecharger 'https://github.com/tesseract-ocr/tessdata_fast/raw/main/fra.traineddata' 'fra.traineddata'
$tess = Join-Path $Sortie 'tesseract'
if (-not (Test-Path (Join-Path $tess 'tesseract.exe'))) {
  $septZip = @((Get-Command 7z.exe -ErrorAction SilentlyContinue).Source, "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") |
    Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  if (-not $septZip) { throw '7-Zip est nécessaire pour extraire Tesseract (https://www.7-zip.org).' }
  $tmp = Join-Path $Sortie 'tesseract_tmp'
  if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
  & $septZip x -y "-o$tmp" $setup | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Extraction de Tesseract impossible (7-Zip, code $LASTEXITCODE)." }
  New-Item -ItemType Directory -Force -Path (Join-Path $tess 'tessdata'), (Join-Path $tess 'doc') | Out-Null
  # Moteur et bibliothèques ; ni outils d'entraînement, ni désinstallateur.
  Copy-Item (Join-Path $tmp 'tesseract.exe') $tess
  Copy-Item (Join-Path $tmp '*.dll') $tess
  foreach ($d in 'configs', 'tessconfigs') { Copy-Item -Recurse -Force (Join-Path $tmp "tessdata\$d") (Join-Path $tess "tessdata\$d") }
  Copy-Item (Join-Path $tmp 'doc\*') (Join-Path $tess 'doc')
  Remove-Item -Recurse -Force $tmp
}
Copy-Item -Force $fra (Join-Path $tess 'tessdata\fra.traineddata')
foreach ($f in 'tesseract.exe', 'libtesseract-5.dll', 'libleptonica-6.dll', 'tessdata\fra.traineddata', 'tessdata\configs\tsv', 'doc\LICENSE') {
  if (-not (Test-Path (Join-Path $tess $f))) { throw "Fichier de Tesseract manquant : $f" }
}
# Vérification : Tesseract démarre (bibliothèques complètes) et connaît le français.
$langues = & (Join-Path $tess 'tesseract.exe') --tessdata-dir (Join-Path $tess 'tessdata') --list-langs | Out-String
if ($LASTEXITCODE -ne 0 -or $langues -notmatch '(?m)^fra\s*$') { throw "Tesseract extrait inutilisable (code $LASTEXITCODE) : $langues" }
Write-Host ("Tesseract prêt : {0:N0} Mo" -f ((Get-ChildItem $tess -Recurse -File | Measure-Object Length -Sum).Sum / 1MB))

# Visual C++ (requis par l'application Flutter et par PostgreSQL).
Telecharger 'https://aka.ms/vs/17/release/vc_redist.x64.exe' 'vc_redist.x64.exe' | Out-Null
Write-Host 'Dépendances prêtes.'
