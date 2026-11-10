import 'package:drift/drift.dart';

part 'base_locale.g.dart';

/// Base SQLite chiffrée du téléphone. Le schéma est défini en SQL dans
/// `tables.drift` (identique, colonne pour colonne, au registre du paquet
/// commun et au schéma PostgreSQL). `dart run build_runner build` génère
/// `base_locale.g.dart`.
@DriftDatabase(include: {'tables.drift'})
class BaseLocale extends _$BaseLocale {
  BaseLocale(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
