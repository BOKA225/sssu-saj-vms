/// Contrôles de vraisemblance des constantes saisies lors de la visite.
/// Ils ne bloquent pas la saisie : ils signalent une valeur à vérifier
/// (erreur de frappe, unité inversée…).
library;

class Alerte {
  final String champ;
  final String message;
  const Alerte(this.champ, this.message);

  @override
  String toString() => '$champ : $message';
}

class _Plage {
  final num min;
  final num max;
  final String unite;
  const _Plage(this.min, this.max, this.unite);
}

/// Plages plausibles chez des élèves et étudiants (3 à 30 ans environ).
const _plages = {
  'poids_kg': _Plage(8, 200, 'kg'),
  'taille_cm': _Plage(70, 220, 'cm'),
  'ta_sys': _Plage(60, 220, 'mmHg'),
  'ta_dia': _Plage(30, 140, 'mmHg'),
  'temperature_c': _Plage(34, 42.5, '°C'),
  'fc': _Plage(40, 200, 'battements/min'),
  'fr': _Plage(8, 60, 'cycles/min'),
};

List<Alerte> verifierConstantes({
  double? poidsKg,
  double? tailleCm,
  int? taSys,
  int? taDia,
  double? temperatureC,
  int? fc,
  int? fr,
}) {
  final alertes = <Alerte>[];
  void controler(String champ, num? valeur) {
    if (valeur == null) return;
    final p = _plages[champ]!;
    if (valeur < p.min || valeur > p.max) {
      alertes.add(Alerte(champ, 'valeur inhabituelle ($valeur ${p.unite}), attendu entre ${p.min} et ${p.max}'));
    }
  }

  controler('poids_kg', poidsKg);
  controler('taille_cm', tailleCm);
  controler('ta_sys', taSys);
  controler('ta_dia', taDia);
  controler('temperature_c', temperatureC);
  controler('fc', fc);
  controler('fr', fr);
  if (taSys != null && taDia != null && taDia >= taSys) {
    alertes.add(const Alerte('ta_dia', 'la diastolique doit être inférieure à la systolique'));
  }
  if ((taSys == null) != (taDia == null)) {
    alertes.add(const Alerte('ta_sys', 'saisir la systolique et la diastolique'));
  }
  return alertes;
}
