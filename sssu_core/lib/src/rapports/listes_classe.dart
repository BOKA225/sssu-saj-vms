/// Listes de classe d'un établissement : document à imprimer (PDF, Word),
/// un tableau par classe, et classeur Excel d'une feuille par classe aux
/// colonnes du modèle d'importation (le classeur peut être réimporté).
/// Identité seulement : aucune donnée médicale.
library;

import 'dart:math' as math;

import 'package:excel/excel.dart';

import '../auth/permissions.dart';
import '../commun/commun.dart';
import '../regles/age.dart';
import 'document.dart';
import 'rapports.dart' show RapportRefuse;

/// Élève d'une liste de classe.
class EleveListe {
  final String id;
  final String? matricule;
  final String nom;
  final String prenoms;

  /// « M » ou « F ».
  final String sexe;

  /// Date de naissance (AAAA-MM-JJ).
  final String? dateNaissance;
  final String? telephone;

  /// Date de la dernière visite de l'année (AAAA-MM-JJ), affichée à l'écran.
  final String? derniereVisite;
  final String? statutVisite;

  const EleveListe({
    required this.id,
    this.matricule,
    required this.nom,
    required this.prenoms,
    required this.sexe,
    this.dateNaissance,
    this.telephone,
    this.derniereVisite,
    this.statutVisite,
  });

  String get nomComplet => '$nom $prenoms';
}

/// Classe et ses élèves (inscrits, triés par nom).
class ListeDeClasse {
  final String classeId;
  final String libelle;
  final String? niveau;
  final List<EleveListe> eleves;
  const ListeDeClasse({required this.classeId, required this.libelle, this.niveau, required this.eleves});

  int get garcons => eleves.where((e) => e.sexe == 'M').length;
  int get filles => eleves.where((e) => e.sexe == 'F').length;

  /// « 32 élèves (15 G, 17 F) ».
  String get effectif =>
      '${eleves.length} élève${eleves.length > 1 ? 's' : ''} ($garcons G, $filles F)';
}

/// Exporter une liste de classe : droit des listes nominatives, ou de ceux
/// qui gèrent les dossiers des élèves (importation, établissements).
bool peutExporterListesDeClasse(Droits a) => a.peut(Permission.rapportExporterNominatif) || a.peutGererEleves;

String _dateFr(String? iso) {
  if (iso == null) return '';
  final d = lireDate(iso);
  String z(int n) => n.toString().padLeft(2, '0');
  return '${z(d.day)}/${z(d.month)}/${d.year}';
}

/// Document des listes de classe : un tableau par classe, une page par classe.
DocumentRapport rapportListesDeClasse({
  required String etablissement,
  required String annee,
  required List<ListeDeClasse> classes,
  required EnteteRapport entete,
  required Droits acteur,
  required DateTime genereLe,
}) {
  if (!peutExporterListesDeClasse(acteur)) {
    throw const RapportRefuse('Vous n\'êtes pas autorisé à exporter les listes de classe.');
  }
  final blocs = <BlocRapport>[];
  for (var k = 0; k < classes.length; k++) {
    final c = classes[k];
    if (k > 0) blocs.add(const BlocSautDePage());
    blocs.add(BlocTitre('${c.libelle} — ${c.effectif}'));
    if (c.eleves.isEmpty) {
      blocs.add(const BlocParagraphe('Aucun élève inscrit.', italique: true));
      continue;
    }
    blocs.add(BlocTableau(
      entetes: const ['N°', 'Matricule', 'Nom et prénoms', 'Sexe', 'Date de naissance', 'Âge', 'Téléphone du parent'],
      largeurs: const [0.6, 1.6, 4.2, 0.7, 1.6, 0.8, 1.8],
      lignes: [
        for (var i = 0; i < c.eleves.length; i++)
          [
            i + 1,
            c.eleves[i].matricule ?? '',
            c.eleves[i].nomComplet,
            c.eleves[i].sexe,
            _dateFr(c.eleves[i].dateNaissance),
            c.eleves[i].dateNaissance == null
                ? ''
                : '${calculerAge(lireDate(c.eleves[i].dateNaissance!), genereLe).annees} ans',
            c.eleves[i].telephone ?? '',
          ]
      ],
    ));
  }
  final total = classes.fold<int>(0, (s, c) => s + c.eleves.length);
  return DocumentRapport(
    titre: classes.length == 1 ? 'Liste de classe' : 'Listes de classe',
    sousTitre: classes.length == 1
        ? '$etablissement · ${classes.single.libelle} · année $annee'
        : '$etablissement · ${classes.length} classes, $total élèves · année $annee',
    entete: entete,
    blocs: blocs.isEmpty ? const [BlocParagraphe('Aucune classe.')] : blocs,
    genereLe: genereLe,
    confidentiel: true,
  );
}

/// Classeur Excel : une feuille par classe, nommée comme la classe, aux
/// colonnes du modèle d'importation.
List<int> classeurListesDeClasse(List<ListeDeClasse> classes) {
  final excel = Excel.createExcel();
  final defaut = excel.getDefaultSheet() ?? 'Sheet1';
  final pris = <String>{};
  // Nom de feuille valide pour Excel : 31 caractères, sans : \ / ? * [ ], unique.
  String nomFeuille(String libelle) {
    var n = libelle.replaceAll(RegExp(r'[:\\/?*\[\]]'), '-').trim();
    if (n.isEmpty) n = 'Classe';
    if (n.length > 31) n = n.substring(0, 31);
    var u = n;
    for (var k = 2; !pris.add(u.toLowerCase()); k++) {
      final suffixe = ' ($k)';
      u = '${n.substring(0, math.min(n.length, 31 - suffixe.length))}$suffixe';
    }
    return u;
  }

  const entetes = ['N°', 'Matricule', 'Nom', 'Prénoms', 'Date de naissance', 'Sexe', 'Téléphone du parent'];
  final gras = CellStyle(bold: true);
  if (classes.isEmpty) excel.rename(defaut, 'Aucune classe');
  for (var k = 0; k < classes.length; k++) {
    final c = classes[k];
    final nom = nomFeuille(c.libelle);
    if (k == 0) excel.rename(defaut, nom);
    final f = excel[nom];
    for (var col = 0; col < entetes.length; col++) {
      f.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
        ..value = TextCellValue(entetes[col])
        ..cellStyle = gras;
      f.setColumnWidth(col, col == 2 || col == 3 ? 26 : 16);
    }
    for (var i = 0; i < c.eleves.length; i++) {
      final e = c.eleves[i];
      final valeurs = <CellValue>[
        IntCellValue(i + 1),
        TextCellValue(e.matricule ?? ''),
        TextCellValue(e.nom),
        TextCellValue(e.prenoms),
        TextCellValue(_dateFr(e.dateNaissance)),
        TextCellValue(e.sexe),
        TextCellValue(e.telephone ?? ''),
      ];
      for (var col = 0; col < valeurs.length; col++) {
        f.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: i + 1)).value = valeurs[col];
      }
    }
  }
  return excel.encode()!;
}
