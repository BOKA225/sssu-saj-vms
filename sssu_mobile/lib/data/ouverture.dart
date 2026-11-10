import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

import '../securite/coffre.dart';
import 'base_locale.dart';

Future<File> _fichierBase() async =>
    File(p.join((await getApplicationSupportDirectory()).path, 'sssu_saj_vms.db'));

/// Supprime le fichier de la base (effacement à distance), base fermée.
Future<void> supprimerBaseLocale() async {
  final f = await _fichierBase();
  for (final x in [f, File('${f.path}-wal'), File('${f.path}-shm'), File('${f.path}-journal')]) {
    if (await x.exists()) await x.delete();
  }
}

/// Ouvre (ou crée) la base chiffrée du téléphone. Le fichier est placé dans
/// l'espace privé de l'application et chiffré par SQLCipher avec une clé
/// conservée dans le stockage sécurisé.
Future<BaseLocale> ouvrirBaseLocale(Coffre coffre) async {
  if (Platform.isAndroid) {
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
    await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
  }
  final fichier = await _fichierBase();
  final cle = await coffre.cleBase();
  return BaseLocale(NativeDatabase.createInBackground(
    fichier,
    isolateSetup: () {
      if (Platform.isAndroid) open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
    },
    setup: (db) {
      // La clé doit être fournie avant toute autre instruction.
      db.execute("PRAGMA key = \"x'$cle'\";");
      final verif = db.select('PRAGMA cipher_version;');
      if (verif.isEmpty) {
        throw StateError('SQLCipher indisponible : la base ne peut pas être chiffrée.');
      }
      db.execute('PRAGMA foreign_keys = ON;');
    },
  ));
}
