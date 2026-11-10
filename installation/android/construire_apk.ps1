<#
  Construit l'APK Android de SSSU-SAJ VMS (Windows).
  Prérequis : Flutter 3.24, Android SDK (Android Studio), JDK 17.
  Signature : android\key.properties (voir LISEZMOI.md).
#>
param([string]$Version = '1.0.0', [int]$NumeroBuild = 1)
$ErrorActionPreference = 'Stop'
$mobile = Resolve-Path (Join-Path $PSScriptRoot '..\..\sssu_mobile')
Push-Location $mobile
try {
  if (-not (Test-Path 'android')) { flutter create --platforms=android --org ci.sssusaj --project-name sssu_mobile . }
  dart run ..\installation\android\configurer_android.dart
  flutter pub get
  dart run build_runner build --delete-conflicting-outputs
  flutter build apk --release --build-name $Version --build-number $NumeroBuild
  if ($LASTEXITCODE -ne 0) { throw 'Échec de la construction.' }
  $apk = 'build\app\outputs\flutter-apk\app-release.apk'
  $cible = Join-Path $PSScriptRoot "sortie\SSSU-SAJ-VMS-$Version.apk"
  New-Item -ItemType Directory -Force -Path (Split-Path $cible) | Out-Null
  Copy-Item $apk $cible -Force
  Write-Host "APK : $cible"
} finally { Pop-Location }
