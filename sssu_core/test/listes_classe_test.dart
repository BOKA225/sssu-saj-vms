import 'package:excel/excel.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

/// Listes de classe par établissement : ordre des classes, document à
/// imprimer, classeur Excel d'une feuille par classe (réimportable).
void main() {
  Droits droits(RoleCode r) => Droits(utilisateurId: 'u', role: r, permissions: matriceParDefaut[r]!);
  const entete = EnteteRapport(lignes: ['DISTRICT SANITAIRE DE KOUASSI-KOUASSIKRO']);
  final classes = [
    const ListeDeClasse(classeId: 'c1', libelle: 'CM2 A', eleves: [
      EleveListe(id: 'e1', matricule: '12345678A', nom: 'KOUASSI', prenoms: 'Aya', sexe: 'F', dateNaissance: '2014-03-02',
          telephone: '0707070707'),
      EleveListe(id: 'e2', nom: 'SORO', prenoms: 'Ali', sexe: 'M'),
    ]),
    const ListeDeClasse(classeId: 'c2', libelle: 'Tle D', eleves: []),
  ];

  test('ordre scolaire des classes, nombres compris', () {
    final l = ['Tle D', 'CM2 A', '6ème 10', '6ème 2', 'CP1', '2nde G1', 'BT 1', 'Groupe bleu', 'CE1', '1ère A1'];
    l.sort(comparerClasses);
    expect(l, ['CP1', 'CE1', 'CM2 A', '6ème 2', '6ème 10', '2nde G1', '1ère A1', 'Tle D', 'BT 1', 'Groupe bleu']);
  });

  test('document : un tableau par classe, classe vide signalée, âge, droits', () {
    expect(
        () => rapportListesDeClasse(
            etablissement: 'EPP X', annee: '2026-2027', classes: classes, entete: entete,
            acteur: droits(RoleCode.agent), genereLe: DateTime.utc(2026, 11, 14)),
        throwsA(isA<RapportRefuse>()));
    final d = rapportListesDeClasse(
        etablissement: 'EPP X', annee: '2026-2027', classes: classes, entete: entete,
        acteur: droits(RoleCode.admin), genereLe: DateTime.utc(2026, 11, 14));
    expect(d.titre, 'Listes de classe');
    expect(d.sousTitre, 'EPP X · 2 classes, 2 élèves · année 2026-2027');
    expect(d.confidentiel, isTrue);
    expect(d.blocs.map((b) => b.runtimeType.toString()),
        ['BlocTitre', 'BlocTableau', 'BlocSautDePage', 'BlocTitre', 'BlocParagraphe']);
    expect((d.blocs.first as BlocTitre).texte, 'CM2 A — 2 élèves (1 G, 1 F)');
    final t = d.blocs[1] as BlocTableau;
    expect(t.lignes.first, [1, '12345678A', 'KOUASSI Aya', 'F', '02/03/2014', '12 ans', '0707070707']);
    expect(t.lignes.last, [2, '', 'SORO Ali', 'M', '', '', '']);
    // Rendus Word et Excel sans erreur.
    expect(rendreWord(d), isNotEmpty);
    expect(rendreExcel(d), isNotEmpty);
    final une = rapportListesDeClasse(
        etablissement: 'EPP X', annee: '2026-2027', classes: [classes.first], entete: entete,
        acteur: droits(RoleCode.medecin), genereLe: DateTime.utc(2026, 11, 14));
    expect((une.titre, une.sousTitre), ('Liste de classe', 'EPP X · CM2 A · année 2026-2027'));
  });

  test('classeur Excel : une feuille par classe, noms valides et uniques, réimportable', () {
    final x = Excel.decodeBytes(classeurListesDeClasse([
      ...classes,
      const ListeDeClasse(classeId: 'c3', libelle: 'cm2 a', eleves: []),
      const ListeDeClasse(classeId: 'c4', libelle: 'CP1/CP2', eleves: []),
    ]));
    expect(x.tables.keys, ['CM2 A', 'Tle D', 'cm2 a (2)', 'CP1-CP2']);
    final feuilles = [
      for (final e in x.tables.entries)
        FeuilleBrute(e.key, [
          for (final r in e.value.rows)
            if (r.any((c) => (c?.value?.toString() ?? '').trim().isNotEmpty))
              [for (final c in r) (c?.value?.toString() ?? '').trim()]
        ])
    ];
    final groupes = grouperParClasse(tableauxDuClasseur(feuilles));
    expect(groupes.single.classeLue!.libelle, 'CM2 A');
    final lignes = analyserTableau(groupes.single.tableau);
    expect(lignes.map((l) => (l.matricule, l.nom, l.prenoms, l.sexe, l.dateNaissance, l.telephone)), [
      ('12345678A', 'KOUASSI', 'Aya', Sexe.feminin, DateTime.utc(2014, 3, 2), '0707070707'),
      (null, 'SORO', 'Ali', Sexe.masculin, null, null),
    ]);
  });
}
