/// Lecture des fichiers CSV : encodage (UTF-8 ou Windows-1252, fréquent pour
/// les fichiers enregistrés par Excel en français), séparateur (point-virgule,
/// virgule ou tabulation) et guillemets.
library;

import 'dart:convert';

/// Caractères Windows-1252 de 0x80 à 0x9F (les autres octets valent Latin-1).
const List<int> _cp1252 = [
  0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0x017D, 0xFFFD, //
  0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0x017E, 0x0178,
];

/// Décode les octets d'un fichier texte : UTF-8 s'il est valide (avec ou sans
/// BOM), sinon Windows-1252.
String decoderTexte(List<int> octets) {
  var debut = 0;
  if (octets.length >= 3 && octets[0] == 0xEF && octets[1] == 0xBB && octets[2] == 0xBF) debut = 3;
  final contenu = octets.sublist(debut);
  try {
    return utf8.decode(contenu);
  } on FormatException {
    final b = StringBuffer();
    for (final o in contenu) {
      b.writeCharCode(o >= 0x80 && o <= 0x9F ? _cp1252[o - 0x80] : o);
    }
    return b.toString();
  }
}

/// Séparateur le plus fréquent (hors guillemets) sur les premières lignes.
String detecterSeparateur(String texte) {
  const candidats = [';', ',', '\t'];
  final lignes = texte.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).take(10).toList();
  var meilleur = ';';
  var score = -1;
  for (final c in candidats) {
    final total = lignes.fold<int>(0, (n, l) {
      var dans = false, compte = 0;
      for (final ch in l.split('')) {
        if (ch == '"') dans = !dans;
        if (!dans && ch == c) compte++;
      }
      return n + compte;
    });
    if (total > score) {
      score = total;
      meilleur = c;
    }
  }
  return meilleur;
}

/// Découpe un CSV (RFC 4180 : champs entre guillemets, guillemets doublés,
/// retours à la ligne dans un champ). Les lignes entièrement vides sont omises.
List<List<String>> lireCsv(String texte, {String? separateur}) {
  final sep = separateur ?? detecterSeparateur(texte);
  final lignes = <List<String>>[];
  var ligne = <String>[];
  final champ = StringBuffer();
  var dansGuillemets = false;
  var i = 0;
  void finChamp() {
    ligne.add(champ.toString().trim());
    champ.clear();
  }

  void finLigne() {
    finChamp();
    if (ligne.any((c) => c.isNotEmpty)) lignes.add(ligne);
    ligne = <String>[];
  }

  while (i < texte.length) {
    final ch = texte[i];
    if (dansGuillemets) {
      if (ch == '"') {
        if (i + 1 < texte.length && texte[i + 1] == '"') {
          champ.write('"');
          i++;
        } else {
          dansGuillemets = false;
        }
      } else {
        champ.write(ch);
      }
    } else if (ch == '"') {
      dansGuillemets = true;
    } else if (ch == sep) {
      finChamp();
    } else if (ch == '\n') {
      finLigne();
    } else if (ch != '\r') {
      champ.write(ch);
    }
    i++;
  }
  if (champ.isNotEmpty || ligne.isNotEmpty) finLigne();
  return lignes;
}
