import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:sssu_mobile/data/base_locale.dart' hide Utilisateur, Eleve;

/// Mise à jour d'un téléphone installé avant la version 1.2.0 (schéma 1) :
/// nouvelles rubriques de la grille nationale acceptées, colonne
/// `inspection.grille` ajoutée, critères et clés étrangères conservés.
void main() {
  test('base du téléphone en schéma 1 mise à jour en schéma 2', () async {
    final dossier = Directory.systemTemp.createTempSync('sssu_migration');
    addTearDown(() => dossier.deleteSync(recursive: true));
    final fichier = File('${dossier.path}/base.db');
    BaseLocale ouvrir() => BaseLocale(NativeDatabase(fichier, setup: (d) => d.execute('PRAGMA foreign_keys = ON;')));

    // 1. Base créée par la version actuelle, ramenée au schéma 1.
    var db = ouvrir();
    await db.customSelect('SELECT 1').get();
    final ddl =
        (await db.customSelect("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'critere_inspection'").getSingle())
            .read<String>('sql');
    final nouvelles = RubriqueInspection.actuelles.map((r) => ", '${r.code}'").join();
    expect(ddl, contains(nouvelles));
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement('PRAGMA legacy_alter_table = ON');
    await db.customStatement('ALTER TABLE critere_inspection RENAME TO critere_ancien');
    await db.customStatement(ddl.replaceAll(nouvelles, ''));
    await db.customStatement('DROP TABLE critere_ancien');
    await db.customStatement('ALTER TABLE inspection DROP COLUMN grille');
    await db.customStatement(
        "INSERT INTO critere_inspection (id, created_at, updated_at, rubrique, code, libelle) VALUES ('ancien', 0, 0, 'eau_potable', 'x', 'Eau')");
    await expectLater(
        db.customStatement(
            "INSERT INTO critere_inspection (id, created_at, updated_at, rubrique, code, libelle) VALUES ('b1', 0, 0, 'eau_boisson', 'B1', 'Eau')"),
        throwsA(anything),
        reason: 'schéma 1 : rubrique inconnue');
    await db.customStatement('PRAGMA user_version = 1');
    await db.close();

    // 2. Réouverture : migration.
    db = ouvrir();
    final c = criteresGrille.first;
    await db.customStatement(
        'INSERT INTO critere_inspection (id, created_at, updated_at, rubrique, code, libelle) VALUES (?, 0, 0, ?, ?, ?)',
        [c.id, c.rubrique.code, c.code, c.libelle]);
    final criteres = await db.customSelect('SELECT id FROM critere_inspection ORDER BY id').get();
    expect(criteres.map((l) => l.read<String>('id')), containsAll(['ancien', c.id]));
    final colonnes = await db.customSelect("SELECT name FROM pragma_table_info('inspection')").get();
    expect(colonnes.map((l) => l.read<String>('name')), contains('grille'));
    expect((await db.customSelect('PRAGMA user_version').getSingle()).data.values.first, 3);
    expect((await db.customSelect('PRAGMA foreign_keys').getSingle()).data.values.first, 1);
    // Les réponses référencent toujours la table des critères.
    final fk = await db.customSelect("SELECT \"table\" AS t FROM pragma_foreign_key_list('inspection_reponse')").get();
    expect(fk.map((l) => l.read<String>('t')), contains('critere_inspection'));
    await db.customSelect('SELECT COUNT(*) FROM critere_inspection WHERE rubrique = ?', variables: [Variable(c.rubrique.code)]).get();
    await db.close();
  });

  test('base du téléphone en schéma 2 mise à jour en schéma 3 : visite d\'aptitude', () async {
    final dossier = Directory.systemTemp.createTempSync('sssu_migration3');
    addTearDown(() => dossier.deleteSync(recursive: true));
    final fichier = File('${dossier.path}/base.db');
    BaseLocale ouvrir() => BaseLocale(NativeDatabase(fichier, setup: (d) => d.execute('PRAGMA foreign_keys = ON;')));

    // Base actuelle ramenée au schéma 2 : sans les colonnes de la visite d'aptitude.
    var db = ouvrir();
    await db.customSelect('SELECT 1').get();
    await db.customStatement('PRAGMA foreign_keys = OFF');
    for (final c in ['aptitude_restrictions', 'aptitude', 'type_visite']) {
      await db.customStatement('ALTER TABLE visite DROP COLUMN $c');
    }
    await db.customStatement("INSERT INTO visite (id, created_at, updated_at, eleve_id, agent_id, date_visite, statut) "
        "VALUES ('v1', 0, 0, 'e', 'a', '2026-10-01', 'valide')");
    await db.customStatement('PRAGMA user_version = 2');
    await db.close();

    // Réouverture : colonnes ajoutées, visite existante systématique.
    db = ouvrir();
    final v = await db.customSelect("SELECT type_visite, aptitude FROM visite WHERE id = 'v1'").getSingle();
    expect((v.read<String>('type_visite'), v.readNullable<String>('aptitude')), ('systematique', null));
    expect((await db.customSelect('PRAGMA user_version').getSingle()).data.values.first, 3);
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement("INSERT INTO visite (id, created_at, updated_at, eleve_id, agent_id, date_visite, statut, "
        "type_visite, aptitude, aptitude_restrictions) VALUES ('v2', 0, 0, 'e', 'a', '2026-11-01', 'valide', 'aptitude', "
        "'apte_partiel', 'Pas d''endurance')");
    await expectLater(
        db.customStatement("INSERT INTO visite (id, created_at, updated_at, eleve_id, agent_id, date_visite, statut, "
            "type_visite) VALUES ('v3', 0, 0, 'e', 'a', '2026-11-01', 'valide', 'autre')"),
        throwsA(anything),
        reason: 'type de visite contrôlé');
    await db.close();
  });
}
