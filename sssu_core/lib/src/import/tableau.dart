/// Tableau brut extrait d'un fichier (Excel, CSV, PDF ou image) et détection
/// de la ligne d'en-tête et des colonnes.
library;

import 'champs.dart';

class TableauBrut {
  /// Cellules, ligne par ligne (texte tel que lu dans le fichier).
  final List<List<String>> lignes;

  /// Index de la ligne d'en-tête, ou `null` si aucune n'a été reconnue
  /// (l'utilisateur affecte alors les colonnes lui-même).
  final int? ligneEntete;

  /// Champ affecté à chaque colonne (index → champ).
  final Map<int, ChampListe> correspondance;

  /// Origine, pour l'affichage et le journal (`xlsx`, `csv`, `pdf`, `pdf_ocr`).
  final String format;

  const TableauBrut({required this.lignes, required this.ligneEntete, required this.correspondance, required this.format});

  int get nombreColonnes => lignes.fold(0, (m, l) => l.length > m ? l.length : m);

  TableauBrut avecCorrespondance(Map<int, ChampListe> c, {int? ligneEntete}) =>
      TableauBrut(lignes: lignes, ligneEntete: ligneEntete ?? this.ligneEntete, correspondance: c, format: format);
}

class EnteteDetectee {
  final int index;
  final Map<int, ChampListe> correspondance;
  const EnteteDetectee(this.index, this.correspondance);
}

/// Note d'une ligne candidate : nombre de champs distincts reconnus (hors
/// numéro d'ordre), à condition qu'un champ de nom soit présent.
int _score(Map<int, ChampListe> c) {
  final champs = c.values.where((f) => f != ChampListe.numero && f != ChampListe.ignorer).toSet();
  if (!champs.any((f) => f.estNom)) return 0;
  return champs.length;
}

/// Champs reconnus dans une ligne. [strict] : intitulés exacts uniquement
/// (sans les règles « commence par NOM… »), pour ne pas confondre un élève
/// nommé « NOMEL » avec un intitulé.
Map<int, ChampListe> correspondanceDeLigne(List<String> cellules, {bool strict = false}) {
  final c = <int, ChampListe>{};
  for (var i = 0; i < cellules.length; i++) {
    final f = strict ? reconnaitreEnteteExact(cellules[i]) : reconnaitreEntete(cellules[i]);
    if (f != null && !c.containsValue(f)) c[i] = f;
  }
  return c;
}

/// Cherche la ligne d'en-tête parmi les [profondeur] premières lignes :
/// celle qui reconnaît le plus de champs (au moins deux, dont un nom).
EnteteDetectee? detecterEntete(List<List<String>> lignes, {int profondeur = 20}) {
  EnteteDetectee? meilleure;
  var meilleurScore = 1;
  for (var i = 0; i < lignes.length && i < profondeur; i++) {
    final c = correspondanceDeLigne(lignes[i]);
    final s = _score(c);
    if (s > meilleurScore) {
      meilleurScore = s;
      meilleure = EnteteDetectee(i, c);
    }
  }
  return meilleure;
}

/// Une ligne de données qui reprend l'en-tête (en-tête répété sur chaque page).
bool estEnteteRepete(List<String> cellules) => _score(correspondanceDeLigne(cellules, strict: true)) >= 2;

/// Construit un tableau à partir de lignes de cellules (Excel, CSV) en
/// détectant l'en-tête.
TableauBrut tableauDepuisLignes(List<List<String>> lignes, {required String format}) {
  final e = detecterEntete(lignes);
  return TableauBrut(lignes: lignes, ligneEntete: e?.index, correspondance: e?.correspondance ?? {}, format: format);
}
