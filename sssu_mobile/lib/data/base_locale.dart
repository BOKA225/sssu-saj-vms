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
  /// 2 (version 1.2.0) : grille d'inspection nationale (rubriques B à J,
  /// colonne `inspection.grille`).
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, de, vers) async {
          // Clés étrangères suspendues : la table des critères est recréée
          // (nouvelle contrainte sur la rubrique), ses réponses gardées.
          await customStatement('PRAGMA foreign_keys = OFF');
          await transaction(() async {
            if (de < 2) {
              await m.alterTable(TableMigration(critereInspection));
              await m.addColumn(inspection, inspection.grille);
            }
          });
          await customStatement('PRAGMA foreign_keys = ON');
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
