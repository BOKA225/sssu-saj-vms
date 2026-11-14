import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

/// Visite médicale d'aptitude (3ème et Tle) : formulaire, statistiques
/// séparées de la visite systématique, rapports.
void main() {
  Droits droits(RoleCode r) => Droits(utilisateurId: 'u', role: r, permissions: matriceParDefaut[r]!);
  const entete = EnteteRapport(lignes: ['DISTRICT SANITAIRE'], nomMedecinChef: 'Dr KOFFI');

  test('classes concernées : 3ème et terminale, général et technique', () {
    for (final c in ['3ème 1', '3e B', 'Troisième', 'Tle D', 'Terminale A1', 'Tle G2', 'TLE F2-1']) {
      expect(classeConcerneeParAptitude(c), isTrue, reason: c);
    }
    for (final c in ['CM2 A', '4ème 2', '1ère D', '2nde G1', 'BT 2', 'Groupe bleu']) {
      expect(classeConcerneeParAptitude(c), isFalse, reason: c);
    }
    expect(classeConcerneeParAptitude('Classe d\'examen', niveau: 'TLE'), isTrue);
    expect(classeConcerneeParAptitude('Classe d\'examen', niveau: '3ème'), isTrue);
  });

  group('Formulaire', () {
    FormulaireVisite visite() => FormulaireVisite(
          eleveId: 'e',
          agentId: 'a',
          dateVisite: DateTime.utc(2026, 11, 14),
          type: TypeVisite.aptitude,
          conclusion: ConclusionVisite.sansAnomalie,
        );

    test('décision obligatoire, restrictions ou motif sauf « apte »', () {
      final f = visite();
      expect(controlerVisite(f, aujourdhui: DateTime.utc(2026, 11, 14)).erreurs, contains('Choisir la décision d\'aptitude.'));
      f.aptitude = DecisionAptitude.aptePartiel;
      expect(controlerVisite(f, aujourdhui: DateTime.utc(2026, 11, 14)).erreurs,
          contains('Préciser les restrictions ou le motif de l\'inaptitude.'));
      f.aptitudeRestrictions = 'Pas de course d\'endurance';
      expect(controlerVisite(f, aujourdhui: DateTime.utc(2026, 11, 14)).transmissible, isTrue);
      f
        ..aptitude = DecisionAptitude.apte
        ..aptitudeRestrictions = '';
      expect(controlerVisite(f, aujourdhui: DateTime.utc(2026, 11, 14)).transmissible, isTrue);
    });

    test('enregistrement et rechargement ; visite systématique sans décision', () {
      final f = visite()
        ..aptitude = DecisionAptitude.inapteTemporaire
        ..aptitudeRestrictions = 'Entorse de la cheville';
      final d = f.donneesVisite();
      expect((d['type_visite'], d['aptitude'], d['aptitude_restrictions']),
          ('aptitude', 'inapte_temporaire', 'Entorse de la cheville'));
      final g = FormulaireVisite(eleveId: 'e', agentId: 'a', dateVisite: DateTime.utc(2026, 11, 14))..chargerVisite(d);
      expect((g.type, g.aptitude, g.aptitudeRestrictions),
          (TypeVisite.aptitude, DecisionAptitude.inapteTemporaire, 'Entorse de la cheville'));

      final s = FormulaireVisite(eleveId: 'e', agentId: 'a', dateVisite: DateTime.utc(2026, 11, 14))
        ..aptitude = DecisionAptitude.apte;
      final ds = s.donneesVisite();
      expect((ds['type_visite'], ds['aptitude']), ('systematique', null));
      // Visite enregistrée avant la version 1.6 : systématique.
      final ancienne = FormulaireVisite(eleveId: 'e', agentId: 'a', dateVisite: DateTime.utc(2026, 11, 14))
        ..chargerVisite({'date_visite': '2026-10-01', 'statut': 'valide'});
      expect(ancienne.type, TypeVisite.systematique);
    });
  });

  group('Statistiques séparées', () {
    final jeu = _jeu();

    test('visite systématique : tous les élèves, visites systématiques seulement', () {
      final s = calculerStatistiques(jeu, FiltreStatistiques(dateAge: DateTime.utc(2026, 11, 25)));
      expect((s.generale.effectif, s.generale.examines, s.nbVisites), (6, 2, 2));
      expect(s.aptitudes.values.every((n) => n == 0), isTrue);
      expect(s.parEtablissement.map((e) => e.libelle), ['Collège Moderne', 'EPP Centre']);
    });

    test('visite d\'aptitude : élèves de 3ème et Tle, décisions', () {
      final s = calculerStatistiques(
          jeu, FiltreStatistiques(typeVisite: TypeVisite.aptitude, dateAge: DateTime.utc(2026, 11, 25)));
      expect(s.typeVisite, TypeVisite.aptitude);
      expect((s.generale.effectif, s.generale.examines, s.nbVisites), (4, 3, 3),
          reason: 'élève de CM2 et sa visite d\'aptitude hors population');
      expect(s.parEtablissement.map((e) => e.libelle), ['Collège Moderne'], reason: 'école primaire écartée');
      expect(s.parClasse.map((c) => c.libelle), unorderedEquals(['3ème 1', 'Tle D']));
      expect(s.aptitudes, {
        DecisionAptitude.apte: 1,
        DecisionAptitude.aptePartiel: 1,
        DecisionAptitude.inapteTemporaire: 1,
        DecisionAptitude.inapteDefinitif: 0,
      });
      expect([for (final l in s.parTrancheAge) if (l.effectif > 0) (l.tranche, l.garcons, l.filles, l.examines)], [
        (TrancheAge.de10a14, 1, 0, 1),
        (TrancheAge.de15a19, 1, 2, 2),
      ]);
      // Les inspections ne dépendent pas du type de visite.
      expect(s.inspections.etablissements, 2);
    });

    test('liste des décisions d\'aptitude et rapports', () {
      final l = listeAptitudes(jeu, const FiltreStatistiques());
      expect(l.map((x) => (x.eleve.nom, x.derniereVisite!.aptitude, x.derniereVisite!.aptitudeRestrictions)), [
        ('BAMBA', DecisionAptitude.apte, null),
        ('KONE', DecisionAptitude.inapteTemporaire, 'Fracture du poignet'),
        ('YAO', DecisionAptitude.aptePartiel, 'Asthme : effort modéré'),
      ]);
      expect(listeAptitudes(jeu, const FiltreStatistiques(), decisions: {DecisionAptitude.apte}).length, 1);

      expect(() => rapportAptitudes(jeu, const FiltreStatistiques(), entete: entete, acteur: droits(RoleCode.agent),
          genereLe: DateTime.utc(2026, 11, 25)), throwsA(isA<RapportRefuse>()));
      final d = rapportAptitudes(jeu, const FiltreStatistiques(),
          entete: entete, acteur: droits(RoleCode.medecin), genereLe: DateTime.utc(2026, 11, 25));
      expect(d.sousTitre, startsWith('Visite médicale d\'aptitude (3ème et Tle) · Année scolaire 2026-2027'));
      expect((d.blocs.first as BlocParagraphe).texte, contains('1 apte'));
      final t = d.blocs[1] as BlocTableau;
      expect(t.lignes.map((x) => x[8]),
          ['Apte', 'Inapte temporairement', 'Aptitude partielle (avec restrictions)']);

      final r = rapportStatistique(jeu, const FiltreStatistiques(typeVisite: TypeVisite.aptitude),
          portee: PorteeRapport.annuel, entete: entete, acteur: droits(RoleCode.medecin), genereLe: DateTime.utc(2026, 11, 25));
      expect(r.titre, contains('visites d\'aptitude'));
      final titres = [for (final b in r.blocs) if (b is BlocTitre) b.texte];
      expect(titres.take(5), [
        '1. Indicateurs généraux',
        '2. Couverture par sexe',
        '3. Élèves par tranche d\'âge et par sexe',
        '4. Décisions d\'aptitude',
        '5. Conclusions des visites',
      ]);
      final sys = rapportStatistique(jeu, const FiltreStatistiques(),
          portee: PorteeRapport.annuel, entete: entete, acteur: droits(RoleCode.medecin), genereLe: DateTime.utc(2026, 11, 25));
      expect([for (final b in sys.blocs) if (b is BlocTitre) b.texte], isNot(contains(contains('Décisions'))));
      expect(sys.sousTitre, startsWith('Visite médicale systématique'));
      expect(rendreWord(r), isNotEmpty);
      expect(rendreExcel(r), isNotEmpty);
    });
  });
}

JeuStatistiques _jeu() {
  Map<String, Object?> l(Map<String, Object?> m) => {'deleted_at': null, ...m};
  return JeuStatistiques.depuisLignes(
    annee: AnneeStat('A', '2026-2027', DateTime.utc(2026, 9, 1), DateTime.utc(2027, 7, 31)),
    identite: true,
    etablissements: [l({'id': 'E1', 'nom': 'EPP Centre'}), l({'id': 'E2', 'nom': 'Collège Moderne'})],
    classes: [
      l({'id': 'C1', 'libelle': 'CM2 A', 'niveau': 'CM2', 'etablissement_id': 'E1', 'annee_scolaire_id': 'A'}),
      l({'id': 'C2', 'libelle': '3ème 1', 'niveau': '3EME', 'etablissement_id': 'E2', 'annee_scolaire_id': 'A'}),
      l({'id': 'C3', 'libelle': 'Tle D', 'etablissement_id': 'E2', 'annee_scolaire_id': 'A'}),
      l({'id': 'C4', 'libelle': '4ème 2', 'etablissement_id': 'E2', 'annee_scolaire_id': 'A'}),
    ],
    inscriptions: [
      for (final (e, c) in [('e1', 'C1'), ('e2', 'C2'), ('e3', 'C3'), ('e4', 'C3'), ('e5', 'C2'), ('e6', 'C4')])
        l({'eleve_id': e, 'classe_id': c, 'statut': 'inscrit'}),
    ],
    eleves: [
      l({'id': 'e1', 'nom': 'SORO', 'prenoms': 'Ali', 'sexe': 'M', 'date_naissance': '2015-02-01'}),
      l({'id': 'e2', 'nom': 'BAMBA', 'prenoms': 'Issa', 'sexe': 'M', 'date_naissance': '2012-03-01'}),
      l({'id': 'e3', 'nom': 'KONE', 'prenoms': 'Awa', 'sexe': 'F', 'date_naissance': '2008-05-01'}),
      l({'id': 'e4', 'nom': 'YAO', 'prenoms': 'Marie', 'sexe': 'F', 'date_naissance': '2009-06-01'}),
      l({'id': 'e5', 'nom': 'ZADI', 'prenoms': 'Paul', 'sexe': 'M', 'date_naissance': '2010-01-01'}),
      l({'id': 'e6', 'nom': 'TOURE', 'prenoms': 'Ami', 'sexe': 'F', 'date_naissance': '2013-01-01'}),
    ],
    visites: [
      // Visites systématiques.
      l({'id': 's1', 'eleve_id': 'e1', 'date_visite': '2026-10-05', 'statut': 'valide', 'conclusion': 'sans_anomalie'}),
      l({'id': 's2', 'eleve_id': 'e2', 'date_visite': '2026-10-06', 'statut': 'valide', 'conclusion': 'anomalie',
        'type_visite': 'systematique'}),
      // Visites d'aptitude.
      l({'id': 'a1', 'eleve_id': 'e2', 'date_visite': '2026-11-10', 'statut': 'valide', 'conclusion': 'sans_anomalie',
        'type_visite': 'aptitude', 'aptitude': 'apte'}),
      l({'id': 'a2', 'eleve_id': 'e3', 'date_visite': '2026-11-10', 'statut': 'synchronise', 'conclusion': 'anomalie',
        'type_visite': 'aptitude', 'aptitude': 'inapte_temporaire', 'aptitude_restrictions': 'Fracture du poignet'}),
      l({'id': 'a3', 'eleve_id': 'e4', 'date_visite': '2026-11-11', 'statut': 'valide', 'conclusion': 'suivi',
        'type_visite': 'aptitude', 'aptitude': 'apte_partiel', 'aptitude_restrictions': 'Asthme : effort modéré'}),
      l({'id': 'a4', 'eleve_id': 'e1', 'date_visite': '2026-11-12', 'statut': 'valide', 'conclusion': 'sans_anomalie',
        'type_visite': 'aptitude', 'aptitude': 'apte'}),
      l({'id': 'a5', 'eleve_id': 'e5', 'date_visite': '2026-11-12', 'statut': 'ebauche', 'type_visite': 'aptitude'}),
    ],
    visitePathologies: const [],
    pathologies: const [],
    inspections: [
      l({'id': 'I1', 'etablissement_id': 'E1', 'date_inspection': '2026-10-10', 'statut': 'enregistre', 'niveau': 'moyen'}),
      l({'id': 'I2', 'etablissement_id': 'E2', 'date_inspection': '2026-10-11', 'statut': 'enregistre', 'niveau': 'satisfaisant'}),
    ],
  );
}
