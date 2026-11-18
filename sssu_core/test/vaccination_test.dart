import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

import 'outils/environnement.dart';

Droits _droits(RoleCode r) => Droits(utilisateurId: 'u-${r.name}', role: r, permissions: matriceParDefaut[r]!);

const _bcg = Vaccin(id: 'v-bcg', code: 'BCG', libelle: 'BCG', programme: ProgrammeVaccin.pev, statut: StatutVaccin.obligatoire, ordre: 1);
const _rr = Vaccin(id: 'v-rr', code: 'RR', libelle: 'Rougeole-rubéole', programme: ProgrammeVaccin.pev, statut: StatutVaccin.obligatoire, ordre: 2);
const _hpv = Vaccin(
    id: 'v-hpv', code: 'HPV', libelle: 'HPV', programme: ProgrammeVaccin.pev, statut: StatutVaccin.obligatoire, prescolaire: false, ordre: 3);
const _ror = Vaccin(id: 'v-ror', code: 'ROR', libelle: 'ROR', programme: ProgrammeVaccin.horsPev, statut: StatutVaccin.recommande, ordre: 1);
const _ancien = Vaccin(
    id: 'v-x', code: 'X', libelle: 'Ancien', programme: ProgrammeVaccin.pev, statut: StatutVaccin.obligatoire, actif: false);

void main() {
  group('Modèle', () {
    test('identifiant du suivi vaccinal : le même sur tous les appareils, UUID version 5', () {
      final a = idSuiviVaccinal('019a7c3e-0000-7000-8000-000000000001');
      expect(a, idSuiviVaccinal('019a7c3e-0000-7000-8000-000000000001'));
      expect(a, isNot(idSuiviVaccinal('019a7c3e-0000-7000-8000-000000000002')));
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(a), isTrue);
      expect(SuiviVaccinal(eleveId: 'e1').id, idSuiviVaccinal('e1'));
    });

    test('classes du préscolaire et filles concernées par le vaccin HPV', () {
      for (final c in ['Petite section', 'Moyenne section A', 'Grande section 2', 'GS', 'PS1', 'ms b', 'GS-2']) {
        expect(classePrescolaire(c), isTrue, reason: c);
      }
      for (final c in ['CP1', 'CM2 A', '6ème 1', 'Tle D']) {
        expect(classePrescolaire(c), isFalse, reason: c);
      }
      expect(classePrescolaire('Classe 1', niveau: 'MS'), isTrue);
      expect(classePrescolaire('Section des lions', typeEtablissement: 'prescolaire'), isTrue);
      expect(classePrescolaire('Section des lions', typeEtablissement: 'primaire'), isFalse);

      final visite = DateTime.utc(2026, 11, 18);
      bool hpv(String naissance, {Sexe sexe = Sexe.feminin, TypeVisite type = TypeVisite.systematique}) =>
          hpvConcerne(sexe: sexe, dateNaissance: lireDate(naissance), dateVisite: visite, type: type);
      expect(hpv('2017-11-18'), isTrue, reason: '9 ans le jour même');
      expect(hpv('2017-11-19'), isFalse, reason: '8 ans');
      expect(hpv('2012-01-01'), isTrue, reason: '14 ans');
      expect(hpv('2011-11-18'), isFalse, reason: '15 ans');
      expect(hpv('2014-05-05', sexe: Sexe.masculin), isFalse);
      expect(hpv('2014-05-05', type: TypeVisite.aptitude), isFalse);
      expect(hpvConcerne(sexe: Sexe.feminin, dateNaissance: null, dateVisite: visite), isFalse);
    });

    test('suivi vaccinal : colonnes, relecture, fiche vide', () {
      final s = SuiviVaccinal(
        eleveId: 'e1',
        parentTuteur: ' KOUAME Akissi ',
        parentTelephone: '0707070707',
        carnetPresente: true,
        observations: '',
        dateVerification: DateTime.utc(2026, 11, 18),
        vaccins: {'v-rr': false, 'v-bcg': true},
      );
      final d = s.versDonnees();
      expect(registreParNom['suivi_vaccinal']!.nomsColonnes, containsAll(d.keys));
      expect(d['vaccins'], '{"v-bcg":true,"v-rr":false}', reason: 'rangés par identifiant');
      expect((d['parent_tuteur'], d['observations'], d['date_verification']), ('KOUAME Akissi', null, '2026-11-18'));
      final relu = SuiviVaccinal.depuisDonnees(d);
      expect(relu.vaccins, {'v-bcg': true, 'v-rr': false});
      expect((relu.carnetPresente, relu.parentTelephone), (true, '0707070707'));
      expect(SuiviVaccinal(eleveId: 'e1').vide, isTrue);
      expect(SuiviVaccinal(eleveId: 'e1', carnetPresente: false).vide, isFalse);
      expect(SuiviVaccinal.depuisDonnees({'eleve_id': 'e', 'vaccins': null}).vaccins, isEmpty);
      expect(registreParNom['vaccin']!.nomsColonnes, containsAll(_ror.versDonnees().keys));
      expect(Vaccin.depuisDonnees('i', {..._ror.versDonnees(), 'actif': 0, 'prescolaire': 1}).actif, isFalse);
    });

    test('état vaccinal (vaccins obligatoires) et couverture par vaccin', () {
      final liste = vaccinsPrescolaire([_ror, _hpv, _ancien, _rr, _bcg]);
      expect(liste.map((v) => v.code), ['BCG', 'RR', 'ROR'], reason: 'actifs du préscolaire, PEV puis hors PEV');
      expect(etatVaccinal(null, liste), EtatVaccinal.nonRenseigne);
      expect(etatVaccinal(SuiviVaccinal(eleveId: 'e', vaccins: {'v-ror': true}), liste), EtatVaccinal.nonRenseigne);
      expect(etatVaccinal(SuiviVaccinal(eleveId: 'e', vaccins: {'v-bcg': true}), liste), EtatVaccinal.incomplet);
      expect(etatVaccinal(SuiviVaccinal(eleveId: 'e', vaccins: {'v-bcg': true, 'v-rr': false}), liste), EtatVaccinal.incomplet);
      expect(etatVaccinal(SuiviVaccinal(eleveId: 'e', vaccins: {'v-bcg': true, 'v-rr': true}), liste), EtatVaccinal.aJour,
          reason: 'le vaccin recommandé non fait ne compte pas');
      EnfantVaccination enfant(String id, Map<String, bool>? v) => EnfantVaccination(
          eleveId: id, nom: 'N$id', prenoms: 'P', sexe: Sexe.feminin, etablissementId: 'E', etablissement: 'EPP',
          classeId: 'C', classe: 'GS', suivi: v == null ? null : SuiviVaccinal(eleveId: id, vaccins: v));
      final enfants = [
        enfant('1', {'v-bcg': true, 'v-rr': true}),
        enfant('2', {'v-bcg': true, 'v-rr': false, 'v-ror': true}),
        enfant('3', null),
        enfant('4', {'v-bcg': false}),
      ];
      final c = {for (final x in couvertureVaccins(enfants, liste)) x.vaccin.code: (x.faits, x.nonFaits, x.nonRenseignes, x.tauxCouverture)};
      expect(c['BCG'], (2, 1, 1, 50.0));
      expect(c['RR'], (1, 1, 2, 25.0));
      expect(c['ROR'], (1, 0, 3, 25.0));
      expect(repartitionEtats(enfants, liste),
          {EtatVaccinal.aJour: 1, EtatVaccinal.incomplet: 2, EtatVaccinal.nonRenseigne: 1});
    });

    test('vaccin HPV dans la visite : contrôles, colonnes, relecture', () {
      FormulaireVisite f() => FormulaireVisite(eleveId: 'e', agentId: 'a', dateVisite: DateTime.utc(2026, 11, 18))
        ..conclusion = ConclusionVisite.sansAnomalie;
      final aucune = f();
      expect(controlerVisite(aucune, hpv: true).erreurs, contains(startsWith('Vaccin HPV : indiquer')));
      expect(controlerVisite(aucune).erreurs.where((e) => e.contains('HPV')), isEmpty, reason: 'fille non concernée');
      expect(controlerVisite(f()..hpv = StatutHpv.aProposer, hpv: true).erreurs, contains(contains('« fait » ou « pas fait »')));
      expect(controlerVisite(f()..hpv = StatutHpv.nonFait, hpv: true).erreurs, contains('Vaccin HPV non fait : choisir le motif.'));
      for (final ok in [
        f()..hpv = StatutHpv.dejaFait,
        f()..hpv = StatutHpv.fait,
        f()
          ..hpv = StatutHpv.nonFait
          ..hpvMotif = MotifHpv.refusParents,
      ]) {
        expect(controlerVisite(ok, hpv: true).erreurs.where((e) => e.contains('HPV')), isEmpty);
      }
      final d = (f()
            ..hpv = StatutHpv.nonFait
            ..hpvMotif = MotifHpv.vaccinIndisponible)
          .donneesVisite();
      expect(registreParNom['visite']!.nomsColonnes, containsAll(d.keys));
      expect((d['hpv'], d['hpv_motif']), ('non_fait', 'vaccin_indisponible'));
      expect((f()..hpv = StatutHpv.fait..hpvMotif = MotifHpv.autre).donneesVisite()['hpv_motif'], isNull,
          reason: 'motif seulement si non fait');
      expect((f()..type = TypeVisite.aptitude..hpv = StatutHpv.fait).donneesVisite()['hpv'], isNull);
      final relu = f()..chargerVisite(d);
      expect((relu.hpv, relu.hpvMotif), (StatutHpv.nonFait, MotifHpv.vaccinIndisponible));
      expect(StatutHpv.fait.vaccinee && StatutHpv.dejaFait.vaccinee && !StatutHpv.nonFait.vaccinee, isTrue);
    });
  });

  group('Gestion sur le poste central', () {
    late Environnement env;
    late ServiceGestion gestion;
    final chef = _droits(RoleCode.medecinChef);

    setUp(() async {
      env = await Environnement.creer();
      gestion = ServiceGestion(depot: env.depot, horloge: env.horloge, hacheur: HacheurMotDePasse(parametres: ParametresArgon2.tests));
    });

    test('vaccins : ajout (code tiré du nom), doublon refusé, modification, droits', () async {
      final v = await gestion.creerVaccin(
          chef,
          const Vaccin(
              id: '', code: '', libelle: 'Fièvre jaune (VAA)', programme: ProgrammeVaccin.pev, statut: StatutVaccin.obligatoire, cible: ' 9 mois '));
      expect((v.donnees['code'], v.donnees['cible'], v.donnees['ordre'], v.donnees['actif']), ('FIEVRE_JAUNE_VAA', '9 mois', 1, true));
      await expectLater(
          gestion.creerVaccin(
              chef,
              const Vaccin(
                  id: '', code: '', libelle: 'fièvre jaune (vaa)', programme: ProgrammeVaccin.pev, statut: StatutVaccin.obligatoire)),
          throwsA(isA<ErreurGestion>()));
      final h = await gestion.creerVaccin(chef,
          const Vaccin(id: '', code: 'hpv', libelle: 'HPV', programme: ProgrammeVaccin.pev, statut: StatutVaccin.obligatoire));
      expect((h.donnees['code'], h.donnees['ordre']), ('HPV', 2));
      final m = await gestion.modifierVaccin(chef, v.id,
          Vaccin.depuis(v).copieAvec(statut: StatutVaccin.recommande, programme: ProgrammeVaccin.horsPev, actif: false));
      expect((m.donnees['code'], m.donnees['statut'], m.donnees['programme'], m.donnees['actif'], m.version),
          ('FIEVRE_JAUNE_VAA', 'recommande', 'hors_pev', false, 2));
      await expectLater(gestion.modifierVaccin(chef, h.id, Vaccin.depuis(h).copieAvec(libelle: 'Fièvre jaune (VAA)')),
          throwsA(isA<ErreurGestion>()));
      await expectLater(
          gestion.creerVaccin(_droits(RoleCode.agent),
              const Vaccin(id: '', code: '', libelle: 'Varicelle', programme: ProgrammeVaccin.horsPev, statut: StatutVaccin.recommande)),
          throwsA(isA<ErreurGestion>()));
    });

    test('suivi vaccinal : une fiche par enfant, dans le périmètre de son établissement', () async {
      final s = SuiviVaccinal(eleveId: env.eleveA, parentTuteur: 'KOUASSI Aya', carnetPresente: true, vaccins: {'v-bcg': true});
      final a = await gestion.enregistrerSuiviVaccinal(chef, s);
      expect((a.id, a.etablissementId, a.version, a.donnees['date_verification']),
          (idSuiviVaccinal(env.eleveA), env.etabA, 1, '2026-11-10'));
      final b = await gestion.enregistrerSuiviVaccinal(chef, s..vaccins['v-rr'] = false);
      expect((b.id, b.version), (a.id, 2));
      expect(jsonDecode(b.donnees['vaccins']! as String), {'v-bcg': true, 'v-rr': false});
      final suivis = await env.depot.transaction((tx) => tx.chercher('suivi_vaccinal', {'eleve_id': env.eleveA}));
      expect(suivis, hasLength(1));
      await expectLater(gestion.enregistrerSuiviVaccinal(_droits(RoleCode.admin), s), throwsA(isA<ErreurGestion>()),
          reason: 'l\'administrateur n\'accède pas aux données médicales');
    });

    test('téléphone en version 1.7 : vaccins et visite avec le vaccin HPV retenus, mise à jour demandée', () async {
      final id = await env.appairer('Version 1.7', [env.etabA]);
      final m = env.horloge.maintenant();
      Enregistrement visite(String? hpv) => Enregistrement(
          table: 'visite',
          id: nouvelId(),
          version: 1,
          versionBase: 1,
          createdAt: m,
          updatedAt: m,
          etablissementId: env.etabA,
          donnees: {
            'eleve_id': env.eleveA,
            'agent_id': env.medecin.id,
            'date_visite': '2026-11-10',
            'statut': 'valide',
            'type_visite': 'systematique',
            'hpv': hpv,
          });
      final sans = visite(null);
      final avec = visite('fait');
      await env.depot.transaction((tx) async {
        await tx.ecrire(sans);
        await tx.ecrire(avec);
      });
      expect(ServiceSynchronisation.compatible(avec, 3), isFalse);
      expect(ServiceSynchronisation.compatible(sans, 3), isTrue);
      expect(ServiceSynchronisation.protocoleRequis(avec), 4);
      final suivi = await gestion.enregistrerSuiviVaccinal(chef, SuiviVaccinal(eleveId: env.eleveA, carnetPresente: false));
      expect(ServiceSynchronisation.compatible(suivi, 3), isFalse);

      final recus = <String>{};
      var curseur = 0;
      ErreurProtocole? refus;
      for (var i = 0; i < 50; i++) {
        try {
          final r = await env.sync.preparerReception(id.appareilId, curseur, protocole: 3);
          recus.addAll(r.changements.map((c) => c.enregistrement.id));
          curseur = r.curseur;
          if (!r.suite) break;
        } on ErreurProtocole catch (e) {
          refus = e;
          break;
        }
      }
      expect(recus, contains(sans.id));
      expect(recus, isNot(contains(avec.id)));
      expect(refus?.codeHttp, 426);
      expect(refus?.message, contains('vaccination'));
    });
  });

  group('Statistiques et rapports', () {
    final annee = AnneeStat('A', '2026-2027', DateTime.utc(2026, 9, 1), DateTime.utc(2027, 7, 31));
    Map<String, Object?> eleve(String id, String sexe, String? naissance) =>
        {'id': id, 'sexe': sexe, 'date_naissance': naissance, 'nom': 'NOM$id', 'prenoms': 'P$id'};
    Map<String, Object?> visite(String id, String eleve, String date, {String? hpv, String? motif, String type = 'systematique'}) =>
        {'id': id, 'eleve_id': eleve, 'date_visite': date, 'statut': 'valide', 'type_visite': type, 'hpv': hpv, 'hpv_motif': motif};
    final jeu = JeuStatistiques.depuisLignes(
      annee: annee,
      etablissements: [
        {'id': 'E1', 'nom': 'EPP A'},
        {'id': 'E2', 'nom': 'Lycée B'},
      ],
      classes: [
        {'id': 'C1', 'libelle': 'CM1', 'etablissement_id': 'E1', 'annee_scolaire_id': 'A'},
        {'id': 'C2', 'libelle': '5ème 1', 'etablissement_id': 'E2', 'annee_scolaire_id': 'A'},
      ],
      inscriptions: [
        for (final (e, c) in [('f1', 'C1'), ('f2', 'C1'), ('f3', 'C2'), ('f4', 'C2'), ('f5', 'C2'), ('f6', 'C2'), ('g1', 'C1'), ('f7', 'C2')])
          {'eleve_id': e, 'classe_id': c, 'statut': 'inscrit'},
      ],
      eleves: [
        eleve('f1', 'F', '2016-10-01'), // 10 ans : déjà vaccinée
        eleve('f2', 'F', '2017-12-01'), // 8 ans à la visite : non concernée
        eleve('f3', 'F', '2013-02-02'), // 13 ans : non fait puis fait (rattrapage)
        eleve('f4', 'F', '2012-03-03'), // 14 ans : non fait, refus des parents
        eleve('f5', 'F', '2011-04-04'), // 15 ans : non concernée
        eleve('f6', 'F', '2014-05-05'), // 12 ans : non examinée
        eleve('g1', 'M', '2015-06-06'), // garçon
        eleve('f7', 'F', '2013-07-07'), // 13 ans : visite sans statut HPV
      ],
      visites: [
        visite('v1', 'f1', '2026-10-05', hpv: 'deja_fait'),
        visite('v2', 'f2', '2026-10-05'),
        visite('v3', 'f3', '2026-10-06', hpv: 'non_fait', motif: 'vaccin_indisponible'),
        visite('v4', 'f3', '2026-11-06', hpv: 'fait'),
        visite('v5', 'f4', '2026-10-07', hpv: 'non_fait', motif: 'refus_parents'),
        visite('v6', 'f5', '2026-10-07'),
        visite('v7', 'g1', '2026-10-07'),
        visite('v8', 'f7', '2026-10-08'),
        visite('v9', 'f6', '2026-10-08', hpv: 'fait', type: 'aptitude'), // autre type : pas comptée
      ],
      visitePathologies: const [],
      pathologies: const [],
    );

    test('bilan HPV des filles de 9 à 14 ans', () {
      final s = calculerStatistiques(jeu, FiltreStatistiques(dateAge: DateTime.utc(2026, 11, 18)));
      final e = s.hpv.ensemble;
      expect((e.cibles, e.examinees, e.dejaVaccinees, e.vaccineesVisite, e.nonVaccinees, e.nonRenseignees),
          (5, 4, 1, 1, 1, 1));
      expect((e.vaccinees, e.proposees, e.couverture, e.couvertureCible), (2, 2, 50.0, 40.0));
      expect(s.hpv.motifs, {MotifHpv.refusParents: 1});
      final parEtab = {for (final l in s.hpv.parEtablissement) l.id: (l.cibles, l.examinees, l.vaccinees)};
      expect(parEtab, {'E1': (1, 1, 1), 'E2': (4, 3, 1)});
      expect(calculerStatistiques(jeu, const FiltreStatistiques(typeVisite: TypeVisite.aptitude)).hpv.ensemble.cibles, 0);
    });

    test('rapports : bilan HPV, vaccination du préscolaire (nominative), rendus', () async {
      const entete = EnteteRapport(lignes: EnteteRapport.lignesParDefaut, nomMedecinChef: 'Dr KOFFI Marc');
      final genereLe = DateTime.utc(2026, 11, 18, 10);
      final chef = _droits(RoleCode.medecinChef);
      final annuel = rapportStatistique(jeu, FiltreStatistiques(dateAge: DateTime.utc(2026, 11, 18)),
          portee: PorteeRapport.annuel, entete: entete, acteur: chef, genereLe: genereLe);
      expect(annuel.blocs.whereType<BlocTitre>().map((t) => t.texte), contains(endsWith('Vaccin HPV des filles de 9 à 14 ans')));
      final h = rapportHpv(jeu, const FiltreStatistiques(typeVisite: TypeVisite.aptitude),
          entete: entete, acteur: _droits(RoleCode.admin), genereLe: genereLe);
      final parEtab = h.blocs.whereType<BlocTableau>().firstWhere((t) => t.titre == 'Par établissement');
      expect(parEtab.lignes.map((l) => l[0]), ['EPP A', 'Lycée B'], reason: 'visite systématique, quel que soit le filtre');
      expect(parEtab.totaux!.last, '50 %');

      final liste = [_bcg, _rr, _ror, _hpv];
      final enfants = [
        EnfantVaccination(
            eleveId: '1', nom: 'AKA', prenoms: 'Ange', sexe: Sexe.masculin, dateNaissance: DateTime.utc(2021, 3, 1),
            etablissementId: 'E1', etablissement: 'EPP A', classeId: 'C', classe: 'Grande section',
            telephoneContact: '0101010101',
            suivi: SuiviVaccinal(eleveId: '1', parentTuteur: 'AKA Jean', carnetPresente: true, vaccins: {'v-bcg': true, 'v-rr': false})),
        const EnfantVaccination(
            eleveId: '2', nom: 'BLE', prenoms: 'Awa', sexe: Sexe.feminin, etablissementId: 'E1', etablissement: 'EPP A',
            classeId: 'C', classe: 'Grande section'),
      ];
      final d = rapportVaccinationPrescolaire(enfants, liste,
          perimetre: 'Année 2026-2027 · EPP A', entete: entete, acteur: chef, genereLe: genereLe);
      expect(d.confidentiel, isTrue);
      final t = d.blocs.whereType<BlocTableau>().firstWhere((t) => t.titre == 'Enfants');
      expect(t.entetes, ['N°', 'Nom et prénoms', 'Sexe', 'Né(e) le', 'Classe', 'Parent ou tuteur', 'Carnet', 'BCG', 'RR', 'ROR', 'État'],
          reason: 'un seul établissement ; HPV hors de la liste du préscolaire');
      expect(t.lignes[0], [1, 'AKA Ange', 'M', '01/03/2021', 'Grande section', 'AKA Jean – 0101010101', 'Oui', '✓', '✗', '', 'Incomplet']);
      expect(t.lignes[1].last, 'Non renseigné');
      final couverture = d.blocs.whereType<BlocTableau>().firstWhere((t) => t.titre == 'Couverture par vaccin');
      expect(couverture.lignes.first, ['BCG', 'PEV', 'Obligatoire', 1, 0, 1, '50 %']);
      expect(
          () => rapportVaccinationPrescolaire(enfants, liste,
              perimetre: '', entete: entete, acteur: _droits(RoleCode.admin), genereLe: genereLe),
          throwsA(isA<RapportRefuse>()));

      final polices = PolicesRapport(
        normale: File('../sssu_windows/assets/polices/DejaVuSans.ttf').readAsBytesSync(),
        grasse: File('../sssu_windows/assets/polices/DejaVuSans-Bold.ttf').readAsBytesSync(),
      );
      for (final doc in [d, h]) {
        expect(ascii.decode((await rendrePdf(doc, polices)).sublist(0, 5)), '%PDF-');
        expect(rendreWord(doc), isNotEmpty);
      }
      final lignes = Excel.decodeBytes(rendreExcel(d)).tables['Rapport']!.rows;
      expect(lignes.any((l) => l.isNotEmpty && l[1]?.value.toString() == 'AKA Ange'), isTrue);
    });
  });
}
