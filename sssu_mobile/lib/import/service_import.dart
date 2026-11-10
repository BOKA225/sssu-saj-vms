/// Enregistrement d'une liste validée par l'utilisateur : dossiers des
/// nouveaux élèves, rattachement des élèves déjà connus, inscriptions dans la
/// classe, journal de l'importation et conservation chiffrée du fichier source.
library;

import 'package:sssu_core/sssu_core.dart';

import '../data/base_locale.dart' hide Utilisateur, Eleve;
import '../data/depot_local_drift.dart';
import '../fichiers/stockage_chiffre.dart';
import 'lecteurs.dart';

class ClasseCible {
  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  const ClasseCible(this.id, this.etablissementId, this.anneeScolaireId);
}

class ResultatImport {
  final String lotId;
  final int crees;
  final int rattaches;
  final int ignores;
  final int changementsDeClasse;
  const ResultatImport(this.lotId, this.crees, this.rattaches, this.ignores, this.changementsDeClasse);
}

class ServiceImport {
  final BaseLocale db;
  final DepotLocalDrift depot;
  final StockageChiffre fichiers;

  ServiceImport(this.db, this.depot, this.fichiers);

  Future<ResultatImport> enregistrer({
    required List<LigneImport> lignes,
    required ClasseCible classe,
    required TableauBrut tableau,
    required String nomFichier,
    required List<int> octetsSource,
    required String utilisateurId,
  }) async {
    final b = bilan(lignes);
    if (!b.validable) {
      throw const ErreurImport('Corrigez les lignes en erreur (ou choisissez « Ne pas importer ») avant de valider.');
    }
    final lotId = nouvelId();
    final chemin = await fichiers.ecrire('imports', lotId, octetsSource);
    var crees = 0, rattaches = 0, ignores = 0, changements = 0;
    try {
      await db.transaction(() async {
        await depot.creer(
          'import_lot',
          {
            'classe_id': classe.id,
            'utilisateur_id': utilisateurId,
            'fichier_nom': nomFichier,
            'format': tableau.format,
            'empreinte_sha256': sha256Hex(octetsSource),
            'statut': 'valide',
            'nb_lignes': lignes.length,
          },
          id: lotId,
          utilisateurId: utilisateurId,
          aTransmettre: false,
        );
        for (var i = 0; i < lignes.length; i++) {
          final l = lignes[i];
          String? eleveId;
          switch (l.action) {
            case ActionImport.ignorer:
              ignores++;
            case ActionImport.creer:
              final e = await depot.creer('eleve', donneesEleve(l),
                  utilisateurId: utilisateurId, etablissementId: classe.etablissementId);
              eleveId = e.id;
              crees++;
            case ActionImport.rattacher:
              eleveId = l.eleveExistantId!;
              await _completerDossier(eleveId, l, utilisateurId);
              rattaches++;
          }
          if (eleveId != null && await _inscrire(eleveId, classe, utilisateurId)) changements++;
          await depot.creer(
            'import_ligne',
            {
              'import_lot_id': lotId,
              'numero': l.numeroSource,
              'donnees_extraites': {for (final e in l.brut.entries) e.key.name: e.value},
              'anomalies': [for (final a in l.anomalies) a.message, ...l.notes],
              'decision': l.action == ActionImport.ignorer ? 'rejeter' : 'garder',
              'eleve_id': eleveId,
            },
            utilisateurId: utilisateurId,
            aTransmettre: false,
          );
        }
      });
    } catch (_) {
      await fichiers.supprimer(chemin);
      rethrow;
    }
    return ResultatImport(lotId, crees, rattaches, ignores, changements);
  }

  /// Complète un dossier existant avec les informations qu'il n'avait pas
  /// (jamais d'écrasement d'une information déjà présente).
  Future<void> _completerDossier(String eleveId, LigneImport l, String utilisateurId) async {
    final e = await depot.lire('eleve', eleveId);
    if (e == null) throw ErreurImport('Dossier introuvable pour ${l.nom} ${l.prenoms}.');
    final nouvelles = donneesEleve(l);
    final ajouts = <String, Object?>{
      for (final k in ['matricule', 'date_naissance', 'telephone_contact'])
        if (e.donnees[k] == null && nouvelles[k] != null) k: nouvelles[k],
    };
    if (ajouts.isNotEmpty) await depot.modifier('eleve', eleveId, ajouts, utilisateurId: utilisateurId);
  }

  /// Inscrit l'élève dans la classe pour l'année ; un élève déjà inscrit dans
  /// une autre classe la même année change de classe. Retourne vrai en cas de
  /// changement de classe.
  Future<bool> _inscrire(String eleveId, ClasseCible classe, String utilisateurId) async {
    final existantes =
        await depot.chercher('inscription', {'eleve_id': eleveId, 'annee_scolaire_id': classe.anneeScolaireId});
    if (existantes.isEmpty) {
      await depot.creer(
        'inscription',
        {'eleve_id': eleveId, 'classe_id': classe.id, 'annee_scolaire_id': classe.anneeScolaireId, 'statut': 'inscrit'},
        utilisateurId: utilisateurId,
        etablissementId: classe.etablissementId,
      );
      return false;
    }
    final ins = existantes.first;
    if (ins.donnees['classe_id'] == classe.id && ins.donnees['statut'] == 'inscrit') return false;
    await depot.modifier('inscription', ins.id, {'classe_id': classe.id, 'statut': 'inscrit'},
        utilisateurId: utilisateurId, etablissementId: classe.etablissementId);
    return ins.donnees['classe_id'] != classe.id;
  }
}
