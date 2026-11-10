/// Reconstruction d'un tableau à partir de mots positionnés, tels que fournis
/// par l'extraction de texte d'un PDF ou par la reconnaissance optique (OCR)
/// d'un PDF scanné. Gère les colonnes mal alignées, les en-têtes répétés sur
/// plusieurs pages et les intitulés de plusieurs mots.
library;

import 'champs.dart';
import 'tableau.dart';

class MotPositionne {
  final String texte;
  final double gauche;
  final double haut;
  final double largeur;
  final double hauteur;
  final int page;

  const MotPositionne(this.texte, {required this.gauche, required this.haut, required this.largeur, required this.hauteur, this.page = 0});

  double get droite => gauche + largeur;
  double get centreX => gauche + largeur / 2;
  double get centreY => haut + hauteur / 2;

  @override
  String toString() => '«$texte» p$page (${gauche.toStringAsFixed(0)}, ${haut.toStringAsFixed(0)})';
}

/// Découpe un fragment de texte en mots, en répartissant sa largeur
/// proportionnellement au nombre de caractères (extraction PDF).
List<MotPositionne> decouperFragment(MotPositionne f) {
  final parties = f.texte.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parties.length <= 1) return parties.isEmpty ? const [] : [f];
  final total = f.texte.length;
  final resultat = <MotPositionne>[];
  var position = 0;
  for (final p in parties) {
    final debut = f.texte.indexOf(p, position);
    position = debut + p.length;
    resultat.add(MotPositionne(p,
        gauche: f.gauche + f.largeur * debut / total,
        haut: f.haut,
        largeur: f.largeur * p.length / total,
        hauteur: f.hauteur,
        page: f.page));
  }
  return resultat;
}

/// Regroupe les mots d'une page en lignes (de haut en bas, mots de gauche à droite).
List<List<MotPositionne>> grouperEnLignes(List<MotPositionne> mots) {
  final tries = [...mots]..sort((a, b) => a.centreY.compareTo(b.centreY));
  final lignes = <List<MotPositionne>>[];
  double? centre;
  double hauteur = 0;
  for (final m in tries) {
    if (centre != null && (m.centreY - centre).abs() <= 0.5 * (m.hauteur > hauteur ? m.hauteur : hauteur)) {
      final l = lignes.last..add(m);
      centre = l.fold<double>(0, (s, x) => s + x.centreY) / l.length;
      hauteur = l.fold<double>(0, (s, x) => s + x.hauteur) / l.length;
    } else {
      lignes.add([m]);
      centre = m.centreY;
      hauteur = m.hauteur;
    }
  }
  for (final l in lignes) {
    l.sort((a, b) => a.gauche.compareTo(b.gauche));
  }
  return lignes;
}

class _Ancre {
  final ChampListe champ;
  final double gauche;
  final double droite;
  final String libelle;
  _Ancre(this.champ, this.gauche, this.droite, this.libelle);
}

/// Intitulés reconnus dans une ligne : groupes de mots voisins (au plus
/// [motsMaxIntitule]) correspondant exactement à un intitulé connu, le plus
/// long d'abord. Deux mots trop éloignés n'appartiennent pas au même intitulé.
List<_Ancre> _ancres(List<MotPositionne> ligne, {bool strict = false}) {
  final ancres = <_Ancre>[];
  var i = 0;
  while (i < ligne.length) {
    _Ancre? trouvee;
    var longueur = 0;
    for (var n = motsMaxIntitule; n >= 1; n--) {
      if (i + n > ligne.length) continue;
      final groupe = ligne.sublist(i, i + n);
      var voisins = true;
      for (var k = 1; k < groupe.length; k++) {
        if (groupe[k].gauche - groupe[k - 1].droite > 1.2 * groupe[k].hauteur) voisins = false;
      }
      if (!voisins) continue;
      final libelle = groupe.map((m) => m.texte).join(' ');
      final champ = n == 1 && !strict ? reconnaitreEntete(libelle) : reconnaitreEnteteExact(libelle);
      if (champ != null) {
        trouvee = _Ancre(champ, groupe.first.gauche, groupe.last.droite, libelle);
        longueur = n;
        break;
      }
    }
    final t = trouvee;
    if (t != null && !ancres.any((a) => a.champ == t.champ)) {
      ancres.add(t);
      i += longueur;
    } else {
      i += longueur == 0 ? 1 : longueur;
    }
  }
  return ancres;
}

int _scoreAncres(List<_Ancre> a) {
  final champs = a.map((x) => x.champ).where((c) => c != ChampListe.numero).toSet();
  return champs.any((c) => c.estNom) ? champs.length : 0;
}

/// Construit le tableau d'un document à partir de ses mots positionnés.
///
/// - L'en-tête est la première ligne reconnaissant au moins deux champs dont
///   un nom ; une page qui a son propre en-tête recalcule les colonnes, une page
///   sans en-tête reprend celles de la page précédente.
/// - Chaque mot est placé dans la colonne dont il est le plus proche, ce qui
///   tolère des colonnes mal alignées.
/// - Sans en-tête reconnu, les cellules sont découpées aux grands espaces et
///   l'utilisateur affecte les colonnes.
TableauBrut grilleDepuisMots(List<MotPositionne> mots, {required String format}) {
  final pages = <int, List<MotPositionne>>{};
  for (final m in mots.where((m) => m.texte.trim().isNotEmpty)) {
    pages.putIfAbsent(m.page, () => []).add(m);
  }
  final numerosPages = pages.keys.toList()..sort();
  List<_Ancre>? colonnes;
  final lignesSortie = <List<String>>[];
  var enteteEcrite = false;

  for (final p in numerosPages) {
    final lignes = grouperEnLignes(pages[p]!);
    var debut = 0;
    for (var i = 0; i < lignes.length && i < 25; i++) {
      // Après le premier en-tête, seuls les intitulés exacts comptent (en-tête répété).
      final a = _ancres(lignes[i], strict: colonnes != null);
      if (_scoreAncres(a) >= 2) {
        colonnes = a..sort((x, y) => x.gauche.compareTo(y.gauche));
        debut = i + 1;
        break;
      }
    }
    if (colonnes == null) continue; // pas encore d'en-tête : titres, page de garde
    if (!enteteEcrite) {
      lignesSortie.add([for (final c in colonnes) c.libelle]);
      enteteEcrite = true;
    }
    final cols = colonnes;
    for (final ligne in lignes.skip(debut)) {
      if (_scoreAncres(_ancres(ligne, strict: true)) >= 2) continue; // en-tête répété
      final cellules = List<String>.filled(cols.length, '');
      for (final m in ligne) {
        // Mot entièrement à gauche de la première colonne (numéro d'ordre non titré) : ignoré.
        if (m.droite < cols.first.gauche - m.hauteur && cols.first.champ != ChampListe.numero) continue;
        final k = _colonneLaPlusProche(cols, m);
        cellules[k] = cellules[k].isEmpty ? m.texte : '${cellules[k]} ${m.texte}';
      }
      if (cellules.any((c) => c.isNotEmpty)) lignesSortie.add(cellules);
    }
  }

  if (colonnes == null) {
    // Aucun en-tête : découpage aux grands espaces.
    final lignes = <List<String>>[];
    for (final p in numerosPages) {
      for (final l in grouperEnLignes(pages[p]!)) {
        lignes.add(_decouperAuxEspaces(l));
      }
    }
    return TableauBrut(lignes: lignes, ligneEntete: null, correspondance: const {}, format: format);
  }
  return TableauBrut(
    lignes: lignesSortie,
    ligneEntete: 0,
    correspondance: {for (var i = 0; i < colonnes.length; i++) i: colonnes[i].champ},
    format: format,
  );
}

/// Colonne d'un mot : les limites entre colonnes sont placées à mi-chemin
/// entre la fin d'un intitulé et le début du suivant, ce qui tolère des
/// valeurs décalées par rapport à leur intitulé.
int _colonneLaPlusProche(List<_Ancre> cols, MotPositionne m) {
  for (var k = cols.length - 1; k > 0; k--) {
    final limite = (cols[k - 1].droite + cols[k].gauche) / 2;
    if (m.centreX >= limite) return k;
  }
  return 0;
}

List<String> _decouperAuxEspaces(List<MotPositionne> ligne) {
  final cellules = <String>[];
  final hauteurs = ligne.map((m) => m.hauteur).toList()..sort();
  final h = hauteurs[hauteurs.length ~/ 2];
  var courante = StringBuffer();
  for (var i = 0; i < ligne.length; i++) {
    if (i > 0 && ligne[i].gauche - ligne[i - 1].droite > 1.5 * h) {
      cellules.add(courante.toString());
      courante = StringBuffer();
    }
    if (courante.isNotEmpty) courante.write(' ');
    courante.write(ligne[i].texte);
  }
  cellules.add(courante.toString());
  return cellules;
}
