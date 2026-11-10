/// Calcul de la conformité d'une inspection sanitaire.
///
/// Taux = (conformes + 0,5 × partiellement conformes) / (critères évalués) × 100,
/// les critères « non applicable » étant exclus du dénominateur.
/// Les seuils du niveau global sont des paramètres (table `parametre`),
/// 80 % et 50 % par défaut.
library;

import '../modeles/enums.dart';

class ResultatConformite {
  final int conformes;
  final int partiels;
  final int nonConformes;
  final int nonApplicables;

  /// Pourcentage arrondi à une décimale, `null` si aucun critère n'est évalué.
  final double? taux;
  final NiveauConformite? niveau;

  const ResultatConformite({
    required this.conformes,
    required this.partiels,
    required this.nonConformes,
    required this.nonApplicables,
    required this.taux,
    required this.niveau,
  });

  int get evalues => conformes + partiels + nonConformes;
}

ResultatConformite calculerConformite(
  Iterable<ResultatInspection> reponses, {
  double seuilSatisfaisant = 80,
  double seuilMoyen = 50,
}) {
  if (seuilMoyen > seuilSatisfaisant) {
    throw ArgumentError('Le seuil « moyen » doit être inférieur au seuil « satisfaisant ».');
  }
  var c = 0, p = 0, n = 0, na = 0;
  for (final r in reponses) {
    switch (r) {
      case ResultatInspection.conforme:
        c++;
      case ResultatInspection.partiel:
        p++;
      case ResultatInspection.nonConforme:
        n++;
      case ResultatInspection.nonApplicable:
        na++;
    }
  }
  final evalues = c + p + n;
  if (evalues == 0) {
    return ResultatConformite(
        conformes: c, partiels: p, nonConformes: n, nonApplicables: na, taux: null, niveau: null);
  }
  final taux = ((c + 0.5 * p) / evalues * 1000).roundToDouble() / 10;
  final NiveauConformite niveau;
  if (taux >= seuilSatisfaisant) {
    niveau = NiveauConformite.satisfaisant;
  } else if (taux >= seuilMoyen) {
    niveau = NiveauConformite.moyen;
  } else {
    niveau = NiveauConformite.insuffisant;
  }
  return ResultatConformite(
      conformes: c, partiels: p, nonConformes: n, nonApplicables: na, taux: taux, niveau: niveau);
}
