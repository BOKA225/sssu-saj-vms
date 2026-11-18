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
  /// 3 (version 1.6.0) : visite d'aptitude (colonnes `visite.type_visite`,
  /// `aptitude`, `aptitude_restrictions`).
  /// 4 (version 1.8.0) : vaccination (tables `vaccin` et `suivi_vaccinal`,
  /// colonnes `visite.hpv` et `hpv_motif`).
  @override
  int get schemaVersion => 4;

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
            if (de < 3) {
              for (final c in [visite.typeVisite, visite.aptitude, visite.aptitudeRestrictions]) {
                await _ajouterColonne(m, visite, c);
              }
            }
            if (de < 4) {
              for (final c in [visite.hpv, visite.hpvMotif]) {
                await _ajouterColonne(m, visite, c);
              }
              for (final t in <TableInfo>[vaccin, suiviVaccinal]) {
                await _creerTable(m, t);
              }
            }
          });
          await customStatement('PRAGMA foreign_keys = ON');
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Crée une table si elle n'existe pas encore (migration rejouée).
  Future<void> _creerTable(Migrator m, TableInfo table) async {
    final existe = await customSelect("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: [Variable(table.actualTableName)]).get();
    if (existe.isEmpty) await m.createTable(table);
  }

  /// Ajoute une colonne si elle n'existe pas encore (migration rejouée).
  Future<void> _ajouterColonne(Migrator m, TableInfo table, GeneratedColumn colonne) async {
    final existe = await customSelect('SELECT 1 FROM pragma_table_info(?) WHERE name = ?',
        variables: [Variable(table.actualTableName), Variable(colonne.name)]).get();
    if (existe.isEmpty) await m.addColumn(table, colonne);
  }
}
