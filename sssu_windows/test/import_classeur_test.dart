// Classeur Excel de plusieurs classes lu sur le poste central.
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sssu_core/sssu_core.dart';
import 'package:sssu_windows/import/lecteurs_poste.dart';

void main() {
  late Directory dossier;
  setUp(() async => dossier = await Directory.systemTemp.createTemp('sssu_classeur'));
  tearDown(() async => dossier.delete(recursive: true));

  test('modèle rempli : une liste par feuille de classe, feuilles vides et explications écartées', () async {
    final x = Excel.decodeBytes(modeleListeEleves(classes: const ['CM2 A', '2nde G', '2nde G1']));
    for (final (feuille, nom) in [('2nde G', 'KOFFI'), ('2nde G1', 'TRAORE')]) {
      x[feuille].appendRow([
        TextCellValue('1'), TextCellValue(''), TextCellValue(nom), TextCellValue('Ange'),
        DateCellValue(year: 2010, month: 2, day: 3), TextCellValue('F'),
      ]);
    }
    final chemin = p.join(dossier.path, 'eleves.xlsx');
    File(chemin).writeAsBytesSync(x.encode()!);
    final tableaux = await LecteurListes().lireTableaux(chemin);
    expect(tableaux.map((t) => t.feuille), ['2nde G', '2nde G1']);
    final groupes = grouperParClasse(tableaux);
    expect(groupes.map((g) => g.classeLue!.libelle), ['2nde G', '2nde G1']);
    final l = analyserTableau(groupes.first.tableau).single;
    expect((l.nom, l.dateNaissance), ('KOFFI', DateTime.utc(2010, 2, 3)));
  });

  test('fichier CSV : une seule liste, colonne « Classe » répartie', () async {
    final chemin = p.join(dossier.path, 'eleves.csv');
    File(chemin).writeAsStringSync('Classe;Nom;Prénoms;Sexe\n2nd G1;KOFFI;Ange;F\nTle F2;TRAORE;Awa;F\n');
    final tableaux = await LecteurListes().lireTableaux(chemin);
    expect(tableaux.length, 1);
    expect(grouperParClasse(tableaux).map((g) => g.classeLue!.libelle), ['2nde G1', 'Tle F2']);
  });
}
