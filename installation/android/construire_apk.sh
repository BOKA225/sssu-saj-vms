#!/usr/bin/env bash
# Construit l'APK Android de SSSU-SAJ VMS (Linux ou macOS).
# Prérequis : Flutter 3.24, Android SDK, JDK 17. Signature : android/key.properties.
set -euo pipefail
VERSION="${1:-1.0.0}"; BUILD="${2:-1}"
ICI="$(cd "$(dirname "$0")" && pwd)"
cd "$ICI/../../sssu_mobile"
[ -d android ] || flutter create --platforms=android --org ci.sssusaj --project-name sssu_mobile .
dart run ../installation/android/configurer_android.dart
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release --build-name "$VERSION" --build-number "$BUILD"
mkdir -p "$ICI/sortie"
cp build/app/outputs/flutter-apk/app-release.apk "$ICI/sortie/SSSU-SAJ-VMS-$VERSION.apk"
echo "APK : $ICI/sortie/SSSU-SAJ-VMS-$VERSION.apk"
