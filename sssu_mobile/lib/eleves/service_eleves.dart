/// Ajout d'un élève dans une classe et modification de son identité sur le
/// téléphone. Les changements sont transmis au poste central à la prochaine
/// synchronisation, comme ceux d'une importation.
library;

import 'package:sssu_core/sssu_core.dart';

import '../data/base_locale.dart' hide Utilisateur, Eleve;
import '../data/depot_local_drift.dart';

class ErreurDossier implements Exception {
  final String message;
  const ErreurDossier(this.message);
  @override
  String toString() => message;
}

class ServiceEleves {
  final BaseLocale db;
  final DepotLocalDrift depot;
  ServiceEleves(this.db, this.depot);

  /// Nouvel élève inscrit dans la classe ; retourne son identifiant.
  /// [identite] : champs préparés par `identiteEleveSaisie`.
  Future<String> ajouter({
    required Map<String, Object?> identite,
    required String classeId,
    required String etablissementId,
    required String anneeScolaireId,
    required String utilisateurId,
  }) async {
    await _matriculeLibre(identite['matricule'] as String?);
    late String id;
    await db.transaction(() async {
      final e = await depot.creer('eleve', identite, utilisateurId: utilisateurId, etablissementId: etablissementId);
      await depot.creer(
        'inscription',
        {'eleve_id': e.id, 'classe_id': classeId, 'annee_scolaire_id': anneeScolaireId, 'statut': 'inscrit'},
        utilisateurId: utilisateurId,
        etablissementId: etablissementId,
      );
      id = e.id;
    });
    return id;
  }

  /// Enregistre les champs modifiés de l'identité (rien si rien n'a changé).
  Future<void> modifier(String eleveId, Map<String, Object?> identite, {required String utilisateurId}) async {
    final e = await depot.lire('eleve', eleveId);
    if (e == null) throw const ErreurDossier('Dossier introuvable sur ce téléphone.');
    await _matriculeLibre(identite['matricule'] as String?, sauf: eleveId);
    final changements = {
      for (final k in identite.keys)
        if (identite[k] != e.donnees[k]) k: identite[k],
    };
    if (changements.isEmpty) return;
    await depot.modifier('eleve', eleveId, changements, utilisateurId: utilisateurId);
  }

  Future<void> _matriculeLibre(String? matricule, {String? sauf}) async {
    if (matricule == null || matricule.isEmpty) return;
    final memes = [for (final e in await depot.chercher('eleve', {'matricule': matricule})) if (e.id != sauf) e];
    if (memes.isNotEmpty) {
      final d = memes.first.donnees;
      throw ErreurDossier('Le matricule $matricule est déjà celui de ${d['nom']} ${d['prenoms']}.');
    }
  }
}
