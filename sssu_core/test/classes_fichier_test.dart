import 'package:excel/excel.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

/// Classes de l'enseignement technique, et fichiers de plusieurs classes
/// (une feuille par classe, ou une colonne « Classe »).
void main() {
  group('Classes de l\'enseignement technique', () {
    test('lecture dans un titre ou une cellule', () {
      expect(lireClasse('2nd G')!.libelle, '2nde G');
      expect(lireClasse('2nd G')!.niveau, '2NDE');
      expect(lireClasse('LISTE DE LA CLASSE DE 2nde G1 A — LYCÉE TECHNIQUE')!.libelle, '2nde G1 A');
      expect(lireClasse('Terminale F2-2')!.libelle, 'Tle F2 2');
      expect(lireClasse('PREMIERE G2')!.libelle, '1ère G2');
      expect(lireClasse('Seconde E')!.libelle, '2nde E');
      expect(lireClasse('Classe : BT 1')!.libelle, 'BT 1');
      expect(lireClasse('CAP2')!.libelle, 'CAP 2');
      expect(lireClasse('BTS 1')!.niveau, 'BTS');
      // Pas de mot pris pour une section.
      expect(lireClasse('CP1 EPP AGBO')!.libelle, 'CP1');
      expect(lireClasse('CM1 ET CM2')!.libelle, 'CM1');
      expect(lireClasse('CM2 A 2026-2027')!.libelle, 'CM2 A');
    });

    test('enseignement général : séries A1, A2, C, D et numéros de classe', () {
      expect(lireClasse('Terminale A1')!.libelle, 'Tle A1');
      expect(lireClasse('LISTE DE LA 1ère D 2 — LYCÉE MODERNE')!.libelle, '1ère D 2');
      expect(lireClasse('Seconde C')!.libelle, '2nde C');
      expect(lireClasse('3e B')!.libelle, '3ème B');
      expect(lireClasse('6ème 4')!.libelle, '6ème 4');
      expect(cleClasse('Tle A2'), cleClasse('TERMINALE A2'));
      expect(cleClasse('1ère D-2'), cleClasse('1ERE D 2'));
      const classes = [
        ClasseConnue(id: 'd1', etablissementId: 'lm', libelle: 'Tle D1'),
        ClasseConnue(id: 'd2', etablissementId: 'lm', libelle: 'Tle D2'),
        ClasseConnue(id: 'a1', etablissementId: 'lm', libelle: 'Tle A1'),
      ];
      expect(rapprocherClasse(lireClasse('TERMINALE D 2')!, 'lm', classes)!.id, 'd2');
      expect(rapprocherClasse(lireClasse('Terminale A1')!, 'lm', classes)!.id, 'a1');
    });

    test('libellés comparables à l\'écriture près', () {
      expect(cleClasse('2nd G1'), cleClasse('2nde G1'));
      expect(cleClasse('Seconde G1'), cleClasse('2nde G1'));
      expect(cleClasse('2NDE G1 A'), cleClasse('2nde G1-A'));
      expect(cleClasse('Tle F2-2'), cleClasse('TLE F22'));
      expect(cleClasse('BT 1'), 'BT1');
      expect(niveauDeClasse('Tle G2'), 'TLE');
      expect(niveauDeClasse('Groupe bleu'), isNull);
    });

    test('rapprochement avec les classes de l\'établissement', () {
      const classes = [
        ClasseConnue(id: 'g1', etablissementId: 'lt', libelle: '2nde G1'),
        ClasseConnue(id: 'g2', etablissementId: 'lt', libelle: '2nde G2'),
        ClasseConnue(id: 'f2', etablissementId: 'lt', libelle: 'Tle F2'),
        ClasseConnue(id: 'x', etablissementId: 'autre', libelle: '2nde G'),
      ];
      expect(rapprocherClasse(lireClasse('2nd G1')!, 'lt', classes)!.id, 'g1');
      expect(rapprocherClasse(lireClasse('Seconde G2')!, 'lt', classes)!.id, 'g2');
      expect(rapprocherClasse(lireClasse('2nde G')!, 'lt', classes), isNull, reason: 'à créer dans cet établissement');
      expect(rapprocherClasse(lireClasse('Terminale')!, 'lt', classes)!.id, 'f2', reason: 'seule classe de Tle');
      expect(rapprocherClasse(lireClasse('2nde')!, 'lt', classes), isNull, reason: 'deux classes de 2nde');
      expect(rapprocherClasse(const ClasseLue('Groupe bleu', ''), 'lt', classes), isNull);
    });

    test('classes proposées à la saisie', () {
      expect(suggestionsClasses('2nd g'), ['2nde G', '2nde G1', '2nde G2']);
      expect(suggestionsClasses('tle f'), ['Tle F1', 'Tle F2', 'Tle F3', 'Tle F4', 'Tle F7']);
      expect(suggestionsClasses('g1'), ['2nde G1', '1ère G1', 'Tle G1']);
      expect(suggestionsClasses('BT'), ['BT 1', 'BT 2', 'BT 3']);
      // Enseignement général.
      expect(suggestionsClasses('tle a'), ['Tle A1', 'Tle A2']);
      expect(suggestionsClasses('1ere'), ['1ère A1', '1ère A2', '1ère C', '1ère D', '1ère B', '1ère E', '1ère F1', '1ère F2',
          '1ère F3', '1ère F4', '1ère F7', '1ère G1', '1ère G2']);
      expect(suggestionsClasses('2nde c'), ['2nde C']);
      expect(suggestionsClasses(''), isEmpty);
    });
  });

  group('Fichier de plusieurs classes', () {
    test('une feuille par classe ; explications et feuilles vides écartées', () {
      final tableaux = tableauxDuClasseur(const [
        FeuilleBrute('Explications', [
          ['Une feuille par classe.'],
          ['Renommez chaque feuille avec le libellé de la classe.'],
        ]),
        FeuilleBrute('2nde G1', [
          ['N°', 'Nom', 'Prénoms', 'Sexe'],
          ['1', 'KOUASSI', 'Aya', 'F'],
          ['2', 'KONAN', 'Yao', 'M'],
        ]),
        FeuilleBrute('Tle F2', [
          ['LYCÉE TECHNIQUE DE BOUAKÉ'],
          ['N°', 'Nom', 'Prénoms', 'Sexe'],
          ['1', 'TRAORE', 'Awa', 'F'],
        ]),
        FeuilleBrute('Feuil3', [
          ['N°', 'Nom', 'Prénoms', 'Sexe'],
        ]),
      ]);
      expect(tableaux.map((t) => t.feuille), ['2nde G1', 'Tle F2']);
      final groupes = grouperParClasse(tableaux);
      expect(groupes.map((g) => g.classeLue!.libelle), ['2nde G1', 'Tle F2']);
      expect(groupes.map((g) => g.origine), ['Feuille « 2nde G1 »', 'Feuille « Tle F2 »']);
      final l = analyserTableau(groupes[1].tableau).single;
      expect((l.nom, l.numeroSource), ('TRAORE', 3));
    });

    test('feuilles sans nom de classe : la classe vient des titres', () {
      final groupes = grouperParClasse(tableauxDuClasseur(const [
        FeuilleBrute('Feuil1', [
          ['CLASSE DE CM2 A'],
          ['Nom et prénoms', 'Sexe'],
          ['SORO Ali', 'M'],
        ]),
        FeuilleBrute('Feuil2', [
          ['CLASSE DE CM2 B'],
          ['Nom et prénoms', 'Sexe'],
          ['YAO Ange', 'F'],
        ]),
      ]));
      expect(groupes.map((g) => g.classeLue!.libelle), ['CM2 A', 'CM2 B']);
    });

    test('classeur sans en-tête reconnu : la feuille la plus remplie', () {
      final t = tableauxDuClasseur(const [
        FeuilleBrute('A', [
          ['x']
        ]),
        FeuilleBrute('B', [
          ['KOUASSI Aya', 'F'],
          ['KONAN Yao', 'M'],
        ]),
      ]);
      expect(t.single.feuille, 'B');
      expect(t.single.ligneEntete, isNull);
    });

    test('colonne « Classe » : une classe par valeur, cellules fusionnées, numéros d\'origine', () {
      final t = tableauDepuisLignes([
        ['LISTE DES ÉLÈVES'],
        ['N°', 'Classe', 'Nom et prénoms', 'Sexe'],
        ['1', '2nd G1', 'KOUASSI Aya', 'F'],
        ['2', '', 'KONAN Yao', 'M'],
        ['3', '2nde G2', 'TRAORE Awa', 'F'],
        ['4', '2NDE G1', 'BAMBA Ali', 'M'],
      ], format: 'xlsx', feuille: 'Feuil1');
      expect(t.correspondance[1], ChampListe.classe);
      final groupes = grouperParClasse([t]);
      expect(groupes.length, 2);
      expect(groupes[0].origine, 'Classe « 2nd G1 »');
      expect(groupes[0].classeLue!.libelle, '2nde G1');
      final g1 = analyserTableau(groupes[0].tableau);
      expect(g1.map((l) => l.nom), ['KOUASSI', 'KONAN', 'BAMBA']);
      expect(g1.map((l) => l.numeroSource), [3, 4, 6]);
      expect(analyserTableau(groupes[1].tableau).single.numeroSource, 5);
    });

    test('valeur de classe non reconnue gardée telle quelle', () {
      final groupes = grouperParClasse([
        tableauDepuisLignes([
          ['Classe', 'Nom', 'Prénoms'],
          ['Groupe bleu', 'SORO', 'Ali'],
        ], format: 'csv'),
      ]);
      expect(groupes.single.classeLue!.libelle, 'Groupe bleu');
      expect(groupes.single.classeLue!.niveau, '');
    });

    test('ligne de titre « Classe | Nom de l\'enseignant » : pas l\'en-tête', () {
      final t = tableauDepuisLignes([
        ['Classe', 'Nom de l\'enseignant'],
        ['N°', 'Nom', 'Prénoms', 'Sexe'],
        ['1', 'SORO', 'Ali', 'M'],
      ], format: 'xlsx');
      expect(t.ligneEntete, 1);
    });

    test('doublon dans une autre classe du fichier : la classe est précisée', () {
      LigneImport ligne(int n, String groupe) => LigneImport(
          numeroSource: n,
          brut: const {},
          matricule: '12345678A',
          nom: 'KOUASSI',
          prenoms: 'Aya',
          sexe: Sexe.feminin,
          dateNaissance: DateTime.utc(2010, 3, 2),
          groupe: groupe);
      final lignes = [ligne(3, '2nde G1'), ligne(7, '2nde G2')];
      controlerLignes(lignes, dateReference: DateTime.utc(2026, 11, 13));
      expect(lignes[1].anomalies.map((a) => a.message), contains('Doublon de la ligne 3 de « 2nde G1 » (même matricule).'));
      expect(lignes[1].action, ActionImport.ignorer);
    });

    test('modèle Excel : une feuille par classe, reconnue une fois remplie', () {
      final modele = Excel.decodeBytes(modeleListeEleves(classes: const ['CM2 A', '2nde G1']));
      expect(modele.tables.keys, containsAll(['Explications', 'CM2 A', '2nde G1']));
      modele['2nde G1'].appendRow([
        TextCellValue('1'), TextCellValue('12345678A'), TextCellValue('KOFFI'), TextCellValue('Ange'),
        TextCellValue('12/09/2009'), TextCellValue('F'), TextCellValue(''),
      ]);
      final relu = Excel.decodeBytes(modele.encode()!);
      final feuilles = [
        for (final e in relu.tables.entries)
          FeuilleBrute(e.key, [
            for (final r in e.value.rows)
              if (r.any((c) => (c?.value?.toString() ?? '').trim().isNotEmpty))
                [for (final c in r) (c?.value?.toString() ?? '').trim()]
          ])
      ];
      final groupes = grouperParClasse(tableauxDuClasseur(feuilles));
      expect(groupes.single.classeLue!.libelle, '2nde G1');
      expect(analyserTableau(groupes.single.tableau).single.nom, 'KOFFI');
    });
  });
}
