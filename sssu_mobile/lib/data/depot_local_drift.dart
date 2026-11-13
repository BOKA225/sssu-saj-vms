/// Base locale du téléphone vue par la synchronisation (implémentation SQLite).
/// Même comportement que `DepotLocalMemoire` du paquet commun, testé de la
/// même façon.
library;

import 'package:sssu_core/sssu_core.dart';

import '../fichiers/stockage_chiffre.dart';
import 'base_locale.dart' hide Utilisateur, Eleve;
import 'conversion_sql.dart';

/// Colonnes propres au téléphone, jamais écrasées par une réception.
const Map<String, Set<String>> colonnesLocales = {
  'utilisateur': {'hash_pin', 'echecs_connexion', 'bloque_jusqua'},
};

class DepotLocalDrift implements DepotLocalSync {
  final BaseLocale db;
  final Horloge horloge;
  String? appareilId;

  /// Fichiers chiffrés des photographies (fourni par `ServicesMobile`).
  StockageChiffre? fichiers;

  DepotLocalDrift(this.db, {this.horloge = const HorlogeSysteme(), this.appareilId, this.fichiers});

  TableSpec _spec(String table) {
    final s = registreParNom[table];
    if (s == null || !s.surMobile) throw ArgumentError('Table absente du téléphone : $table');
    return s;
  }

  Future<List<Map<String, Object?>>> _select(String sql, [List<Object?> args = const []]) async {
    final lignes = await db.customSelect(sql, variables: [for (final a in args) variable(a)]).get();
    return [for (final l in lignes) l.data];
  }

  // ------------------------------------------------------------------ lecture

  Future<Enregistrement?> lire(String table, String id) async {
    final s = _spec(table);
    final r = await _select('SELECT * FROM ${s.nom} WHERE id = ?', [id]);
    return r.isEmpty ? null : lireLigne(s, r.first);
  }

  /// Enregistrements non supprimés dont les colonnes valent les valeurs données.
  Future<List<Enregistrement>> chercher(String table, Map<String, Object?> egalites) async {
    final s = _spec(table);
    final conditions = <String>['deleted_at IS NULL'];
    final args = <Object?>[];
    egalites.forEach((col, v) {
      final c = s.colonne(col);
      if (c == null) throw ArgumentError('Colonne inconnue : $table.$col');
      if (v == null) {
        conditions.add('$col IS NULL');
      } else {
        conditions.add('$col = ?');
        args.add(versSqlite(c.type, v));
      }
    });
    final r = await _select('SELECT * FROM ${s.nom} WHERE ${conditions.join(' AND ')} ORDER BY created_at', args);
    return [for (final l in r) lireLigne(s, l)];
  }

  Future<EtatSync?> etat(String table, String id) async {
    final r = await _select('SELECT sync_status FROM ${_spec(table).nom} WHERE id = ?', [id]);
    return r.isEmpty ? null : EtatSync.depuisCode(r.first['sync_status']! as String);
  }

  // ------------------------------------------------------- saisie sur le téléphone

  /// Crée un enregistrement saisi sur le téléphone. [aTransmettre] = faux
  /// pour une ébauche (état « local », non envoyée).
  Future<Enregistrement> creer(
    String table,
    Map<String, Object?> donnees, {
    required String utilisateurId,
    String? etablissementId,
    bool aTransmettre = true,
    String? id,
  }) async {
    final m = horloge.maintenant();
    final e = Enregistrement(
      table: table,
      id: id ?? nouvelId(),
      version: 1,
      versionBase: 0,
      createdAt: m,
      updatedAt: m,
      createdBy: utilisateurId,
      updatedBy: utilisateurId,
      deviceId: appareilId,
      etablissementId: etablissementId,
      donnees: donnees,
    );
    final anomalies = e.anomaliesColonnes();
    if (anomalies.isNotEmpty) throw ArgumentError(anomalies.join(', '));
    await _ecrire(e, aTransmettre ? EtatSync.enAttente : EtatSync.local, remplacerTout: true);
    return e;
  }

  /// Modifie un enregistrement : version = base + 1, état « en attente »
  /// (ou « local » si [aTransmettre] est faux).
  Future<Enregistrement> modifier(
    String table,
    String id,
    Map<String, Object?> changements, {
    required String utilisateurId,
    bool aTransmettre = true,
    String? etablissementId,
  }) async {
    final actuel = await lire(table, id);
    if (actuel == null) throw StateError('$table/$id introuvable');
    final e = actuel.copier(
      version: actuel.versionBase + 1,
      updatedAt: horloge.maintenant(),
      updatedBy: utilisateurId,
      deviceId: appareilId,
      etablissementId: etablissementId,
      donnees: {...actuel.donnees, ...changements},
    );
    await _ecrire(e, aTransmettre ? EtatSync.enAttente : EtatSync.local, remplacerTout: true);
    return e;
  }

  /// Supprime un enregistrement : définitivement s'il n'a jamais été transmis
  /// au poste central, sinon par suppression logique (transmise à la
  /// prochaine synchronisation).
  Future<void> supprimer(String table, String id, {required String utilisateurId}) async {
    final actuel = await lire(table, id);
    if (actuel == null) return;
    if (actuel.versionBase == 0) {
      await db.customStatement('DELETE FROM ${_spec(table).nom} WHERE id = ?', [id]);
      return;
    }
    final e = actuel.copier(
      version: actuel.versionBase + 1,
      updatedAt: horloge.maintenant(),
      updatedBy: utilisateurId,
      deviceId: appareilId,
      deletedAt: horloge.maintenant(),
    );
    await _ecrire(e, EtatSync.enAttente, remplacerTout: true);
  }

  /// Passe à « en attente » des enregistrements saisis en ébauche (état
  /// « local »), pour qu'ils soient transmis à la prochaine synchronisation.
  Future<void> rendreTransmissible(String table, String id) =>
      db.customStatement("UPDATE ${_spec(table).nom} SET sync_status = 'en_attente' WHERE id = ? AND sync_status = 'local'", [id]);

  Future<void> _ecrire(Enregistrement e, EtatSync etat, {required bool remplacerTout}) async {
    final s = _spec(e.table);
    final valeurs = <String, Object?>{
      'id': e.id,
      'version': e.version,
      'base_version': e.versionBase,
      'created_at': formaterHorodatage(e.createdAt),
      'updated_at': formaterHorodatage(e.updatedAt),
      'created_by': e.createdBy,
      'updated_by': e.updatedBy,
      'device_id': e.deviceId,
      'deleted_at': e.deletedAt == null ? null : formaterHorodatage(e.deletedAt!),
      'sync_status': etat.code,
      'portee_etablissement_id': e.etablissementId,
    };
    for (final c in s.colonnes) {
      final v = e.donnees[c.nom];
      if (v == null && c.aValeurParDefaut && !e.donnees.containsKey(c.nom)) continue;
      if (v == null && c.aValeurParDefaut && c.obligatoire) continue;
      valeurs[c.nom] = versSqlite(c.type, v);
    }
    final preserver = remplacerTout ? const <String>{} : (colonnesLocales[e.table] ?? const <String>{});
    final colonnes = valeurs.keys.toList();
    final miseAJour = colonnes.where((c) => c != 'id' && !preserver.contains(c)).map((c) => '$c = excluded.$c');
    await db.customStatement(
      'INSERT INTO ${s.nom} (${colonnes.join(', ')}) VALUES (${List.filled(colonnes.length, '?').join(', ')}) '
      'ON CONFLICT(id) DO UPDATE SET ${miseAJour.join(', ')}',
      [for (final c in colonnes) valeurs[c]],
    );
  }

  // ---------------------------------------------------------- synchronisation

  @override
  Future<List<Enregistrement>> enAttente({required int limite}) async {
    final specs = registre.where((t) => t.envoiParTelephone && t.surMobile).toList()
      ..sort((a, b) => a.ordreEnvoi.compareTo(b.ordreEnvoi));
    final resultat = <Enregistrement>[];
    for (final s in specs) {
      final reste = limite - resultat.length;
      if (reste <= 0) break;
      final lignes = await _select(
          'SELECT * FROM ${s.nom} WHERE sync_status = ? ORDER BY updated_at LIMIT ?', [EtatSync.enAttente.code, reste]);
      resultat.addAll(lignes.map((l) => lireLigne(s, l)));
    }
    return resultat;
  }

  @override
  Future<void> marquerSynchronise(Enregistrement envoye, int versionServeur) async {
    final s = _spec(envoye.table);
    // Photographie supprimée, suppression enregistrée par le poste : le fichier local est effacé.
    if (envoye.supprime && tablesAvecFichier.contains(s.nom) && fichiers != null) {
      final chemin = envoye.donnees['chemin_chiffre'] as String?;
      if (chemin != null) await fichiers!.supprimer(chemin);
    }
    final ts = formaterHorodatage(envoye.updatedAt);
    await db.customStatement(
      'UPDATE ${s.nom} SET base_version = ?, '
      'version = CASE WHEN updated_at = ? THEN ? ELSE ? END, '
      "sync_status = CASE WHEN updated_at = ? THEN 'synchronise' ELSE 'en_attente' END "
      'WHERE id = ?',
      [versionServeur, ts, versionServeur, versionServeur + 1, ts, envoye.id],
    );
    await _effacerMotif(envoye.table, envoye.id);
  }

  @override
  Future<void> marquerConflit(Enregistrement envoye, String motif) async {
    final s = _spec(envoye.table);
    await db.customStatement("UPDATE ${s.nom} SET sync_status = 'conflit' WHERE id = ?", [envoye.id]);
    await ecrireEtat('motif_conflit:${s.nom}:${envoye.id}', motif);
  }

  Future<String?> motifConflit(String table, String id) => lireEtat('motif_conflit:$table:$id');

  Future<void> _effacerMotif(String table, String id) =>
      db.customStatement('DELETE FROM sync_etat WHERE cle = ?', ['motif_conflit:$table:$id']);

  @override
  Future<void> appliquerDistant(Enregistrement e, {required bool resolutionConflit}) async {
    final s = registreParNom[e.table];
    if (s == null || !s.surMobile) return;
    final r = await _select('SELECT sync_status, base_version FROM ${s.nom} WHERE id = ?', [e.id]);
    if (r.isNotEmpty) {
      final etat = EtatSync.depuisCode(r.first['sync_status']! as String);
      final base = (r.first['base_version']! as num).toInt();
      final protege = etat == EtatSync.enAttente ||
          etat == EtatSync.local ||
          (etat == EtatSync.conflit && !resolutionConflit);
      if (protege) return;
      if (etat == EtatSync.synchronise && e.version < base) return;
    }
    await db.transaction(() async {
      await _ecrire(e.copier(versionBase: e.version), EtatSync.synchronise, remplacerTout: false);
      if (resolutionConflit) await _effacerMotif(s.nom, e.id);
    });
  }

  // ------------------------------------------------------------- fichiers

  @override
  Future<List<FichierLocal>> fichiersATransferer() async {
    final resultat = <FichierLocal>[];
    for (final t in tablesAvecFichier) {
      final s = registreParNom[t];
      if (s == null || !s.surMobile) continue;
      final lignes = await _select(
          "SELECT id, empreinte_sha256 FROM ${s.nom} WHERE sync_status = 'synchronise' AND deleted_at IS NULL "
          "AND statut_transfert <> 'confirme' ORDER BY created_at");
      resultat.addAll([for (final l in lignes) FichierLocal(t, l['id']! as String, l['empreinte_sha256']! as String)]);
    }
    return resultat;
  }

  Future<String?> _chemin(FichierLocal f) async {
    final r = await _select('SELECT chemin_chiffre FROM ${_spec(f.table).nom} WHERE id = ?', [f.id]);
    return r.isEmpty ? null : r.first['chemin_chiffre'] as String?;
  }

  @override
  Future<List<int>?> lireFichier(FichierLocal f) async {
    final stockage = fichiers;
    final chemin = await _chemin(f);
    if (stockage == null || chemin == null || !await stockage.existe(chemin)) return null;
    try {
      return await stockage.lire(chemin);
    } catch (_) {
      return null; // fichier illisible (clé ou contenu altéré) : signalé comme manquant
    }
  }

  /// Le poste central a vérifié et conservé le fichier : statut « confirme »
  /// (sans nouvelle version : le poste a fait de même) et copie locale effacée.
  @override
  Future<void> marquerFichierTransfere(FichierLocal f) async {
    final chemin = await _chemin(f);
    await db.customStatement("UPDATE ${_spec(f.table).nom} SET statut_transfert = 'confirme' WHERE id = ?", [f.id]);
    if (chemin != null) await fichiers?.supprimer(chemin);
  }

  /// Abandonne la version locale d'un enregistrement jamais accepté par le
  /// poste central (création refusée ou en conflit) : il est effacé du
  /// téléphone avec les éléments qui en dépendent (également jamais
  /// transmis) et leurs fichiers. Retourne le nombre d'enregistrements effacés.
  Future<int> abandonner(String table, String id) async {
    final aEffacer = <(String, String)>[];
    final dependances = await _dependances();
    Future<void> collecter(String t, String i) async {
      if (aEffacer.contains((t, i))) return;
      final r = await _select('SELECT base_version FROM $t WHERE id = ?', [i]);
      if (r.isEmpty) return;
      if ((r.first['base_version']! as num).toInt() != 0) {
        throw StateError('Un élément concerné existe déjà sur le poste central : '
            'seule la décision du Médecin-Chef peut le modifier.');
      }
      aEffacer.add((t, i));
      for (final (enfant, colonne) in dependances[t] ?? const <(String, String)>[]) {
        for (final l in await _select('SELECT id FROM $enfant WHERE $colonne = ?', [i])) {
          await collecter(enfant, l['id']! as String);
        }
      }
    }

    await collecter(_spec(table).nom, id);
    final chemins = <String>[];
    await enTransaction(() async {
      for (final (t, i) in aEffacer) {
        if (tablesAvecFichier.contains(t)) {
          final c = await _chemin(FichierLocal(t, i, ''));
          if (c != null) chemins.add(c);
        }
        await db.customStatement('DELETE FROM $t WHERE id = ?', [i]);
        await _effacerMotif(t, i);
      }
    });
    for (final c in chemins) {
      await fichiers?.supprimer(c);
    }
    return aEffacer.length;
  }

  /// Pour chaque table : (table enfant, colonne) qui la référencent (clés étrangères SQLite).
  Future<Map<String, List<(String, String)>>> _dependances() async {
    final resultat = <String, List<(String, String)>>{};
    for (final s in registre.where((t) => t.surMobile)) {
      for (final fk in await _select('SELECT "table" AS parent, "from" AS colonne FROM pragma_foreign_key_list(?)', [s.nom])) {
        (resultat[fk['parent']! as String] ??= []).add((s.nom, fk['colonne']! as String));
      }
    }
    return resultat;
  }

  /// Enregistrements en conflit ou refusés, avec leur motif (écran « Éléments à vérifier »).
  Future<List<({Enregistrement enregistrement, String? motif})>> enConflit() async {
    final resultat = <({Enregistrement enregistrement, String? motif})>[];
    for (final s in registre.where((t) => t.envoiParTelephone && t.surMobile)) {
      final lignes = await _select("SELECT * FROM ${s.nom} WHERE sync_status = 'conflit' ORDER BY updated_at");
      for (final l in lignes) {
        final e = lireLigne(s, l);
        resultat.add((enregistrement: e, motif: await motifConflit(s.nom, e.id)));
      }
    }
    return resultat;
  }

  @override
  Future<void> enTransaction(Future<void> Function() action) => db.transaction(() async {
        await db.customStatement('PRAGMA defer_foreign_keys = ON');
        await action();
      });

  @override
  Future<String?> generationServeur() => lireEtat('generation');

  @override
  Future<void> definirGenerationServeur(String generation) => ecrireEtat('generation', generation);

  @override
  Future<Set<String>> preparerReprise() async {
    final cles = <String>{};
    await db.transaction(() async {
      for (final s in registre.where((t) => t.envoiParTelephone && t.surMobile)) {
        for (final l in await _select("SELECT id FROM ${s.nom} WHERE sync_status = 'synchronise'")) {
          cles.add('${s.nom}/${l['id']}');
        }
        await db.customStatement("UPDATE ${s.nom} SET sync_status = 'en_attente' WHERE sync_status = 'synchronise'");
      }
    });
    return cles;
  }

  @override
  Future<int> curseur() async => int.tryParse(await lireEtat('curseur') ?? '') ?? 0;

  @override
  Future<void> definirCurseur(int curseur) => ecrireEtat('curseur', '$curseur');

  Future<String?> lireEtat(String cle) async {
    final r = await _select('SELECT valeur FROM sync_etat WHERE cle = ?', [cle]);
    return r.isEmpty ? null : r.first['valeur'] as String?;
  }

  Future<void> ecrireEtat(String cle, String? valeur) => db.customStatement(
      'INSERT INTO sync_etat (cle, valeur) VALUES (?, ?) ON CONFLICT(cle) DO UPDATE SET valeur = excluded.valeur',
      [cle, valeur]);

  /// Nombre d'enregistrements par état, pour l'indicateur de synchronisation.
  Future<Map<EtatSync, int>> compterEtats() async {
    final totaux = {for (final e in EtatSync.values) e: 0};
    for (final s in registre.where((t) => t.envoiParTelephone && t.surMobile)) {
      final r = await _select('SELECT sync_status, COUNT(*) AS n FROM ${s.nom} GROUP BY sync_status');
      for (final l in r) {
        final e = EtatSync.depuisCode(l['sync_status']! as String);
        totaux[e] = totaux[e]! + (l['n']! as num).toInt();
      }
    }
    return totaux;
  }
}
