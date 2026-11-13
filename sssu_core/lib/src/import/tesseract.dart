/// Lecture du résultat de Tesseract OCR (poste central Windows) au format TSV :
/// `tesseract page.png stdout -l fra --psm 6 -c tessedit_create_tsv=1`.
library;

import 'mots.dart';

class MotOcr {
  final MotPositionne mot;

  /// Confiance de Tesseract, de 0 à 100.
  final double confiance;
  const MotOcr(this.mot, this.confiance);
}

/// Mots (niveau 5) du TSV de Tesseract, avec leur position et leur confiance.
List<MotOcr> motsDepuisTsvTesseract(String tsv, {int page = 0}) {
  final resultat = <MotOcr>[];
  final lignes = tsv.split(RegExp(r'\r?\n'));
  if (lignes.isEmpty) return resultat;
  final entete = lignes.first.split('\t');
  int col(String nom) => entete.indexOf(nom);
  final iNiveau = col('level'), iG = col('left'), iH = col('top'), iL = col('width'), iHt = col('height');
  final iConf = col('conf'), iTexte = col('text');
  if ([iNiveau, iG, iH, iL, iHt, iConf, iTexte].any((i) => i < 0)) {
    throw const FormatException('Sortie Tesseract inattendue (TSV sans en-tête).');
  }
  for (final l in lignes.skip(1)) {
    final c = l.split('\t');
    if (c.length <= iTexte || c[iNiveau] != '5') continue;
    final texte = c[iTexte].trim();
    if (texte.isEmpty) continue;
    resultat.add(MotOcr(
      MotPositionne(
        texte,
        gauche: double.parse(c[iG]),
        haut: double.parse(c[iH]),
        largeur: double.parse(c[iL]),
        hauteur: double.parse(c[iHt]),
        page: page,
      ),
      double.tryParse(c[iConf]) ?? 0,
    ));
  }
  return resultat;
}
