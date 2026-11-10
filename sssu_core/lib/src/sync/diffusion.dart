/// Diffusion des données vers les téléphones lorsque le rattachement d'un
/// élève ou l'affectation d'un téléphone change.
library;

import '../schema/registre.dart';
import 'depot_serveur.dart';

/// Rattache l'élève et son dossier médical (visites, antécédents) à
/// [etablissementId] : les téléphones de cet établissement les reçoivent,
/// ce qui conserve l'historique quand l'élève change d'établissement
/// (« un élève = un dossier permanent »).
///
/// À appeler AVANT d'écrire l'inscription, pour que le téléphone reçoive le
/// dossier de l'élève avant son inscription.
Future<void> reaffecterEleve(TransactionServeur tx, String eleveId, String etablissementId) async {
  final eleve = await tx.lire('eleve', eleveId);
  if (eleve == null || eleve.etablissementId == etablissementId) return;
  await tx.ecrire(eleve.copier(etablissementId: etablissementId));
  final visites = await tx.chercher('visite', {'eleve_id': eleveId});
  for (final v in visites) {
    await tx.ecrire(v.copier(etablissementId: etablissementId));
  }
  for (final a in await tx.chercher('antecedent', {'eleve_id': eleveId})) {
    await tx.ecrire(a.copier(etablissementId: etablissementId));
  }
}

/// Rediffuse toutes les données d'un établissement (établissement, classes,
/// élèves, inscriptions, visites, antécédents), dans l'ordre des dépendances,
/// à destination d'un téléphone qui vient d'y être affecté. Les téléphones
/// qui les ont déjà les appliquent sans effet.
Future<void> rediffuserEtablissement(TransactionServeur tx, String etablissementId) async {
  for (final spec in registre.where((t) => t.receptionParTelephone && t.parEtablissement)) {
    for (final e in await tx.parPortee(spec.nom, etablissementId)) {
      await tx.ecrire(e);
    }
  }
}
