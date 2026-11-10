/// Mise à jour automatique du schéma PostgreSQL au démarrage du poste.
///
/// Les fichiers `NNN_nom.sql` du dossier SQL (installé avec l'application)
/// sont appliqués dans l'ordre, une seule fois chacun ; la table
/// `schema_migration` garde la liste des fichiers appliqués et leur
/// empreinte. Une mise à jour de l'application apporte ses nouveaux fichiers,
/// appliqués au premier lancement.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sssu_core/sssu_core.dart';

import 'depot_postgres.dart';

/// Fichiers d'outillage, jamais appliqués automatiquement.
const fichiersManuels = {'010_initialiser_journal_sync.sql'};

class MigrationAppliquee {
  final String nom;
  final bool appliqueeMaintenant;
  const MigrationAppliquee(this.nom, this.appliqueeMaintenant);
}

class MigrationsPoste {
  final DepotPostgres depot;
  final Directory dossier;
  MigrationsPoste(this.depot, this.dossier);

  /// Dossier SQL : celui de la configuration, sinon `sql` à côté de
  /// l'exécutable (installation), sinon `../sql/postgres` (développement).
  static Directory trouverDossier({String? configure}) {
    final candidats = [
      if (configure != null) configure,
      p.join(p.dirname(Platform.resolvedExecutable), 'sql'),
      p.join(Directory.current.path, '..', 'sql', 'postgres'),
      p.join(Directory.current.path, 'sql', 'postgres'),
    ];
    for (final c in candidats) {
      if (File(p.join(c, '001_schema.sql')).existsSync()) return Directory(c);
    }
    throw StateError('Fichiers SQL introuvables (cherchés dans : ${candidats.join(' ; ')}). '
        'Réinstallez l\'application ou indiquez "dossier_sql" dans sssu_config.json.');
  }

  List<File> fichiers() {
    final l = dossier
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'^\d{3}_.+\.sql$').hasMatch(p.basename(f.path)))
        .where((f) => !fichiersManuels.contains(p.basename(f.path)))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return l;
  }

  Future<bool> _tableExiste(String nom) async =>
      (await depot.requete('SELECT to_regclass(@t) IS NOT NULL AS ok', {'t': 'public.$nom'})).single['ok'] == true;

  /// Applique les fichiers manquants ; retourne la liste de tous les fichiers.
  Future<List<MigrationAppliquee>> appliquer() async {
    final resultat = <MigrationAppliquee>[];
    if (!await _tableExiste('schema_migration')) {
      final existante = await _tableExiste('eleve');
      await depot.executerScript('CREATE TABLE IF NOT EXISTS schema_migration ('
          'nom TEXT PRIMARY KEY, empreinte TEXT NOT NULL, appliquee_le TIMESTAMPTZ NOT NULL DEFAULT now())');
      if (existante) {
        // Base créée avant la phase 6 (chargement manuel de 001_schema.sql).
        final f = File(p.join(dossier.path, '001_schema.sql'));
        await depot.requete('INSERT INTO schema_migration (nom, empreinte) VALUES (@n, @e) ON CONFLICT DO NOTHING',
            {'n': '001_schema.sql', 'e': sha256Hex(await f.readAsBytes())});
      }
    }
    final deja = {
      for (final l in await depot.requete('SELECT nom FROM schema_migration')) l['nom'] as String,
    };
    for (final f in fichiers()) {
      final nom = p.basename(f.path);
      if (deja.contains(nom)) {
        resultat.add(MigrationAppliquee(nom, false));
        continue;
      }
      final contenu = await f.readAsString();
      try {
        await depot.executerScript(contenu);
      } catch (e) {
        throw StateError('Mise à jour de la base impossible ($nom) : $e');
      }
      await depot.requete('INSERT INTO schema_migration (nom, empreinte) VALUES (@n, @e) ON CONFLICT DO NOTHING',
          {'n': nom, 'e': sha256Hex(await f.readAsBytes())});
      resultat.add(MigrationAppliquee(nom, true));
    }
    return resultat;
  }
}
