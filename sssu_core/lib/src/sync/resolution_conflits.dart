/// Règles de décision appliquées par le poste central à chaque enregistrement
/// reçu d'un téléphone (tableau « Règles de résolution des conflits » du
/// document de conception). Fonction pure, sans accès à la base.
library;

import 'enregistrement.dart';

enum TypeDecision { accepter, dejaRecu, conflit, refuser }

/// Types de conflit (valeurs de `conflit.type`).
abstract final class TypesConflit {
  static const modificationConcurrente = 'modification_concurrente';
  static const suppressionModification = 'suppression_modification';
  static const doublonEleve = 'doublon_eleve';
  static const doublonVisite = 'doublon_visite';
  static const unicite = 'unicite';
}

class Decision {
  final TypeDecision type;
  final String? typeConflit;
  final String? motif;

  /// Reprise après restauration : le poste garde le numéro de version du
  /// téléphone (au lieu de l'incrémenter), pour que les copies plus anciennes
  /// détenues par d'autres téléphones soient reconnues comme telles.
  final bool conserverVersion;

  const Decision._(this.type, {this.typeConflit, this.motif, this.conserverVersion = false});

  const Decision.accepter() : this._(TypeDecision.accepter);
  const Decision.accepterReprise() : this._(TypeDecision.accepter, conserverVersion: true);
  const Decision.dejaRecu() : this._(TypeDecision.dejaRecu);
  const Decision.conflit(String type, String motif) : this._(TypeDecision.conflit, typeConflit: type, motif: motif);
  const Decision.refuser(String motif) : this._(TypeDecision.refuser, motif: motif);

  @override
  String toString() => '$type${typeConflit == null ? '' : ' ($typeConflit)'}${motif == null ? '' : ' : $motif'}';
}

bool _visiteValidee(Enregistrement? e) => e != null && e.table == 'visite' && e.donnees['statut'] == 'valide';

/// Décide du sort de [entrant] (envoyé par un téléphone) face à [existant]
/// (version actuelle du poste central, ou `null` si inconnue).
///
/// [reprise] : renvoi des données d'un téléphone après une restauration du
/// poste central. La version la plus récente l'emporte : celle du téléphone
/// si elle dépasse celle de la sauvegarde restaurée, sinon celle du poste
/// (le téléphone la recevra ensuite).
Decision decider(Enregistrement entrant, Enregistrement? existant, {bool reprise = false}) {
  // 1. Enregistrement inconnu du poste central : création (ou re-création
  //    après une restauration de sauvegarde) — accepté, rien ne se perd.
  if (existant == null) return reprise ? const Decision.accepterReprise() : const Decision.accepter();

  // 2. Renvoi d'un envoi déjà enregistré (accusé de réception perdu).
  if (entrant.memeContenu(existant)) return const Decision.dejaRecu();

  // Reprise : la version du téléphone ne part pas de celle du poste.
  if (reprise && entrant.versionBase != existant.version) {
    return entrant.version > existant.version ? const Decision.accepterReprise() : const Decision.dejaRecu();
  }

  // 3. Une visite validée ne se modifie plus depuis un téléphone.
  if (_visiteValidee(existant)) {
    return const Decision.refuser('visite_validee');
  }

  // 4. Modification normale : elle part de la version actuelle du poste central.
  if (entrant.versionBase == existant.version) return const Decision.accepter();

  // 5. Le poste central a évolué depuis : modification concurrente.
  if (existant.supprime != entrant.supprime) {
    return const Decision.conflit(TypesConflit.suppressionModification,
        'Enregistrement supprimé d\'un côté et modifié de l\'autre.');
  }
  if (entrant.versionBase > existant.version) {
    return const Decision.conflit(TypesConflit.modificationConcurrente,
        'Le téléphone annonce une version inconnue du poste central (restauration de sauvegarde ?).');
  }
  return const Decision.conflit(TypesConflit.modificationConcurrente,
      'Modifié sur un autre appareil depuis la dernière synchronisation.');
}
