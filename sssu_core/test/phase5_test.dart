import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

import 'outils/environnement.dart';

/// Phase 5 : inspection sanitaire, indicateurs, rapports PDF et Excel.
void main() {
  final genereLe = DateTime.utc(2026, 11, 25, 10);
  const entete = EnteteRapport(lignes: EnteteRapport.lignesParDefaut, nomMedecinChef: 'Dr KOFFI Marc');
  Droits droits(RoleCode r) => Droits(utilisateurId: 'u', role: r, permissions: matriceParDefaut[r]!);

  group('Formulaire d\'inspection', () {
    final criteres = [
      const CritereGrille(id: 'k1', rubrique: RubriqueInspection.toilettes, code: 't1', libelle: 'Toilettes propres', ordre: 2),
      const CritereGrille(id: 'k2', rubrique: RubriqueInspection.eauPotable, code: 'e1', libelle: 'Eau disponible', ordre: 1),
      const CritereGrille(id: 'k3', rubrique: RubriqueInspection.toilettes, code: 't2', libelle: 'Séparation F/G', ordre: 1),
      const CritereGrille(id: 'k4', rubrique: RubriqueInspection.cantine, code: 'c1', libelle: 'Cantine', ordre: 1),
    ];
    FormulaireInspection nouveau() => FormulaireInspection(
        etablissementId: 'E',
        anneeScolaireId: 'A',
        inspecteurId: 'I',
        dateInspection: DateTime.utc(2026, 11, 10),
        criteres: criteres);

    test('grille dans l\'ordre des rubriques puis des critères', () {
      final g = nouveau().parRubrique;
      expect(g.keys, [RubriqueInspection.eauPotable, RubriqueInspection.toilettes, RubriqueInspection.cantine]);
      expect(g[RubriqueInspection.toilettes]!.map((c) => c.id), ['k3', 'k1']);
    });

    test('contrôles : critères sans réponse et signature obligatoires', () {
      final f = nouveau();
      f.reponses['k1']!.resultat = ResultatInspection.conforme;
      final c = controlerInspection(f, aujourdhui: DateTime.utc(2026, 11, 10));
      expect(c.transmissible, isFalse);
      expect(c.erreurs, hasLength(2));
      expect(c.erreurs.first, contains('3 critères'));
    });

    test('calcul, données enregistrées et rechargement', () {
      final f = nouveau()
        ..signaturePng = [1, 2, 3]
        ..recommandations = 'Réparer les latrines';
      f.reponses['k1']!.resultat = ResultatInspection.conforme;
      f.reponses['k2']!
        ..resultat = ResultatInspection.partiel
        ..observation = 'Robinet fuyant';
      f.reponses['k3']!.resultat = ResultatInspection.nonConforme;
      f.reponses['k4']!.resultat = ResultatInspection.nonApplicable;
      final c = controlerInspection(f, aujourdhui: DateTime.utc(2026, 11, 10));
      expect(c.transmissible, isTrue);
      expect(c.avertissements, ['« Séparation F/G » : insuffisance sans observation.']);
      expect(f.insuffisances.map((c) => c.id), ['k2', 'k3']);
      final d = f.donneesInspection();
      // (1 + 0,5) / 3 = 50 %
      expect((d['nb_conformes'], d['nb_partiels'], d['nb_non_conformes'], d['nb_non_applicables']), (1, 1, 1, 1));
      expect((d['taux_conformite'], d['niveau']), (50.0, 'moyen'));
      expect(f.donneesReponse('k2'), containsPair('observation', 'Robinet fuyant'));

      final g = nouveau()..chargerInspection(d);
      expect(g.signaturePng, [1, 2, 3]);
      expect((g.recommandations, g.statut), ('Réparer les latrines', StatutInspection.ebauche));
      // Critère désactivé depuis, auquel l'inspection a répondu : réintégré.
      g.chargerReponse({'critere_id': 'k9', 'resultat': 'conforme'},
          critere: const CritereGrille(id: 'k9', rubrique: RubriqueInspection.securite, code: 's', libelle: 'Ancien'));
      expect(g.criteres.map((c) => c.id), contains('k9'));
    });

    test('seuils lus dans les paramètres, incohérents ignorés', () {
      final s = SeuilsConformite.depuisParametres({'seuil_conformite_satisfaisant': '90', 'seuil_conformite_moyen': '60,5'});
      expect((s.satisfaisant, s.moyen), (90, 60.5));
      final x = SeuilsConformite.depuisParametres({'seuil_conformite_satisfaisant': '40', 'seuil_conformite_moyen': '60'});
      expect((x.satisfaisant, x.moyen), (80, 50));
    });
  });

  group('Indicateurs', () {
    final jeu = jeuDeTest();

    test('couverture générale, par sexe, par établissement', () {
      final s = calculerStatistiques(jeu);
      final g = s.generale;
      expect((g.effectif, g.garcons, g.filles), (6, 3, 3), reason: 'élève sorti et inscription supprimée exclus');
      expect((g.examines, g.garconsExamines, g.fillesExamines), (3, 2, 1),
          reason: 'ébauche et visite de l\'année précédente ne comptent pas');
      expect(g.tauxCouverture, 50.0);
      expect((s.nbEtablissements, s.nbClasses, s.nbVisites), (2, 3, 4));
      expect([for (final e in s.parEtablissement) (e.libelle, e.effectif, e.examines)],
          [('École A', 4, 2), ('École B', 2, 1)]);
      expect(s.parClasse.first.libelle, 'École A – CE1');
      expect(s.conclusions[ConclusionVisite.reference], 1);
      expect(s.conclusions[ConclusionVisite.suivi], 1);
      expect(s.conclusions[ConclusionVisite.sansAnomalie], 1);
    });

    test('pathologies : cas, sexe, tranches d\'âge, prévalence', () {
      final s = calculerStatistiques(jeu);
      final p1 = s.pathologies.firstWhere((p) => p.id == 'P1');
      expect((p1.cas, p1.garcons, p1.filles, p1.prevalence), (2, 1, 1, 66.7));
      expect(p1.parTranche, {TrancheAge.de5a9: 1, TrancheAge.de10a14: 1});
      expect(p1.parEtablissement, {'E1': 1, 'E2': 1});
      final p2 = s.pathologies.firstWhere((p) => p.id == 'P2');
      expect((p2.cas, p2.prevalence), (1, 33.3));
      expect(s.pathologies.map((p) => p.id), ['P1', 'P2', 'P3'], reason: 'ordre de la liste officielle, sans cas compris');
      expect(s.elevesAvecPathologie, 2);
    });

    test('filtres : sexe, classe, période', () {
      final f = calculerStatistiques(jeu, const FiltreStatistiques(sexe: Sexe.feminin)).generale;
      expect((f.effectif, f.examines), (3, 1));
      final c = calculerStatistiques(jeu, const FiltreStatistiques(classeId: 'C1'));
      expect((c.generale.effectif, c.generale.examines, c.generale.tauxCouverture, c.nbEtablissements), (2, 2, 100.0, 1));
      final p = calculerStatistiques(jeu, FiltreStatistiques(du: DateTime.utc(2026, 11, 1)));
      expect((p.generale.examines, p.nbVisites), (2, 2));
      expect(p.pathologies.firstWhere((x) => x.id == 'P1').cas, 1, reason: 'dépistage d\'octobre hors période');
    });

    test('évolution mensuelle et couverture cumulée', () {
      final e = calculerStatistiques(jeu).evolution;
      expect([for (final x in e) (x.mois, x.visites, x.nouveauxExamines, x.couvertureCumulee)], [
        ('2026-09', 0, 0, 0.0),
        ('2026-10', 2, 2, 33.3),
        ('2026-11', 2, 1, 50.0),
      ]);
    });

    test('inspections : dernière par établissement, ébauches exclues, insuffisances', () {
      final x = calculerStatistiques(jeu).inspections;
      expect((x.etablissements, x.inspectes, x.satisfaisants, x.moyens, x.insuffisants), (2, 2, 1, 0, 1));
      expect(x.tauxMoyen, 62.5);
      expect(x.dernieres['E1']!.id, 'I2');
      expect([for (final i in x.principalesInsuffisances) (i.libelle, i.nonConformes, i.partiels)],
          [('Savon disponible', 1, 0), ('Latrines propres', 0, 1)]);
    });

    test('listes nominatives : non examinés, référés et suivis', () {
      expect(listeEleves(jeu, const FiltreStatistiques(), examines: false).map((l) => l.eleve.id), ['e3', 'e4', 'e6']);
      final suivis = listeSuivis(jeu, const FiltreStatistiques());
      expect(suivis.map((l) => (l.eleve.id, l.derniereVisite!.conclusion)),
          [('e2', ConclusionVisite.reference), ('e5', ConclusionVisite.suivi)]);
      expect(suivis.first.derniereVisite!.structureReference, 'CHR de Dimbokro');
    });

    test('tranches d\'âge', () {
      expect(TrancheAge.pour(DateTime.utc(2022, 1, 2), DateTime.utc(2026, 12, 31)), TrancheAge.de0a4);
      expect(TrancheAge.pour(DateTime.utc(2021, 1, 1), DateTime.utc(2026, 12, 31)), TrancheAge.de5a9);
      expect(TrancheAge.pour(DateTime.utc(2016, 11, 11), DateTime.utc(2026, 11, 10)), TrancheAge.de5a9);
      expect(TrancheAge.pour(DateTime.utc(2012, 1, 1), DateTime.utc(2026, 1, 1)), TrancheAge.de10a14);
      expect(TrancheAge.pour(DateTime.utc(2001, 1, 1), DateTime.utc(2026, 1, 1)), TrancheAge.de25a49);
      expect(TrancheAge.pour(DateTime.utc(1977, 1, 2), DateTime.utc(2026, 1, 1)), TrancheAge.de25a49);
      expect(TrancheAge.pour(DateTime.utc(1976, 1, 1), DateTime.utc(2026, 1, 1)), TrancheAge.plus50);
      expect(TrancheAge.pour(null, DateTime.utc(2026)), TrancheAge.inconnu);
      expect(TrancheAge.values.map((t) => t.libelle),
          ['0–4 ans', '5–9 ans', '10–14 ans', '15–19 ans', '20–24 ans', '25–49 ans', '50 ans et plus', 'Âge inconnu']);
    });

    test('élèves par tranche d\'âge et par sexe (âge à une même date)', () {
      final s = calculerStatistiques(jeu, FiltreStatistiques(dateAge: DateTime.utc(2026, 11, 25)));
      expect(s.dateAge, DateTime.utc(2026, 11, 25));
      expect([for (final l in s.parTrancheAge) (l.tranche, l.garcons, l.filles, l.garconsExamines, l.fillesExamines)], [
        (TrancheAge.de0a4, 0, 0, 0, 0),
        (TrancheAge.de5a9, 1, 2, 1, 1), // e1 (7 ans, examiné) ; e2 (8 ans, examinée), e3 (9 ans)
        (TrancheAge.de10a14, 2, 0, 1, 0), // e4 (10 ans), e5 (14 ans, examiné)
        (TrancheAge.de15a19, 0, 0, 0, 0),
        (TrancheAge.de20a24, 0, 0, 0, 0),
        (TrancheAge.de25a49, 0, 0, 0, 0),
        (TrancheAge.plus50, 0, 0, 0, 0),
        (TrancheAge.inconnu, 0, 1, 0, 0),
      ]);
      final total = s.parTrancheAge.fold<int>(0, (t, l) => t + l.effectif);
      expect(total, s.generale.effectif);
      // Date hors de l'année : ramenée dans la période.
      expect(calculerStatistiques(jeu, FiltreStatistiques(dateAge: DateTime.utc(2030))).dateAge, DateTime.utc(2027, 7, 31));
    });
  });

  group('Rapports', () {
    final jeu = jeuDeTest();
    final polices = PolicesRapport(
      normale: File('../sssu_windows/assets/polices/DejaVuSans.ttf').readAsBytesSync(),
      grasse: File('../sssu_windows/assets/polices/DejaVuSans-Bold.ttf').readAsBytesSync(),
    );

    test('droits : listes nominatives refusées à l\'administrateur et à l\'agent', () {
      for (final r in [RoleCode.admin, RoleCode.agent]) {
        expect(
            () => rapportListeEleves(jeu, const FiltreStatistiques(),
                examines: true, entete: entete, acteur: droits(r), genereLe: genereLe),
            throwsA(isA<RapportRefuse>()));
      }
      // L'administrateur édite les rapports statistiques (agrégés).
      rapportStatistique(jeu, const FiltreStatistiques(),
          portee: PorteeRapport.annuel, entete: entete, acteur: droits(RoleCode.admin), genereLe: genereLe);
      expect(
          () => rapportStatistique(jeu, const FiltreStatistiques(),
              portee: PorteeRapport.etablissement, entete: entete, acteur: droits(RoleCode.medecinChef), genereLe: genereLe),
          throwsA(isA<RapportRefuse>()),
          reason: 'établissement à choisir');
    });

    test('rapport annuel en PDF (accents, tirets) et en Excel (nombres exploitables)', () async {
      final d = rapportStatistique(jeu, const FiltreStatistiques(),
          portee: PorteeRapport.annuel, entete: entete, acteur: droits(RoleCode.medecinChef), genereLe: genereLe);
      final pdf = await rendrePdf(d, polices);
      expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
      expect(pdf.length, greaterThan(5000));

      final xlsx = Excel.decodeBytes(rendreExcel(d));
      final lignes = xlsx.tables['Rapport']!.rows;
      String? texte(int l, int c) => lignes[l].length > c ? lignes[l][c]?.value?.toString() : null;
      expect(texte(0, 0), 'MINISTÈRE EN CHARGE DE LA SANTÉ');
      final ligneEtab = lignes.indexWhere((l) => l.isNotEmpty && l[0]?.value?.toString() == 'École A');
      expect(ligneEtab, greaterThan(0));
      expect(lignes[ligneEtab][1]!.value, isA<IntCellValue>());
      expect((lignes[ligneEtab][1]!.value! as IntCellValue).value, 4);
      expect(nomFichierRapport(d, 'pdf'), 'rapport_annuel_des_visites_medicales_scolaires_2026-11-25.pdf');
    });

    test('rapport des pathologies, listes et suivis : rendus sans erreur', () async {
      final chef = droits(RoleCode.medecinChef);
      final docs = [
        rapportPathologies(jeu, const FiltreStatistiques(), entete: entete, acteur: chef, genereLe: genereLe),
        rapportListeEleves(jeu, const FiltreStatistiques(), examines: false, entete: entete, acteur: chef, genereLe: genereLe),
        rapportSuivis(jeu, const FiltreStatistiques(), entete: entete, acteur: chef, genereLe: genereLe),
        rapportStatistique(jeu, const FiltreStatistiques(classeId: 'C1'),
            portee: PorteeRapport.classe, entete: entete, acteur: chef, genereLe: genereLe),
        rapportHistoriqueInspections(jeu, entete: entete, acteur: chef, genereLe: genereLe),
      ];
      for (final d in docs) {
        expect(ascii.decode((await rendrePdf(d, polices)).sublist(0, 5)), '%PDF-', reason: d.titre);
        expect(rendreExcel(d), isNotEmpty);
      }
      expect(docs[1].confidentiel, isTrue);
      final tableau = docs[2].blocs.whereType<BlocTableau>().first;
      expect(tableau.lignes.single[1], 'KOUASSI Aya');
    });

    test('en-tête lu dans les paramètres, par défaut si vide', () {
      final e = EnteteRapport.depuisParametres({'entete_ligne_1': 'MINISTÈRE', 'entete_ligne_2': '  ', 'nom_medecin_chef': ''});
      expect(e.lignes, ['MINISTÈRE']);
      expect(e.nomMedecinChef, isNull);
      expect(EnteteRapport.depuisParametres({}).lignes, EnteteRapport.lignesParDefaut);
    });
  });

  group('Poste central : grille, paramètres, fiches', () {
    late Environnement env;
    late Droits chef;
    late ServiceGestion gestion;
    setUp(() async {
      env = await Environnement.creer();
      chef = await env.droits(env.chef);
      gestion = ServiceGestion(depot: env.depot, horloge: env.horloge);
    });

    test('critères : création (code unique), doublon refusé, désactivation', () async {
      final a = await gestion.creerCritere(chef, rubrique: RubriqueInspection.infirmerie, libelle: 'Trousse de secours complète');
      final b = await gestion.creerCritere(chef, rubrique: RubriqueInspection.infirmerie, libelle: 'Trousse : de secours, complète !');
      expect(a.donnees['code'], 'infirmerie_trousse_de_secours_complete');
      expect(b.donnees['code'], 'infirmerie_trousse_de_secours_complete_2');
      expect(b.donnees['ordre'], (a.donnees['ordre']! as int) + 1);
      await expectLater(gestion.creerCritere(chef, rubrique: RubriqueInspection.infirmerie, libelle: 'trousse de secours complète'),
          throwsA(isA<ErreurGestion>()));
      await expectLater(gestion.creerCritere(await env.droits(env.agent1), rubrique: RubriqueInspection.infirmerie, libelle: 'X'),
          throwsA(isA<ErreurGestion>()));
      final c = await gestion.activerCritere(chef, a.id, actif: false);
      expect(c.donnees['actif'], isFalse);
      // Diffusé aux téléphones.
      final tel = (await env.appairer('Tel', [env.etabA])).appareilId;
      final r = await env.sync.preparerReception(tel, 0, limite: 10000);
      expect(r.changements.any((x) => x.enregistrement.id == a.id && x.enregistrement.donnees['actif'] == false), isTrue);
    });

    test('paramètres : en-tête, seuils contrôlés, clé inconnue refusée', () async {
      await gestion.definirParametres(chef, {'entete_ligne_1': 'MINISTÈRE DE LA SANTÉ', 'nom_medecin_chef': 'Dr X'});
      await gestion.definirParametres(chef, {'nom_medecin_chef': 'Dr Y'});
      final p = await gestion.parametres();
      expect((p['entete_ligne_1'], p['nom_medecin_chef']), ('MINISTÈRE DE LA SANTÉ', 'Dr Y'));
      await expectLater(gestion.definirParametres(chef, {'seuil_conformite_satisfaisant': '120'}), throwsA(isA<ErreurGestion>()));
      await expectLater(gestion.definirParametres(chef, {'seuil_conformite_satisfaisant': '70', 'seuil_conformite_moyen': '75'}),
          throwsA(isA<ErreurGestion>()));
      await expectLater(gestion.definirParametres(chef, {'cle_inconnue': '1'}), throwsA(isA<ErreurGestion>()));
      await gestion.definirParametres(chef, {'nom_medecin_chef': ''});
      expect((await gestion.parametres())['nom_medecin_chef'], isNull);
    });

    test('fiche de visite et rapport d\'inspection lus dans le dépôt du poste', () async {
      final m = env.horloge.maintenant();
      Enregistrement n(String t, Map<String, Object?> d) => Enregistrement(
          table: t, id: nouvelId(), version: 1, versionBase: 1, createdAt: m, updatedAt: m, etablissementId: env.etabA, donnees: d);
      final patho = (await env.depot.transaction((tx) => tx.chercher('pathologie', {}))).firstOrNull;
      final v = n('visite', {
        'eleve_id': env.eleveA,
        'agent_id': env.agent1.id,
        'date_visite': '2026-11-10',
        'statut': 'synchronise',
        'poids_kg': 25.5,
        'conclusion': 'reference',
        'diagnostic': 'Carie',
        'structure_reference': 'CSU',
      });
      final k = n('critere_inspection', {'rubrique': 'eau_potable', 'code': 'zz', 'libelle': 'Eau', 'ordre': 1, 'actif': true});
      final i = n('inspection', {
        'etablissement_id': env.etabA,
        'annee_scolaire_id': env.anneeId,
        'inspecteur_id': env.agent1.id,
        'date_inspection': '2026-11-10',
        'signature': base64.encode([137, 80, 78, 71]),
        'nb_conformes': 0,
        'nb_partiels': 0,
        'nb_non_conformes': 1,
        'nb_non_applicables': 0,
        'taux_conformite': 0.0,
        'niveau': 'insuffisant',
        'statut': 'enregistre',
      });
      final r = n('inspection_reponse', {'inspection_id': i.id, 'critere_id': k.id, 'resultat': 'non_conforme'});
      await env.depot.transaction((tx) async {
        for (final e in [v, k, i, r]) {
          await tx.ecrire(e);
        }
        await tx.ecrire(n('examen_appareil', {'visite_id': v.id, 'appareil': 'bucco_dentaire', 'resultat': 'anormal'}));
        if (patho != null) await tx.ecrire(n('visite_pathologie', {'visite_id': v.id, 'pathologie_id': patho.id}));
      });
      final fv = await env.depot.transaction((tx) => FicheVisite.charger(tx, v.id));
      expect((fv.agent, fv.examens.length), ('AGENT1', 1));
      final d = ficheVisite(fv, entete: entete, acteur: droits(RoleCode.medecin), genereLe: genereLe);
      final champs = d.blocs.whereType<BlocChamps>().expand((b) => b.champs).toList();
      expect(champs, contains(('Structure de référence', 'CSU')));
      expect(champs, contains(('Poids', '25,5 kg')));
      expect(
          () => ficheVisite(fv,
              entete: entete, acteur: droits(RoleCode.infirmier), genereLe: genereLe, photos: [const PhotoRapport([1], 'x')]),
          throwsA(isA<RapportRefuse>()));

      final fi = await env.depot.transaction((tx) => FicheInspection.charger(tx, i.id));
      expect(fi.reponses.single.resultat, ResultatInspection.nonConforme);
      final ri = rapportInspection(fi, entete: entete, acteur: droits(RoleCode.agent), genereLe: genereLe);
      expect(ri.blocs.whereType<BlocSignature>().single.image, [137, 80, 78, 71]);
      expect(ri.blocs.whereType<BlocTableau>().single.titre, startsWith('Eau potable'));
    });
  });
}

/// Jeu de test des indicateurs (voir le détail attendu dans chaque test).
JeuStatistiques jeuDeTest() {
  Map<String, Object?> l(Map<String, Object?> m) => {'deleted_at': null, ...m};
  return JeuStatistiques.depuisLignes(
    annee: AnneeStat('A', '2026-2027', DateTime.utc(2026, 9, 1), DateTime.utc(2027, 7, 31)),
    identite: true,
    etablissements: [l({'id': 'E2', 'nom': 'École B'}), l({'id': 'E1', 'nom': 'École A'})],
    classes: [
      l({'id': 'C1', 'libelle': 'CP1', 'niveau': 'CP1', 'etablissement_id': 'E1', 'annee_scolaire_id': 'A'}),
      l({'id': 'C2', 'libelle': 'CE1', 'niveau': 'CE1', 'etablissement_id': 'E1', 'annee_scolaire_id': 'A'}),
      l({'id': 'C3', 'libelle': '6e A', 'niveau': '6e', 'etablissement_id': 'E2', 'annee_scolaire_id': 'A'}),
      l({'id': 'C0', 'libelle': 'Ancienne', 'etablissement_id': 'E1', 'annee_scolaire_id': 'autre'}),
    ],
    inscriptions: [
      for (final (e, c) in [('e1', 'C1'), ('e2', 'C1'), ('e3', 'C2'), ('e4', 'C2'), ('e5', 'C3'), ('e6', 'C3')])
        l({'eleve_id': e, 'classe_id': c, 'statut': 'inscrit'}),
      l({'eleve_id': 'e7', 'classe_id': 'C3', 'statut': 'sorti'}),
      {'eleve_id': 'e8', 'classe_id': 'C3', 'statut': 'inscrit', 'deleted_at': '2026-10-01T00:00:00Z'},
      l({'eleve_id': 'e1', 'classe_id': 'C0', 'statut': 'inscrit'}),
    ],
    eleves: [
      l({'id': 'e1', 'nom': 'BAMBA', 'prenoms': 'Ali', 'sexe': 'M', 'date_naissance': '2019-03-01'}),
      l({'id': 'e2', 'nom': 'KOUASSI', 'prenoms': 'Aya', 'sexe': 'F', 'date_naissance': '2018-05-01', 'telephone_contact': '07'}),
      l({'id': 'e3', 'nom': 'KONE', 'prenoms': 'Awa', 'sexe': 'F', 'date_naissance': '2017-01-01'}),
      l({'id': 'e4', 'nom': 'YAO', 'prenoms': 'Koffi', 'sexe': 'M', 'date_naissance': '2016-06-01'}),
      l({'id': 'e5', 'nom': 'TRAORE', 'prenoms': 'Issa', 'sexe': 'M', 'date_naissance': DateTime.utc(2012, 1, 1)}),
      l({'id': 'e6', 'nom': 'ZADI', 'prenoms': 'Marie', 'sexe': 'F', 'date_naissance': null}),
      l({'id': 'e7', 'nom': 'SORTI', 'prenoms': 'X', 'sexe': 'M'}),
      l({'id': 'e8', 'nom': 'SUPPRIME', 'prenoms': 'Y', 'sexe': 'F'}),
    ],
    visites: [
      l({'id': 'v1', 'eleve_id': 'e1', 'date_visite': '2026-10-05', 'statut': 'synchronise', 'conclusion': 'sans_anomalie'}),
      l({'id': 'v2', 'eleve_id': 'e2', 'date_visite': '2026-10-05', 'statut': 'synchronise', 'conclusion': 'anomalie'}),
      l({
        'id': 'v3',
        'eleve_id': 'e2',
        'date_visite': '2026-11-12',
        'statut': 'valide',
        'conclusion': 'reference',
        'diagnostic': 'Carie',
        'structure_reference': 'CHR de Dimbokro'
      }),
      l({'id': 'v4', 'eleve_id': 'e3', 'date_visite': '2026-10-06', 'statut': 'ebauche', 'conclusion': 'anomalie'}),
      l({'id': 'v5', 'eleve_id': 'e4', 'date_visite': '2026-06-01', 'statut': 'valide', 'conclusion': 'anomalie'}),
      l({'id': 'v6', 'eleve_id': 'e5', 'date_visite': DateTime.utc(2026, 11, 20), 'statut': 'valide', 'conclusion': 'suivi'}),
      {'id': 'v7', 'eleve_id': 'e6', 'date_visite': '2026-10-05', 'statut': 'valide', 'deleted_at': '2026-10-06'},
    ],
    visitePathologies: [
      l({'visite_id': 'v2', 'pathologie_id': 'P1'}),
      l({'visite_id': 'v3', 'pathologie_id': 'P2'}),
      l({'visite_id': 'v6', 'pathologie_id': 'P1'}),
      l({'visite_id': 'v4', 'pathologie_id': 'P3'}),
    ],
    pathologies: [
      l({'id': 'P2', 'libelle': 'Carie dentaire', 'ordre': 2}),
      l({'id': 'P1', 'libelle': 'Anémie', 'ordre': 1}),
      l({'id': 'P3', 'libelle': 'Gale', 'ordre': 3}),
    ],
    criteres: [l({'id': 'K1', 'libelle': 'Latrines propres'}), l({'id': 'K2', 'libelle': 'Savon disponible'})],
    inspections: [
      l({'id': 'I1', 'etablissement_id': 'E1', 'date_inspection': '2026-10-10', 'statut': 'enregistre', 'taux_conformite': 50.0, 'niveau': 'moyen'}),
      l({'id': 'I2', 'etablissement_id': 'E1', 'date_inspection': '2026-11-15', 'statut': 'enregistre', 'taux_conformite': 25.0, 'niveau': 'insuffisant', 'nb_partiels': 1, 'nb_non_conformes': 1}),
      l({'id': 'I3', 'etablissement_id': 'E2', 'date_inspection': '2026-10-20', 'statut': 'ebauche', 'taux_conformite': 0.0, 'niveau': 'insuffisant'}),
      l({'id': 'I4', 'etablissement_id': 'E2', 'date_inspection': '2026-10-21', 'statut': 'enregistre', 'taux_conformite': 100, 'niveau': 'satisfaisant', 'nb_conformes': '1'}),
    ],
    reponsesInspection: [
      l({'inspection_id': 'I1', 'critere_id': 'K1', 'resultat': 'non_conforme'}),
      l({'inspection_id': 'I1', 'critere_id': 'K2', 'resultat': 'conforme'}),
      l({'inspection_id': 'I2', 'critere_id': 'K1', 'resultat': 'partiel'}),
      l({'inspection_id': 'I2', 'critere_id': 'K2', 'resultat': 'non_conforme'}),
      l({'inspection_id': 'I3', 'critere_id': 'K1', 'resultat': 'non_conforme'}),
      l({'inspection_id': 'I4', 'critere_id': 'K1', 'resultat': 'conforme'}),
    ],
  );
}
