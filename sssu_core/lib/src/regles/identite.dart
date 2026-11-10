/// Normalisation des identités et détection des doublons d'élèves
/// (importation des listes et synchronisation).
library;

import '../commun/commun.dart';
import '../modeles/enums.dart';

const _accents = {
  'À': 'A', 'Â': 'A', 'Ä': 'A', 'Á': 'A', 'Ã': 'A',
  'Ç': 'C',
  'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
  'Î': 'I', 'Ï': 'I', 'Í': 'I', 'Ì': 'I',
  'Ô': 'O', 'Ö': 'O', 'Ó': 'O', 'Ò': 'O', 'Õ': 'O',
  'Ù': 'U', 'Û': 'U', 'Ü': 'U', 'Ú': 'U',
  'Ÿ': 'Y', 'Ñ': 'N', 'Œ': 'OE', 'Æ': 'AE',
};

/// Majuscules, sans accents, apostrophes et tirets remplacés par des espaces,
/// espaces multiples réduits. « N'Guessan  Aya-Marie » → « N GUESSAN AYA MARIE ».
String normaliserTexte(String s) {
  final b = StringBuffer();
  for (final ch in s.toUpperCase().split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b
      .toString()
      .replaceAll(RegExp(r"[’'`´\-_.]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Matricule normalisé : majuscules, sans espaces ni séparateurs.
String? normaliserMatricule(String? s) {
  if (s == null) return null;
  final m = s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return m.isEmpty ? null : m;
}

/// Reconnaît les écritures courantes du sexe dans les listes scolaires.
Sexe? lireSexe(String? s) {
  if (s == null) return null;
  final n = normaliserTexte(s);
  const masculin = {'M', 'MASCULIN', 'G', 'GARCON', 'H', 'HOMME', 'MASC'};
  const feminin = {'F', 'FEMININ', 'FILLE', 'FEMME', 'FEM'};
  if (masculin.contains(n)) return Sexe.masculin;
  if (feminin.contains(n)) return Sexe.feminin;
  return null;
}

/// Lit une date de naissance écrite `JJ/MM/AAAA`, `JJ-MM-AAAA`, `JJ.MM.AAAA`
/// ou `AAAA-MM-JJ`. Retourne `null` si la date est illisible ou inexistante.
DateTime? lireDateNaissance(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final t = s.trim();
  try {
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(t);
    if (iso != null) {
      return lireDate('${iso[1]}-${iso[2]!.padLeft(2, '0')}-${iso[3]!.padLeft(2, '0')}');
    }
    final fr = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$').firstMatch(t);
    if (fr != null) {
      return lireDate('${fr[3]}-${fr[2]!.padLeft(2, '0')}-${fr[1]!.padLeft(2, '0')}');
    }
  } on FormatException {
    return null;
  }
  return null;
}

/// Identité minimale d'un élève pour la comparaison.
class IdentiteEleve {
  final String? id;
  final String? matricule;
  final String nom;
  final String prenoms;
  final DateTime? dateNaissance;

  const IdentiteEleve({this.id, this.matricule, required this.nom, required this.prenoms, this.dateNaissance});

  String get cleNomDate =>
      '${normaliserTexte(nom)}|${normaliserTexte(prenoms)}|${dateNaissance == null ? '' : formaterDate(dateNaissance!)}';
}

enum MotifDoublon { memeMatricule, memesNomPrenomsDateNaissance }

class Doublon {
  final IdentiteEleve candidat;
  final IdentiteEleve existant;
  final MotifDoublon motif;
  const Doublon(this.candidat, this.existant, this.motif);
}

/// Cherche, pour chaque candidat, un élève déjà connu (dans [existants] ou
/// parmi les candidats précédents) : d'abord par matricule, puis par
/// nom + prénoms + date de naissance.
List<Doublon> detecterDoublons(List<IdentiteEleve> candidats, List<IdentiteEleve> existants) {
  final parMatricule = <String, IdentiteEleve>{};
  final parNomDate = <String, IdentiteEleve>{};
  void indexer(IdentiteEleve e) {
    final m = normaliserMatricule(e.matricule);
    if (m != null) parMatricule.putIfAbsent(m, () => e);
    if (e.dateNaissance != null) parNomDate.putIfAbsent(e.cleNomDate, () => e);
  }

  existants.forEach(indexer);
  final resultat = <Doublon>[];
  for (final c in candidats) {
    final m = normaliserMatricule(c.matricule);
    final parMat = m == null ? null : parMatricule[m];
    if (parMat != null) {
      resultat.add(Doublon(c, parMat, MotifDoublon.memeMatricule));
    } else if (c.dateNaissance != null && parNomDate[c.cleNomDate] != null) {
      resultat.add(Doublon(c, parNomDate[c.cleNomDate]!, MotifDoublon.memesNomPrenomsDateNaissance));
    }
    indexer(c);
  }
  return resultat;
}
