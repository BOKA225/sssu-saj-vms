import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// Grille nationale : critères repris du document, scores, critères ★,
/// classement, non-applicables automatiques, données de la grille.
void main() {
  List<CritereGrille> criteres() => [
        for (final d in criteresGrille)
          CritereGrille(id: d.id, rubrique: d.rubrique, code: d.code, libelle: d.libelle, ordre: d.ordre)
      ];

  FormulaireInspection formulaire() => FormulaireInspection(
        etablissementId: nouvelId(),
        anneeScolaireId: nouvelId(),
        inspecteurId: nouvelId(),
        dateInspection: DateTime.utc(2026, 11, 13),
        criteres: criteres(),
      );

  void coter(FormulaireInspection f, ResultatInspection r, {Map<String, ResultatInspection> sauf = const {}}) {
    for (final c in f.criteres) {
      f.reponses[c.id]!.resultat = sauf[c.code] ?? r;
    }
  }

  test('118 critères, 7 critiques, effectifs par section du récapitulatif', () {
    expect(criteresGrille, hasLength(118));
    expect([for (final c in criteresGrille) if (c.critique) c.code], ['B1', 'B2', 'C1', 'C2', 'D1', 'I4', 'I5']);
    final parSection = <String, int>{};
    for (final c in criteresGrille) {
      parSection[c.rubrique.lettre!] = (parSection[c.rubrique.lettre!] ?? 0) + 1;
    }
    expect(parSection, {'B': 12, 'C': 22, 'D': 12, 'E': 9, 'F': 11, 'G': 13, 'H': 15, 'I': 12, 'J': 12});
    expect(criteresGrille.map((c) => c.id).toSet(), hasLength(118));
    expect(criteresGrille.map((c) => c.code).toSet(), hasLength(118));
    for (final c in criteresGrille) {
      expect(c.id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(c.code, startsWith(c.rubrique.lettre!));
    }
    expect(definitionParCode('C11')!.groupe, 'État des installations');
    expect(definitionParCode('H12')!.groupe, 'Vente d\'aliments dans l\'enceinte et aux abords');
    expect(definitionParCode('B1')!.libelle, 'Au moins un point d\'eau de boisson existe dans l\'enceinte de l\'établissement');
    expect(RubriqueInspection.actuelles, hasLength(9));
  });

  test('scores : NA exclus, domaine et global ; barème 80 / 60 / 40', () {
    final f = formulaire();
    coter(f, ResultatInspection.conforme);
    var ev = f.evaluation();
    expect(ev.scoreGlobal, 100);
    expect(ev.classement, ClassementGrille.satisfaisant);

    // Section E non applicable, 3 NC en B (non critiques).
    coter(f, ResultatInspection.conforme, sauf: {
      for (final c in criteresGrille)
        if (c.rubrique == RubriqueInspection.hygieneMenstruelle) c.code: ResultatInspection.nonApplicable,
      'B3': ResultatInspection.nonConforme,
      'B4': ResultatInspection.nonConforme,
      'B5': ResultatInspection.nonConforme,
    });
    ev = f.evaluation();
    final b = ev.domaines.firstWhere((d) => d.rubrique == RubriqueInspection.eauBoisson);
    expect((b.points, b.applicables, b.score), (9.0, 12, 75.0));
    final e = ev.domaines.firstWhere((d) => d.rubrique == RubriqueInspection.hygieneMenstruelle);
    expect(e.score, isNull);
    expect(ev.applicables, 109);
    expect(ev.scoreGlobal, (106 / 109 * 1000).roundToDouble() / 10);

    expect(ClassementGrille.depuisScore(80), ClassementGrille.satisfaisant);
    expect(ClassementGrille.depuisScore(79.9), ClassementGrille.acceptable);
    expect(ClassementGrille.depuisScore(60), ClassementGrille.acceptable);
    expect(ClassementGrille.depuisScore(59.9), ClassementGrille.insuffisant);
    expect(ClassementGrille.depuisScore(40), ClassementGrille.insuffisant);
    expect(ClassementGrille.depuisScore(39.9), ClassementGrille.critique);
  });

  test('un critère ★ non conforme plafonne le classement à « Insuffisant »', () {
    final f = formulaire();
    coter(f, ResultatInspection.conforme, sauf: {'I5': ResultatInspection.nonConforme});
    final ev = f.evaluation();
    expect(ev.scoreGlobal, greaterThan(99));
    expect(ev.classement, ClassementGrille.insuffisant);
    expect(ev.plafonne, isTrue);
    expect(ev.critiquesNonConformes.single.code, 'I5');
    final d = f.donneesInspection();
    expect(d['niveau'], 'insuffisant');
    expect(d['taux_conformite'], ev.scoreGlobal);

    // Score critique : le plafond ne remonte pas le classement.
    coter(f, ResultatInspection.nonConforme);
    expect(f.evaluation().classement, ClassementGrille.critique);
    expect(f.evaluation().plafonne, isFalse);
    expect(classementEnregistre('insuffisant', 0), ClassementGrille.critique);
    expect(classementEnregistre('moyen', 70), ClassementGrille.acceptable);
  });

  test('non applicables automatiques d\'après la structure, motif en observation', () {
    final f = formulaire();
    f.grille
      ..cantine = false
      ..ordreEnseignement = 'prescolaire'
      ..electricite = 'aucune';
    f.reponses[f.criteres.firstWhere((c) => c.code == 'H2').id]!.resultat = ResultatInspection.conforme;
    final n = f.appliquerNonApplicablesAutomatiques();
    expect(n, 9 + 9 + 1); // H1, H3–H10 ; E1–E9 ; G8 (H2 déjà coté)
    String? obs(String code) => f.reponses[f.criteres.firstWhere((c) => c.code == code).id]!.observation;
    ResultatInspection? res(String code) => f.reponses[f.criteres.firstWhere((c) => c.code == code).id]!.resultat;
    expect(res('H1'), ResultatInspection.nonApplicable);
    expect(obs('H1'), 'Pas de cantine');
    expect(res('H2'), ResultatInspection.conforme);
    expect(res('H11'), isNull);
    expect(obs('E4'), 'Préscolaire');
    expect(res('G8'), ResultatInspection.nonApplicable);
  });

  test('données de la grille : JSON enregistré dans l\'inspection et relu', () {
    final f = formulaire();
    f.grille
      ..drenaIepp = 'IEPP Kouassi-Kouassikro'
      ..typeVisite = 'inopinee'
      ..dateDerniereInspection = DateTime.utc(2025, 3, 4)
      ..cantine = true
      ..sourceEau = 'forage'
      ..pointsForts = 'Cour propre'
      ..dateContreVisite = DateTime.utc(2026, 12, 13);
    f.grille.effectifs['eleves'] = Paire(210, 190);
    f.grille.equipements['salles'] = Paire(8);
    f.grille.equipements['cabines_filles'] = Paire(6, 4);
    f.grille.niveauxService[DomaineService.eau] = NiveauService.limite;
    f.grille.problemes.add(ProblemeConstate(probleme: 'Fosse pleine', criteres: 'C13', mesure: 'Vidange', delai: '1 mois'));
    f.grille.problemes.add(ProblemeConstate()); // vide : non enregistré
    final d = f.donneesInspection();
    final j = jsonDecode(d['grille']! as String) as Map<String, Object?>;
    expect((j['problemes']! as List).length, 1);

    final relu = formulaire()..chargerInspection(d);
    final g = relu.grille;
    expect(g.drenaIepp, 'IEPP Kouassi-Kouassikro');
    expect(g.typeVisite, 'inopinee');
    expect(g.dateDerniereInspection, DateTime.utc(2025, 3, 4));
    expect(g.cantine, isTrue);
    expect(g.eleves, 400);
    expect(g.filles, 190);
    expect(g.equipements['cabines_filles']!.b, 4);
    expect(g.niveauxService[DomaineService.eau], NiveauService.limite);
    expect(g.problemes.single.criteres, 'C13');
    expect(g.dateContreVisite, DateTime.utc(2026, 12, 13));

    final ratios = {for (final r in g.ratios) r.libelle: r};
    expect(ratios['Élèves par classe']!.valeur, 50);
    expect(ratios['Filles par cabine fonctionnelle']!.valeur, 47.5);
  });

  test('niveaux de service proposés (eau, assainissement, hygiène des mains)', () {
    final f = formulaire();
    coter(f, ResultatInspection.conforme);
    final g = f.grille
      ..sourceEau = 'forage'
      ..typeLatrine = 'vip';
    expect(niveauServicePropose(DomaineService.eau, f.resultatsParCode, g), NiveauService.elementaire);
    expect(niveauServicePropose(DomaineService.assainissement, f.resultatsParCode, g), NiveauService.elementaire);
    expect(niveauServicePropose(DomaineService.hygiene, f.resultatsParCode, g), NiveauService.elementaire);
    final r = f.resultatsParCode
      ..['B3'] = ResultatInspection.nonConforme
      ..['C2'] = ResultatInspection.nonConforme;
    expect(niveauServicePropose(DomaineService.eau, r, g), NiveauService.limite);
    expect(niveauServicePropose(DomaineService.assainissement, r, g), NiveauService.limite);
    g.sourceEau = 'eau_surface';
    g.typeLatrine = 'fosse_sans_dalle';
    expect(niveauServicePropose(DomaineService.eau, r, g), NiveauService.absence);
    expect(niveauServicePropose(DomaineService.assainissement, r, g), NiveauService.absence);
    // Choix de l'inspecteur prioritaire.
    f.grille.niveauxService[DomaineService.eau] = NiveauService.elementaire;
    expect(f.niveauService(DomaineService.eau), NiveauService.elementaire);
  });

  test('contrôles : « partiel » refusé, NA à justifier, ★ NC et plan d\'action signalés', () {
    final f = formulaire()..signaturePng = [1, 2, 3];
    coter(f, ResultatInspection.conforme, sauf: {'B3': ResultatInspection.partiel});
    expect(controlerInspection(f, aujourdhui: DateTime.utc(2026, 11, 13)).erreurs.join(), contains('partiellement'));
    coter(f, ResultatInspection.conforme, sauf: {'D1': ResultatInspection.nonConforme, 'G8': ResultatInspection.nonApplicable});
    final c = controlerInspection(f, aujourdhui: DateTime.utc(2026, 11, 13));
    expect(c.transmissible, isTrue);
    final a = c.avertissements.join('\n');
    expect(a, contains('NA sans justification en observation : G8'));
    expect(a, contains('★ non conforme(s) : D1'));
    expect(a, contains('sans problème prioritaire'));
    expect(a, contains('contre-visite'));
  });

  test('ancienne grille : calcul inchangé, pas de données de grille', () {
    final ancien = CritereGrille(id: nouvelId(), rubrique: RubriqueInspection.eauPotable, code: 'eau_x', libelle: 'Eau');
    final f = FormulaireInspection(
      etablissementId: nouvelId(),
      anneeScolaireId: nouvelId(),
      inspecteurId: nouvelId(),
      dateInspection: DateTime.utc(2026, 1, 1),
      criteres: [ancien],
    );
    f.reponses[ancien.id]!.resultat = ResultatInspection.partiel;
    expect(f.grilleNationale, isFalse);
    final d = f.donneesInspection();
    expect(d['grille'], isNull);
    expect(d['taux_conformite'], 50);
  });

  test('grille préremplie depuis l\'établissement et les inscriptions', () {
    final g = DonneesGrille.preremplie(
      etablissement: {'type': 'primaire', 'statut': 'public', 'localite': 'Kouassikro', 'responsable': 'M. KOFFI', 'telephone': '0102'},
      garcons: 120,
      filles: 0,
      classes: 6,
    );
    expect(g.ordreEnseignement, 'primaire');
    expect(g.statut, 'public');
    expect(g.chefEtablissement, 'M. KOFFI, 0102');
    expect(g.frequentation, 'garcons');
    expect(g.salles, 6);
    expect(g.nonApplicablesAutomatiques.keys, containsAll(['E1', 'E9']));
  });

  test('rapport de la grille : PDF et Word (.docx) au format de la grille', () async {
    final f = formulaire()..signaturePng = null;
    coter(f, ResultatInspection.conforme, sauf: {
      'C2': ResultatInspection.nonConforme,
      'H1': ResultatInspection.nonApplicable,
      'G3': ResultatInspection.nonConforme,
    });
    f.grille
      ..drenaIepp = 'IEPP <Kouassikro> & environs'
      ..typeVisite = 'programmee'
      ..sourceEau = 'forage'
      ..chefEtablissement = 'M. KOFFI, 0102030405'
      ..pointsForts = 'Cour propre';
    f.grille.problemes.add(ProblemeConstate(probleme: 'Latrines mixtes', criteres: 'C2', mesure: 'Séparer et signaler'));
    final m = DateTime.utc(2026, 11, 13);
    final donnees = f.donneesInspection();
    final inspection = Enregistrement(
        table: 'inspection', id: nouvelId(), version: 1, versionBase: 1, createdAt: m, updatedAt: m, donnees: donnees);
    final fiche = FicheInspection(
      inspection: inspection,
      etablissement: 'EPP Kouassikro 1',
      annee: '2026-2027',
      inspecteur: 'AGENT Un',
      reponses: [
        for (final c in f.criteres)
          ReponseFiche(c, f.reponses[c.id]!.resultat!, f.reponses[c.id]!.observation.isEmpty ? null : f.reponses[c.id]!.observation,
              const [])
      ],
    );
    expect(fiche.nationale, isTrue);
    final doc = rapportInspection(fiche,
        entete: const EnteteRapport(lignes: EnteteRapport.lignesParDefaut),
        acteur: Droits(utilisateurId: 'u', role: RoleCode.medecinChef, permissions: matriceParDefaut[RoleCode.medecinChef]!),
        genereLe: m);
    expect(doc.titre, 'Grille d\'inspection sanitaire des établissements scolaires');
    final tableaux = doc.blocs.whereType<BlocTableau>().toList();
    final latrines = tableaux.firstWhere((t) => t.lignes.any((l) => l[0] == 'C1 ★'));
    expect(latrines.lignes.first[1], 'DISPONIBILITÉ ET SÉPARATION');
    final c2 = latrines.lignes.firstWhere((l) => l[0] == 'C2 ★');
    expect([c2[2], c2[3], c2[4]], ['', 'X', '']);
    final recap = tableaux.firstWhere((t) => t.entetes.first == 'Domaine' && t.totaux != null);
    expect(recap.lignes, hasLength(9));
    expect(recap.totaux![1], 118);
    expect(recap.totaux![3], 117);
    expect(doc.blocs.whereType<BlocParagraphe>().any((b) => b.texte.contains('☒ Insuffisant')), isTrue,
        reason: 'C2 ★ NC : classement plafonné');
    expect(doc.blocs.whereType<BlocSignatures>().single.signatures[1].nom, 'M. KOFFI');

    final polices = PolicesRapport(
      normale: File('../sssu_windows/assets/polices/DejaVuSans.ttf').readAsBytesSync(),
      grasse: File('../sssu_windows/assets/polices/DejaVuSans-Bold.ttf').readAsBytesSync(),
    );
    final pdf = await rendrePdf(doc, polices);
    expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');

    final docx = rendreWord(doc);
    expect(docx.sublist(0, 2), [0x50, 0x4B]); // archive ZIP
    final zip = ZipDecoder().decodeBytes(docx);
    String partie(String nom) => utf8.decode(zip.files.firstWhere((x) => x.name == nom).content as List<int>);
    final xml = partie('word/document.xml');
    expect(xml, contains('C2 ★'));
    expect(xml, contains('IEPP &lt;Kouassikro&gt; &amp; environs'));
    expect(xml, contains('Latrines mixtes'));
    expect('<w:tbl>'.allMatches(xml).length, '</w:tbl>'.allMatches(xml).length);
    expect('<w:tr>'.allMatches(xml).length, '</w:tr>'.allMatches(xml).length);
    expect('<w:p>'.allMatches(xml).length + '<w:p '.allMatches(xml).length, '</w:p>'.allMatches(xml).length);
    expect(partie('[Content_Types].xml'), contains('wordprocessingml.document.main+xml'));
    // Toutes les parties XML sont bien formées.
    for (final f in zip.files.where((f) => f.name.endsWith('.xml') || f.name.endsWith('.rels'))) {
      expect(() => XmlDocument.parse(partie(f.name)), returnsNormally, reason: f.name);
    }
    final arbre = XmlDocument.parse(xml);
    // Ordre des propriétés de cellule exigé par Word.
    for (final tcPr in arbre.findAllElements('w:tcPr')) {
      final noms = tcPr.childElements.map((e) => e.name.qualified).toList();
      final ordre = ['w:tcW', 'w:tcBorders', 'w:shd', 'w:tcMar'];
      final positions = [for (final n in noms) ordre.indexOf(n)];
      expect(positions, orderedEquals([...positions]..sort()), reason: noms.join(','));
    }
    expect(partie('word/footer1.xml'), contains('NUMPAGES'));
  });

  test('rendu Word : images PNG et JPEG dimensionnées, page à l\'italienne', () {
    // PNG 2×1 et en-tête JPEG minimal (SOF0 : 3×4).
    final png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 2, 0, 0, 0, 1,
      8, 6, 0, 0, 0];
    final jpeg = [0xFF, 0xD8, 0xFF, 0xC0, 0, 17, 8, 0, 4, 0, 3, 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1, 0xFF, 0xD9];
    expect(dimensionsImage(png), (2, 1));
    expect(dimensionsImage(jpeg), (3, 4));
    final d = DocumentRapport(
      titre: 'Essai',
      entete: EnteteRapport(lignes: const ['A'], logoPng: png),
      blocs: [BlocImage(jpeg, legende: 'Photo'), const BlocSautDePage(), const BlocSignature(fonction: 'Le Médecin-Chef')],
      genereLe: DateTime.utc(2026),
      paysage: true,
      confidentiel: true,
    );
    final zip = ZipDecoder().decodeBytes(rendreWord(d));
    final noms = zip.files.map((f) => f.name).toList();
    expect(noms, containsAll(['word/media/image1.png', 'word/media/image2.jpeg', 'word/_rels/document.xml.rels']));
    final xml = utf8.decode(zip.files.firstWhere((x) => x.name == 'word/document.xml').content as List<int>);
    expect(xml, contains('w:orient="landscape"'));
    expect(xml, contains('w:type="page"'));
    final pied = utf8.decode(zip.files.firstWhere((x) => x.name == 'word/footer1.xml').content as List<int>);
    expect(pied, contains('secret médical'));
  });
}
