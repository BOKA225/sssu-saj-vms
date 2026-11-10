import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Nouvel identifiant unique (UUID version 7, ordonné dans le temps),
/// généré sur l'appareil et jamais modifié ensuite.
String nouvelId() => _uuid.v7();

/// Source de l'heure, remplaçable dans les tests.
abstract class Horloge {
  DateTime maintenant();
}

class HorlogeSysteme implements Horloge {
  const HorlogeSysteme();

  @override
  DateTime maintenant() => DateTime.now().toUtc();
}

/// Horloge réglable pour les tests.
class HorlogeFixe implements Horloge {
  DateTime _instant;

  HorlogeFixe(DateTime instant) : _instant = instant.toUtc();

  @override
  DateTime maintenant() => _instant;

  void avancer(Duration d) => _instant = _instant.add(d);

  void regler(DateTime instant) => _instant = instant.toUtc();
}

/// Date sans heure au format `AAAA-MM-JJ`.
String formaterDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Lit une date `AAAA-MM-JJ` (l'éventuelle partie horaire est ignorée).
DateTime lireDate(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s.trim());
  if (m == null) throw FormatException('Date invalide (AAAA-MM-JJ attendu)', s);
  final d = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  if (d.month != int.parse(m[2]!) || d.day != int.parse(m[3]!)) {
    throw FormatException('Date inexistante', s);
  }
  return d;
}

/// Horodatage canonique : ISO 8601 en UTC.
String formaterHorodatage(DateTime d) => d.toUtc().toIso8601String();

DateTime lireHorodatage(String s) => DateTime.parse(s).toUtc();
