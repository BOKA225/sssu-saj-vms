import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

import 'outils/environnement.dart';

Droits _droits(RoleCode r) => Droits(utilisateurId: 'u-${r.name}', role: r, permissions: matriceParDefaut[r]!);

void main() {
  test('effectifs saisis : contrôles, élèves visités par type de visite et par sexe', () {
    const s = EffectifSaisi('C', garcons: 10, filles: 12, visitesGarcons: 6, visitesFilles: 9, aptitudeGarcons: 4);
    expect((s.effectif, s.renseigne, s.vide), (22, true, false));
    expect((s.visites(TypeVisite.systematique), s.visites(TypeVisite.systematique, sexe: Sexe.feminin)), (15, 9));
    expect((s.visites(TypeVisite.aptitude), s.visites(TypeVisite.aptitude, sexe: Sexe.feminin)), (4, 0));
    expect(s.erreurs(), isEmpty);
    expect(EffectifSaisi.depuisDonnees(s.versDonnees()).versDonnees(), s.versDonnees());
    expect(EffectifSaisi.depuisDonnees({'classe_id': 'C', 'garcons': '7', 'filles': null}).garcons, 7);
    expect(const EffectifSaisi('C').vide, isTrue);
    expect(const EffectifSaisi('C', garcons: 5, visitesGarcons: 6).erreurs(classe: 'CM2'),
        ['CM2 : plus de garçons visités (6) que de garçons inscrits (5).']);
    expect(const EffectifSaisi('C', visitesFilles: 2).erreurs(), hasLength(2), reason: 'visités sans effectif');
    expect(const EffectifSaisi('C', filles: -1).erreurs(), isNotEmpty);
  });

  group('Statistiques avec des effectifs saisis', () {
    final annee = AnneeStat('A', '2026-2027', DateTime.utc(2026, 9, 1), DateTime.utc(2027, 7, 31));
    final jeu = JeuStatistiques.depuisLignes(
      annee: annee,
      etablissements: [
        {'id': 'E1', 'nom': 'EPP A'},
        {'id': 'E2', 'nom': 'Collège B'},
      ],
      classes: [
        {'id': 'C1', 'libelle': 'CM1', 'etablissement_id': 'E1', 'annee_scolaire_id': 'A'},
        {'id': 'C2', 'libelle': 'CM1', 'etablissement_id': 'E1', 'annee_scolaire_id': 'A'},
        {'id': 'C3', 'libelle': '6ème 1', 'etablissement_id': 'E2', 'annee_scolaire_id': 'A'},
        {'id': 'C4', 'libelle': '3ème 1', 'etablissement_id': 'E2', 'annee_scolaire_id': 'A'},
      ],
      inscriptions: [
        for (final (e, c) in [('e1', 'C1'), ('e2', 'C1'), ('e3', 'C3')]) {'eleve_id': e, 'classe_id': c, 'statut': 'inscrit'},
      ],
      eleves: [
        {'id': 'e1', 'sexe': 'M', 'date_naissance': '2016-01-01'},
        {'id': 'e2', 'sexe': 'F', 'date_naissance': '2016-02-02'},
        {'id': 'e3', 'sexe': 'F', 'date_naissance': '2014-03-03'},
      ],
      visites: [
        {'id': 'v1', 'eleve_id': 'e1', 'date_visite': '2026-10-05', 'statut': 'valide', 'conclusion': 'anomalie'},
        {'id': 'v3', 'eleve_id': 'e3', 'date_visite': '2026-11-05', 'statut': 'valide', 'conclusion': 'sans_anomalie'},
      ],
      visitePathologies: [
        {'visite_id': 'v1', 'pathologie_id': 'P1'},
      ],
      pathologies: [
        {'id': 'P1', 'libelle': 'Carie dentaire', 'ordre': 1},
      ],
      effectifsClasses: [
        {'classe_id': 'C2', 'garcons': 10, 'filles': 12, 'visites_garcons': 6, 'visites_filles': 9},
        // Classe avec une liste : la liste l'emporte.
        {'classe_id': 'C3', 'garcons': 50, 'filles': 50, 'visites_garcons': 50},
        {'classe_id': 'C4', 'garcons': 20, 'filles': 18, 'visites_garcons': 10, 'visites_filles': 10, 'aptitude_garcons': 15,
          'aptitude_filles': 12},
        // Classe inconnue de l'année : ignorée.
        {'classe_id': 'C9', 'garcons': 99},
      ],
    );

    test('visite systématique : effectif, examinés et couverture des listes et des saisies', () {
      final s = calculerStatistiques(jeu, FiltreStatistiques(dateAge: DateTime.utc(2026, 11, 18)));
      final g = s.generale;
      expect((g.effectif, g.garcons, g.filles, g.examines, g.garconsExamines, g.fillesExamines), (63, 31, 32, 37, 17, 20));
      expect((s.saisis.effectif, s.saisis.examines, s.nbClassesSaisies), (60, 35, 2));
      expect((s.effectifListes, s.examinesListes), (3, 2));
      expect({for (final c in s.parEtablissement) c.id: (c.effectif, c.examines)}, {'E1': (24, 16), 'E2': (39, 21)});
      expect({for (final c in s.parClasse) c.id: (c.effectif, c.examines)},
          {'C1': (2, 1), 'C2': (22, 15), 'C3': (1, 1), 'C4': (38, 20)});
      // Conclusions, pathologies, tranches d'âge, évolution : listes d'élèves seulement.
      expect(s.pathologies.single.prevalence, 50.0);
      expect(s.parTrancheAge.fold<int>(0, (t, l) => t + l.effectif), 3);
      expect(s.evolution.last.couvertureCumulee, 66.7);
      expect(s.conclusions[ConclusionVisite.anomalie], 1);
    });

    test('filtre de sexe, visite d\'aptitude, établissement', () {
      final f = calculerStatistiques(jeu, const FiltreStatistiques(sexe: Sexe.feminin)).generale;
      expect((f.effectif, f.garcons, f.examines), (32, 0, 20));
      final a = calculerStatistiques(jeu, const FiltreStatistiques(typeVisite: TypeVisite.aptitude));
      expect((a.generale.effectif, a.generale.examines, a.nbClassesSaisies), (38, 27, 1));
      final e1 = calculerStatistiques(jeu, const FiltreStatistiques(etablissementId: 'E1')).generale;
      expect((e1.effectif, e1.examines), (24, 16));
      final c3 = calculerStatistiques(jeu, const FiltreStatistiques(classeId: 'C3'));
      expect((c3.generale.effectif, c3.nbClassesSaisies), (1, 0));
    });

    test('rapport annuel : note sur les effectifs saisis, pathologies sur les listes', () {
      final d = rapportStatistique(jeu, const FiltreStatistiques(),
          portee: PorteeRapport.annuel,
          entete: const EnteteRapport(lignes: EnteteRapport.lignesParDefaut),
          acteur: _droits(RoleCode.admin),
          genereLe: DateTime.utc(2026, 11, 18));
      final textes = d.blocs.whereType<BlocParagraphe>().map((b) => b.texte).toList();
      expect(textes, contains(startsWith('Dont 60 élève(s) inscrit(s) et 35 visité(s) de 2 classe(s) sans liste')));
      expect(textes, contains(startsWith('1 élève(s) examiné(s) sur 2 présentent au moins une pathologie')));
    });
  });

  group('Gestion', () {
    late Environnement env;
    late ServiceGestion gestion;

    setUp(() async {
      env = await Environnement.creer();
      gestion = ServiceGestion(depot: env.depot, horloge: env.horloge, hacheur: HacheurMotDePasse(parametres: ParametresArgon2.tests));
    });

    test('effectifs saisis par l\'administrateur : création, modification, contrôles, droits', () async {
      final admin = _droits(RoleCode.admin);
      Future<List<Enregistrement>> lus() =>
          env.depot.transaction((tx) => tx.chercher('effectif_classe', {'classe_id': env.classeA}));
      await gestion.enregistrerEffectifs(admin, [
        EffectifSaisi(env.classeA, garcons: 20, filles: 25, visitesGarcons: 18, visitesFilles: 20, aptitudeGarcons: 3),
      ]);
      var l = await lus();
      expect((l.single.donnees['garcons'], l.single.donnees['aptitude_garcons']), (20, 3), reason: 'CM2 : visite d\'aptitude');
      await gestion.enregistrerEffectifs(admin, [EffectifSaisi(env.classeB, garcons: 10, filles: 9, aptitudeGarcons: 3)]);
      final ce1 = await env.depot.transaction((tx) => tx.chercher('effectif_classe', {'classe_id': env.classeB}));
      expect(ce1.single.donnees['aptitude_garcons'], isNull, reason: 'CE1 : pas de visite d\'aptitude');
      await gestion.enregistrerEffectifs(_droits(RoleCode.medecinChef), [EffectifSaisi(env.classeA, garcons: 21, filles: 25)]);
      l = await lus();
      expect((l.length, l.single.version, l.single.donnees['garcons'], l.single.donnees['visites_garcons']), (1, 2, 21, null));
      await expectLater(gestion.enregistrerEffectifs(admin, [EffectifSaisi(env.classeA, garcons: 2, visitesGarcons: 3)]),
          throwsA(isA<ErreurGestion>()));
      await expectLater(gestion.enregistrerEffectifs(_droits(RoleCode.medecin), [EffectifSaisi(env.classeA, garcons: 2)]),
          throwsA(isA<ErreurGestion>()));
      // Saisie vidée : les chiffres sont effacés, la fiche reste unique.
      await gestion.enregistrerEffectifs(admin, [EffectifSaisi(env.classeA)]);
      l = await lus();
      expect((l.length, l.single.donnees['garcons']), (1, null));
    });

    test('établissement sans code : code provisoire tiré du nom ; code conservé si effacé', () async {
      final admin = _droits(RoleCode.admin);
      final e = await gestion.creerEtablissement(admin, {'nom': 'EPP Kouassi 2', 'type': 'primaire', 'statut': 'public'});
      expect(e.donnees['code'], 'EPPKOU2');
      final f = await gestion.creerEtablissement(admin, {'nom': 'EPP Kouassi 2 bis', 'code': '', 'type': 'primaire', 'statut': 'public'});
      expect(f.donnees['code'], isNot('EPPKOU2'));
      final m = await gestion.modifierEtablissement(admin, e.id, {'nom': 'EPP Kouassi II', 'code': null});
      expect((m.donnees['nom'], m.donnees['code']), ('EPP Kouassi II', 'EPPKOU2'));
      final c = await gestion.modifierEtablissement(admin, e.id, {'code': 'x123'});
      expect(c.donnees['code'], 'X123');
      await expectLater(
          gestion.creerEtablissement(admin, {'nom': 'Autre', 'code': 'X123', 'type': 'primaire', 'statut': 'public'}),
          throwsA(isA<ErreurGestion>()));
    });
  });
}
