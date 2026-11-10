/// Calcul de l'âge. L'âge n'est jamais stocké : il est recalculé à partir de la
/// date de naissance et de la date de la visite.
library;

class Age {
  final int annees;
  final int mois;

  const Age(this.annees, this.mois);

  /// Âge en mois révolus (utilisé par les tables OMS).
  int get enMois => annees * 12 + mois;

  @override
  String toString() => mois == 0 ? '$annees an${annees > 1 ? 's' : ''}' : '$annees an${annees > 1 ? 's' : ''} $mois mois';

  @override
  bool operator ==(Object other) => other is Age && other.annees == annees && other.mois == mois;

  @override
  int get hashCode => Object.hash(annees, mois);
}

/// Âge en années et mois révolus à la date [aLaDate].
///
/// Lève une [ArgumentError] si la date de naissance est postérieure à [aLaDate].
Age calculerAge(DateTime dateNaissance, DateTime aLaDate) {
  final n = DateTime.utc(dateNaissance.year, dateNaissance.month, dateNaissance.day);
  final d = DateTime.utc(aLaDate.year, aLaDate.month, aLaDate.day);
  if (n.isAfter(d)) {
    throw ArgumentError('La date de naissance est postérieure à la date de référence.');
  }
  var mois = (d.year - n.year) * 12 + (d.month - n.month);
  if (d.day < n.day) mois -= 1;
  return Age(mois ~/ 12, mois % 12);
}
