/// Enregistrement du suivi vaccinal d'un enfant sur le téléphone : une fiche
/// par enfant, à l'identifiant calculé (`idSuiviVaccinal`), transmise au
/// poste central à la prochaine synchronisation.
library;

import 'package:sssu_core/sssu_core.dart';

import '../data/depot_local_drift.dart';

class ServiceVaccination {
  final DepotLocalDrift depot;
  ServiceVaccination(this.depot);

  /// Enregistre le suivi (rien s'il n'a pas changé, ni s'il est vide et
  /// n'existe pas encore). Retourne `true` si quelque chose a été enregistré.
  Future<bool> enregistrer(SuiviVaccinal s, {required String utilisateurId, String? etablissementId}) async {
    final donnees = s.versDonnees();
    final existant = await depot.lire('suivi_vaccinal', s.id);
    if (existant == null) {
      if (s.vide) return false;
      await depot.creer('suivi_vaccinal', donnees,
          utilisateurId: utilisateurId, etablissementId: etablissementId, id: s.id);
      return true;
    }
    final changements = {
      for (final k in donnees.keys)
        if (donnees[k] != existant.donnees[k]) k: donnees[k],
    };
    if (changements.isEmpty) return false;
    await depot.modifier('suivi_vaccinal', s.id, changements,
        utilisateurId: utilisateurId, etablissementId: etablissementId);
    return true;
  }
}
