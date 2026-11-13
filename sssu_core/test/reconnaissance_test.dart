import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

/// Reconnaissance de l'établissement et de la classe d'une liste importée.
void main() {
  const etabs = [
    EtablissementConnu(id: 'e1', nom: 'EPP Kouassikro 1', code: 'KKR001'),
    EtablissementConnu(id: 'e2', nom: 'EPP Kouassikro 2', code: 'KKR002'),
    EtablissementConnu(id: 'e3', nom: 'Collège Moderne de Kouassi-Kouassikro', code: 'CMKK'),
    EtablissementConnu(id: 'e4', nom: 'EPP Agbo Ahounou', code: 'AGB01'),
  ];
  const classes = [
    ClasseConnue(id: 'c1', etablissementId: 'e1', libelle: 'CM2 A'),
    ClasseConnue(id: 'c2', etablissementId: 'e1', libelle: 'CM2-B'),
    ClasseConnue(id: 'c3', etablissementId: 'e3', libelle: '6ème 3'),
    ClasseConnue(id: 'c4', etablissementId: 'e4', libelle: 'CP1'),
  ];

  test('libellés de classe comparables', () {
    expect(cleClasse('CM2 A'), cleClasse('cm2-a'));
    expect(cleClasse('CM2A'), 'CM2A');
    expect(cleClasse('6ème 3'), '6EME3');
    expect(cleClasse('6e3'), '6EME3');
    expect(cleClasse('Classe de CE1 B'), 'CE1B');
    expect(cleClasse('Terminale D'), 'TLED');
  });

  test('classe lue dans un titre', () {
    expect(lireClasse('LISTE DES ÉLÈVES DE LA CLASSE DE CM2 A – ANNÉE 2026-2027')!.libelle, 'CM2 A');
    expect(lireClasse('Classe : 6ème 3')!.libelle, '6ème 3');
    expect(lireClasse('Liste CM2A EPP Kouassikro')!.libelle, 'CM2 A');
    expect(lireClasse('CP1 EPP AGBO')!.libelle, 'CP1');
    expect(lireClasse('GRANDE SECTION B')!.niveau, 'GS');
    expect(lireClasse('GS KOUASSIKRO (groupe scolaire)'), isNull);
    expect(lireClasse('Effectif : 45 élèves'), isNull);
  });

  test('établissement et classe existante reconnus dans le titre', () {
    final r = reconnaitreListe(
      titres: ['DRENA DIMBOKRO – IEPP KOUASSI-KOUASSIKRO', 'EPP KOUASSIKRO 1', 'LISTE NOMINATIVE – CLASSE : CM2 A'],
      etablissements: etabs,
      classes: classes,
    );
    expect(r.etablissement?.id, 'e1');
    expect(r.classe?.id, 'c1');
    expect(r.classeACreer, isFalse);
  });

  test('numéro de l\'école respecté ; classe à créer', () {
    final r = reconnaitreListe(titres: ['EPP KOUASSIKRO 2', 'CLASSE DE CE2'], etablissements: etabs, classes: classes);
    expect(r.etablissement?.id, 'e2');
    expect(r.classe, isNull);
    expect(r.classeLue?.libelle, 'CE2');
    expect(r.classeACreer, isTrue);
  });

  test('d\'après le nom du fichier seul ; code de l\'établissement', () {
    final r = reconnaitreListe(titres: const [], nomFichier: 'Liste_CM2B_EPP_Kouassikro1.xlsx', etablissements: etabs, classes: classes);
    expect(r.etablissement?.id, 'e1');
    expect(r.classe?.id, 'c2');
    expect(r.raisons.first, contains('nom du fichier'));
    final c = reconnaitreListe(titres: ['Code école : AGB01'], nomFichier: 'scan.jpg', etablissements: etabs, classes: classes);
    expect(c.etablissement?.id, 'e4');
  });

  test('accents et tirets : collège, 6e3', () {
    final r = reconnaitreListe(
        titres: ['COLLEGE MODERNE DE KOUASSI KOUASSIKRO', 'Liste de la 6e 3'], etablissements: etabs, classes: classes);
    expect(r.etablissement?.id, 'e3');
    expect(r.classe?.id, 'c3');
  });

  test('rien de reconnaissable, ou ambiguïté : aucun établissement proposé', () {
    final r = reconnaitreListe(titres: ['Liste des élèves'], etablissements: etabs, classes: classes);
    expect(r.etablissement, isNull);
    expect(r.classeLue, isNull);
    final a = reconnaitreListe(titres: ['EPP KOUASSIKRO'], etablissements: etabs, classes: classes);
    expect(a.etablissement, isNull, reason: 'Kouassikro 1 ou 2 ?');
  });

  test('titres d\'un tableau : lignes avant l\'en-tête', () {
    final t = tableauDepuisLignes([
      ['EPP KOUASSIKRO 1', '', ''],
      ['', 'CLASSE : CM2 A', ''],
      ['N°', 'NOM ET PRÉNOMS', 'DATE DE NAISSANCE'],
      ['1', 'KOUASSI Aya', '12/03/2015'],
    ], format: 'xlsx');
    expect(t.ligneEntete, 2);
    expect(t.titres, ['EPP KOUASSIKRO 1', 'CLASSE : CM2 A']);
  });
}
