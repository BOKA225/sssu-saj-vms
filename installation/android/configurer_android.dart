// Configure le projet Android généré par `flutter create` pour SSSU-SAJ VMS
// (à lancer depuis sssu_mobile : `dart run ../installation/android/configurer_android.dart`).
//
// - MainActivity : FlutterFragmentActivity, captures d'écran interdites ;
// - manifeste : permissions (caméra, réseau, Wi-Fi), pas de sauvegarde
//   Android des données, HTTPS seulement, nom de l'application ;
// - Gradle : Android 8.0 minimum (minSdk 26), signature de la version
//   publiée par android/key.properties (absent : signature de débogage, avec
//   un avertissement).
// Idempotent : peut être relancé sans effet de bord.
import 'dart:io';

void main() {
  final android = Directory('android');
  if (!android.existsSync()) {
    stderr.writeln('Dossier android/ absent : lancez d\'abord '
        '`flutter create --platforms=android --org ci.sssusaj --project-name sssu_mobile .`');
    exit(1);
  }
  _mainActivity();
  _manifeste();
  _gradle();
  _proguard();
  stdout.writeln('Projet Android configuré.');
}

void _mainActivity() {
  final f = Directory('android/app/src/main')
      .listSync(recursive: true)
      .whereType<File>()
      .firstWhere((f) => f.path.endsWith('MainActivity.kt'), orElse: () => throw StateError('MainActivity.kt introuvable'));
  final paquet = RegExp(r'^package\s+([\w.]+)', multiLine: true).firstMatch(f.readAsStringSync())!.group(1);
  f.writeAsStringSync('''package $paquet

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity est requis par flutter_secure_storage et mobile_scanner.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Données médicales de mineurs : captures d'écran interdites, aperçu masqué.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }
}
''');
}

void _manifeste() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  var s = f.readAsStringSync();
  const permissions = [
    'android.permission.INTERNET',
    'android.permission.CAMERA',
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.ACCESS_WIFI_STATE',
  ];
  for (final p in permissions) {
    if (!s.contains('"$p"')) {
      s = s.replaceFirstMapped(
          RegExp(r'<manifest[^>]*>'), (m) => '${m.group(0)}\n    <uses-permission android:name="$p" />');
    }
  }
  s = s.replaceFirstMapped(RegExp(r'<application([^>]*)>', dotAll: true), (m) {
    var a = m.group(1)!;
    void attribut(String nom, String valeur) {
      final re = RegExp('$nom="[^"]*"');
      a = re.hasMatch(a) ? a.replaceAll(re, '$nom="$valeur"') : '$a\n        $nom="$valeur"';
    }

    attribut('android:label', 'SSSU-SAJ VMS');
    attribut('android:allowBackup', 'false');
    attribut('android:fullBackupContent', 'false');
    attribut('android:usesCleartextTraffic', 'false');
    return '<application$a>';
  });
  f.writeAsStringSync(s);
}

void _gradle() {
  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  final f = kts.existsSync() ? kts : groovy;
  final k = f == kts;
  var s = f.readAsStringSync();

  // SDK de compilation exigé par les modules (caméra, stockage sécurisé…).
  s = s.replaceAll(RegExp(r'compileSdk(Version)?\s*=?\s*flutter\.compileSdkVersion'), k ? 'compileSdk = 35' : 'compileSdkVersion 35');

  // Android 8.0 minimum.
  s = s.replaceAll(RegExp(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion'), k ? 'minSdk = 26' : 'minSdkVersion 26');

  if (!s.contains('key.properties')) {
    final lecture = k
        ? '''
import java.util.Properties
import java.io.FileInputStream

val proprietesCle = Properties()
val fichierCle = rootProject.file("key.properties")
if (fichierCle.exists()) {
    proprietesCle.load(FileInputStream(fichierCle))
}
'''
        : '''
def proprietesCle = new Properties()
def fichierCle = rootProject.file('key.properties')
if (fichierCle.exists()) {
    fichierCle.withReader('UTF-8') { proprietesCle.load(it) }
}
''';
    // Après le bloc plugins { … }.
    s = s.replaceFirstMapped(RegExp(r'plugins\s*\{[^}]*\}\n'), (m) => '${m.group(0)}$lecture');
    final signature = k
        ? '''
    signingConfigs {
        create("publication") {
            if (fichierCle.exists()) {
                keyAlias = proprietesCle["keyAlias"] as String
                keyPassword = proprietesCle["keyPassword"] as String
                storeFile = file(proprietesCle["storeFile"] as String)
                storePassword = proprietesCle["storePassword"] as String
            }
        }
    }
'''
        : '''
    signingConfigs {
        publication {
            if (fichierCle.exists()) {
                keyAlias proprietesCle['keyAlias']
                keyPassword proprietesCle['keyPassword']
                storeFile file(proprietesCle['storeFile'])
                storePassword proprietesCle['storePassword']
            }
        }
    }
''';
    s = s.replaceFirstMapped(RegExp(r'android\s*\{\n'), (m) => '${m.group(0)}$signature');
    s = k
        ? s.replaceAll('signingConfig = signingConfigs.getByName("debug")',
            'signingConfig = if (fichierCle.exists()) signingConfigs.getByName("publication") else signingConfigs.getByName("debug")')
        : s.replaceAll('signingConfig signingConfigs.debug',
            'signingConfig fichierCle.exists() ? signingConfigs.publication : signingConfigs.debug');
  }
  if (!s.contains('proguard-rules.pro')) {
    s = s.replaceFirstMapped(RegExp(r'release\s*\{\n'), (m) => k
        ? '${m.group(0)}            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")\n'
        : "${m.group(0)}            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'\n");
  }
  f.writeAsStringSync(s);
  if (!File('android/key.properties').existsSync()) {
    stderr.writeln('ATTENTION : android/key.properties absent — l\'APK sera signé avec la clé de débogage '
        '(acceptable pour un essai, pas pour la diffusion). Voir installation/android/LISEZMOI.md.');
  }
}

/// Règles R8 de la version publiée. Le module ML Kit référence les modèles
/// chinois, japonais, coréen et devanagari, non embarqués (seul l'alphabet
/// latin sert ici) : ces références sont ignorées. Le module Flutter ajoute
/// automatiquement `android/app/proguard-rules.pro` à la compilation.
void _proguard() {
  const regles = '''
# SSSU-SAJ VMS — généré par installation/android/configurer_android.dart
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
''';
  File('android/app/proguard-rules.pro').writeAsStringSync(regles);
}
