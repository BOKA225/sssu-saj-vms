/// Plusieurs classes dans un même fichier : une feuille Excel par classe
/// (« CM2 A », « 2nde G1 »…), ou une colonne « Classe ». Le fichier est
/// découpé en groupes, un par classe ; chaque groupe est analysé comme une
/// liste ordinaire, puis importé dans sa classe après validation.
library;

import '../regles/identite.dart';
import 'champs.dart';
import 'reconnaissance.dart';
import 'tableau.dart';

/// Feuille d'un classeur, lue en lignes de texte (lignes vides retirées).
class FeuilleBrute {
  final String nom;
  final List<List<String>> lignes;
  const FeuilleBrute(this.nom, this.lignes);
}

/// Nom donné par défaut à une feuille (« Feuil1 », « Sheet2 », « Feuille 3 »,
/// « Liste ») : il ne dit rien de la classe.
bool estNomFeuilleParDefaut(String nom) => RegExp(r'^(FEUIL|FEUILLE|SHEET|TABLEAU|ONGLET|PAGE|LISTE|ELEVES|LISTE DES ELEVES)? ?[0-9]*$')
    .hasMatch(normaliserTexte(nom).replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim());

/// Listes d'élèves d'un classeur : chaque feuille dont l'en-tête est reconnu
/// et suivi d'au moins une ligne (les feuilles d'explications, de
/// récapitulatif ou vides sont écartées) ; à défaut, la feuille la plus
/// remplie, dont l'utilisateur indique les colonnes.
List<TableauBrut> tableauxDuClasseur(List<FeuilleBrute> feuilles, {String format = 'xlsx'}) {
  final listes = <TableauBrut>[];
  for (final f in feuilles) {
    if (f.lignes.isEmpty) continue;
    final t = tableauDepuisLignes(f.lignes, format: format, feuille: f.nom);
    if (t.ligneEntete != null && t.lignes.length > t.ligneEntete! + 1) listes.add(t);
  }
  if (listes.isNotEmpty) return listes;
  final remplies = [for (final f in feuilles) if (f.lignes.isNotEmpty) f];
  if (remplies.isEmpty) return const [];
  final plus = remplies.reduce((a, b) => b.lignes.length > a.lignes.length ? b : a);
  return [tableauDepuisLignes(plus.lignes, format: format, feuille: plus.nom)];
}

/// Élèves d'une même classe dans un fichier.
class GroupeClasse {
  /// Libellé affiché : « Feuille « CM2 A » », « Classe « 2nde G1 » ».
  final String origine;

  /// Lignes de cette classe, avec l'en-tête et les numéros de ligne d'origine.
  final TableauBrut tableau;

  /// Textes où lire la classe, du plus sûr au moins sûr (nom de la feuille,
  /// titres de la feuille).
  final List<String> indices;

  /// Valeur de la colonne « Classe » (null : classe donnée par la feuille).
  final String? valeurColonne;

  const GroupeClasse({required this.origine, required this.tableau, this.indices = const [], this.valeurColonne});

  /// Classe lue : reconnue (« 2nd G1 » → « 2nde G1 », niveau « 2NDE »), ou
  /// valeur de la colonne « Classe » telle quelle (niveau vide).
  ClasseLue? get classeLue {
    final v = valeurColonne?.trim();
    if (v != null && v.isNotEmpty) return lireClasse(v) ?? ClasseLue(v, '');
    for (final s in indices) {
      final c = lireClasse(s);
      if (c != null) return c;
    }
    return null;
  }

  /// Nom court de la classe pour les tableaux (« 2nde G1 », sinon l'origine).
  String get libelle => classeLue?.libelle ?? origine;
}

/// Découpe un fichier en classes :
/// - une feuille = une classe (nom de la feuille, sinon titres de la feuille) ;
/// - dans une feuille, la colonne « Classe » (si elle est affectée) répartit
///   les lignes, une classe par valeur ; une cellule vide reprend la classe de
///   la ligne précédente (cellules fusionnées).
List<GroupeClasse> grouperParClasse(List<TableauBrut> tableaux) {
  final groupes = <GroupeClasse>[];
  final plusieursFeuilles = tableaux.length > 1;
  for (final t in tableaux) {
    final feuille = t.feuille;
    final indicesFeuille = [if (feuille != null && !estNomFeuilleParDefaut(feuille)) feuille, ...t.titres];
    final colonne = [for (final e in t.correspondance.entries) if (e.value == ChampListe.classe) e.key].firstOrNull;
    if (colonne == null) {
      groupes.add(GroupeClasse(
        origine: feuille == null ? 'Liste' : 'Feuille « $feuille »',
        tableau: t,
        indices: indicesFeuille,
      ));
      continue;
    }
    final debut = t.ligneEntete == null ? 0 : t.ligneEntete! + 1;
    final parClasse = <String, List<int>>{};
    final valeurs = <String, String>{};
    var cle = '';
    for (var i = debut; i < t.lignes.length; i++) {
      final l = t.lignes[i];
      final v = colonne < l.length ? l[colonne].trim() : '';
      if (v.isNotEmpty && !estEnteteRepete(l)) {
        cle = cleClasse(v);
        valeurs.putIfAbsent(cle, () => v);
      }
      (parClasse[cle] ??= []).add(i);
    }
    final entete = t.ligneEntete == null ? const <int>[] : [t.ligneEntete!];
    for (final e in parClasse.entries) {
      final valeur = valeurs[e.key];
      final index = [...entete, ...e.value];
      final nom = valeur == null ? 'Classe non indiquée' : 'Classe « $valeur »';
      groupes.add(GroupeClasse(
        origine: plusieursFeuilles && feuille != null ? '$nom, feuille « $feuille »' : nom,
        tableau: TableauBrut(
          lignes: [for (final i in index) t.lignes[i]],
          numeros: [for (final i in index) t.numeroLigne(i)],
          ligneEntete: t.ligneEntete == null ? null : 0,
          correspondance: t.correspondance,
          format: t.format,
          texteAvant: t.titres,
          feuille: feuille,
        ),
        // Lignes sans classe indiquée : classe de la feuille ou des titres.
        indices: valeur == null ? indicesFeuille : const [],
        valeurColonne: valeur,
      ));
    }
  }
  return groupes;
}
