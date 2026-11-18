import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:sssu_windows/donnees/depot_postgres.dart';
import 'package:sssu_windows/donnees/migrations.dart';
import 'package:sssu_windows/donnees/requetes_poste.dart';
import 'package:sssu_windows/donnees/source_statistiques.dart';
import 'package:sssu_windows/donnees/stockage_photos.dart';

void main() {
  group('Stockage chiffré des photos', () {
    late Directory dossier;
    setUp(() async => dossier = await Directory.systemTemp.createTemp('sssu_photos'));
    tearDown(() => dossier.delete(recursive: true));

    test('écriture contrôlée par empreinte, lecture, export, fichier chiffré sur disque', () async {
      final s = await StockagePhotosPoste.ouvrir(dossier);
      final id = nouvelId();
      final jpeg = List<int>.generate(2000, (i) => i % 256);
      expect(await s.disponible(id), isFalse);
      await expectLater(s.ecrire(id, jpeg, empreinteAttendue: 'faux'), throwsStateError);
      await s.ecrire(id, jpeg, empreinteAttendue: sha256Hex(jpeg));
      expect(await s.disponible(id), isTrue);
      expect(await s.lire(id), jpeg);
      expect(File('${dossier.path}/photos/$id.enc').readAsBytesSync(), isNot(jpeg));
      final export = '${dossier.path}/export.jpg';
      await s.exporter(id, export);
      expect(File(export).readAsBytesSync(), jpeg);
      // La même clé est réutilisée à la réouverture.
      expect(await (await StockagePhotosPoste.ouvrir(dossier)).lire(id), jpeg);
      expect(() => s.disponible('../../etc/passwd'), throwsArgumentError);
    });
  });

  // Tests sur une base PostgreSQL de TEST où 001_schema.sql, donnees_test.sql et
  // 010_initialiser_journal_sync.sql ont été chargés (SSSU_PG_TEST_URL).
  final url = Platform.environment['SSSU_PG_TEST_URL'];
  final ignorer = url == null ? 'SSSU_PG_TEST_URL non définie' : null;

  group('Gestion sur PostgreSQL', () {
    late DepotPostgres depot;
    late RequetesPoste r;
    late ServiceGestion g;
    late Droits chef;

    setUpAll(() async {
      if (url == null) return;
      depot = await DepotPostgres.ouvrir(ConfigPostgres.depuisUrl(url));
      await MigrationsPoste(depot, Directory('../sql/postgres')).appliquer();
      r = RequetesPoste(depot);
      g = ServiceGestion(depot: depot, hacheur: HacheurMotDePasse(parametres: ParametresArgon2.tests));
      chef = Droits(utilisateurId: nouvelId(), role: RoleCode.medecinChef, permissions: matriceParDefaut[RoleCode.medecinChef]!);
    });
    tearDownAll(() async {
      if (url != null) await depot.fermer();
    });

    test('requêtes des écrans sur le jeu de test', () async {
      final a = (await r.anneeCourante())!;
      final etabs = await r.etablissements(a);
      expect(etabs.length, greaterThanOrEqualTo(2));
      // D'autres fichiers de test ajoutent des établissements sans classe à la
      // même base : on prend un établissement du jeu de test, qui en a.
      var classes = const <LigneClasse>[];
      for (final e in etabs) {
        classes = await r.classes(e.id, a);
        if (classes.isNotEmpty) break;
      }
      expect(classes.first.effectif, greaterThan(0));
      final eleves = await r.eleves(a, classeId: classes.first.id);
      expect(eleves.length, classes.first.effectif);
      expect(await r.eleves(a, texte: eleves.first.nom), isNotEmpty);
      expect(await r.inscriptions(eleves.first.id), isNotEmpty);
    }, skip: ignorer);

    test('visite d\'aptitude sur PostgreSQL : migration 050, type conservé, statistiques séparées', () async {
      final a = (await r.anneeCourante())!;
      LigneEleve? eleve;
      String? etabId;
      for (final e in await r.etablissements(a)) {
        final classes = await r.classes(e.id, a);
        if (classes.isEmpty || classes.first.effectif == 0) continue;
        eleve = (await r.eleves(a, classeId: classes.first.id)).first;
        etabId = e.id;
        break;
      }
      final m = DateTime.now().toUtc();
      var agents = await depot.requete('SELECT id::text AS id FROM utilisateur LIMIT 1');
      if (agents.isEmpty) {
        final role = (await depot.requete('SELECT id::text AS id FROM role LIMIT 1')).first['id'] as String;
        final u = Enregistrement(
            table: 'utilisateur',
            id: nouvelId(),
            version: 1,
            versionBase: 1,
            createdAt: m,
            updatedAt: m,
            donnees: {'identifiant': 'apt-${nouvelId().substring(28)}', 'nom': 'AGENT APTITUDE', 'role_id': role});
        await depot.transaction((tx) => tx.ecrire(u));
        agents = [{'id': u.id}];
      }
      final v = Enregistrement(
          table: 'visite',
          id: nouvelId(),
          version: 1,
          versionBase: 1,
          createdAt: m,
          updatedAt: m,
          etablissementId: etabId,
          donnees: {
            'eleve_id': eleve!.id,
            'agent_id': agents.first['id'],
            'date_visite': a.debut,
            'statut': 'valide',
            'type_visite': 'aptitude',
            'aptitude': 'inapte_temporaire',
            'aptitude_restrictions': 'Entorse de la cheville',
          });
      try {
        await depot.transaction((tx) => tx.ecrire(v));
        var relu = (await depot.transaction((tx) => tx.lire('visite', v.id)))!;
        expect((relu.donnees['type_visite'], relu.donnees['aptitude'], relu.donnees['aptitude_restrictions']),
            ('aptitude', 'inapte_temporaire', 'Entorse de la cheville'));
        // Écriture sans le type (téléphone d'une version antérieure) : le type reste.
        await depot.transaction((tx) => tx.ecrire(v.copier(
            version: 2, donnees: {...v.donnees}..remove('type_visite'))));
        relu = (await depot.transaction((tx) => tx.lire('visite', v.id)))!;
        expect(relu.donnees['type_visite'], 'aptitude');
        await expectLater(
            depot.requete("UPDATE visite SET type_visite = 'autre' WHERE id = CAST(@id AS uuid)", {'id': v.id}),
            throwsA(anything));
        final jeu = await SourceStatistiquesPoste(depot).charger(a, identite: true);
        final vs = jeu.visites.singleWhere((x) => x.id == v.id);
        expect((vs.type, vs.aptitude, vs.aptitudeRestrictions),
            (TypeVisite.aptitude, DecisionAptitude.inapteTemporaire, 'Entorse de la cheville'));
        // La visite d'aptitude ne compte pas parmi les « examinés » des écrans.
        final avant = jeu.visites.where((x) => x.type == TypeVisite.systematique).length;
        expect(avant, lessThan(jeu.visites.length));
      } finally {
        await depot.requete('DELETE FROM visite WHERE id = CAST(@id AS uuid)', {'id': v.id});
      }
    }, skip: ignorer);

    test('listes de classe d\'un établissement : toutes les classes, effectifs, ordre scolaire', () async {
      final a = (await r.anneeCourante())!;
      for (final e in await r.etablissements(a)) {
        final classes = await r.classes(e.id, a);
        if (classes.isEmpty) continue;
        final listes = await r.listesDeClasses(e.id, a);
        expect(listes.map((l) => l.classeId).toSet(), classes.map((c) => c.id).toSet());
        for (final c in classes) {
          final l = listes.singleWhere((x) => x.classeId == c.id);
          expect((l.eleves.length, l.garcons, l.filles), (c.effectif, c.garcons, c.filles), reason: c.libelle);
        }
        final libelles = listes.map((l) => l.libelle).toList();
        expect(libelles, [...libelles]..sort(comparerClasses));
        return;
      }
      fail('aucun établissement avec des classes');
    }, skip: ignorer);

    test('vaccination sur PostgreSQL : migration 060, vaccins, suivi d\'un enfant du préscolaire, vaccin HPV', () async {
      final a = (await r.anneeCourante())!;
      final vaccins = await r.vaccins();
      expect(vaccins.map((v) => v.code), containsAll(['BCG', 'PENTA', 'PCV13', 'RR', 'VAA', 'PALU', 'HPV', 'ROR', 'VARICELLE']));
      expect(vaccins.firstWhere((v) => v.code == 'HPV').prescolaire, isFalse);
      expect(vaccinsPrescolaire(vaccins).first.programme, ProgrammeVaccin.pev);
      expect(vaccinsPrescolaire(vaccins).last.programme, ProgrammeVaccin.horsPev);
      final diffuses = await depot.requete("SELECT COUNT(DISTINCT record_id) AS n FROM sync_changement WHERE table_name = 'vaccin'");
      expect((diffuses.first['n'] as num).toInt(), greaterThanOrEqualTo(vaccins.length), reason: 'liste envoyée aux téléphones');
      await expectLater(
          depot.requete("UPDATE vaccin SET programme = 'autre' WHERE code = 'BCG'"), throwsA(anything));

      // Enfant ajouté dans une classe d'un établissement préscolaire, puis sa fiche.
      final e = await g.creerEtablissement(
          chef, {'nom': 'Préscolaire PG', 'code': 'PS-${nouvelId().substring(30)}', 'type': 'prescolaire', 'statut': 'public'});
      final c = await g.creerClasse(chef, etablissementId: e.id, anneeScolaireId: a.id, libelle: 'Moyenne section');
      final enfant = await g.creerEleve(chef,
          identite: {'nom': 'YAO', 'prenoms': 'Ange', 'sexe': 'M', 'date_naissance': '2022-02-02', 'telephone_contact': '0505'},
          classeId: c.id);
      var liste = await r.enfantsPrescolaire(a, etablissementId: e.id);
      expect((liste.single.eleveId, liste.single.suivi, liste.single.classe), (enfant.id, null, 'Moyenne section'));
      expect((await r.enfantsPrescolaire(a)).map((x) => x.eleveId), contains(enfant.id));
      final bcg = vaccins.firstWhere((v) => v.code == 'BCG');
      final rr = vaccins.firstWhere((v) => v.code == 'RR');
      final s = SuiviVaccinal(eleveId: enfant.id, parentTuteur: 'YAO Koffi', carnetPresente: true, vaccins: {bcg.id: true});
      expect((await g.enregistrerSuiviVaccinal(chef, s)).etablissementId, e.id);
      await g.enregistrerSuiviVaccinal(chef, s
        ..observations = 'Penta 3 en retard'
        ..vaccins[rr.id] = false);
      liste = await r.enfantsPrescolaire(a, etablissementId: e.id);
      final lu = liste.single.suivi!;
      expect((lu.parentTuteur, lu.carnetPresente, lu.observations), ('YAO Koffi', true, 'Penta 3 en retard'));
      expect(lu.vaccins, {bcg.id: true, rr.id: false});
      expect(etatVaccinal(lu, vaccinsPrescolaire(vaccins)), EtatVaccinal.incomplet);
      expect((await r.suiviVaccinal(enfant.id))!.vaccins, {bcg.id: true, rr.id: false});
      final relu = (await depot.transaction((tx) => tx.lire('suivi_vaccinal', idSuiviVaccinal(enfant.id))))!;
      expect((relu.version, relu.etablissementId), (2, e.id));

      // Vaccin ajouté sur le poste : dans la liste, diffusé.
      final nouveau = await g.creerVaccin(
          chef,
          Vaccin(
              id: '',
              code: '',
              libelle: 'Rage PG ${nouvelId().substring(30)}',
              programme: ProgrammeVaccin.horsPev,
              statut: StatutVaccin.recommande));
      expect((await r.vaccins()).map((v) => v.id), contains(nouveau.id));

      // Vaccin HPV noté dans une visite : conservé, lu par les statistiques.
      final m = DateTime.now().toUtc();
      final agents = await depot.requete('SELECT id::text AS id FROM utilisateur LIMIT 1');
      final v = Enregistrement(
          table: 'visite',
          id: nouvelId(),
          version: 1,
          versionBase: 1,
          createdAt: m,
          updatedAt: m,
          etablissementId: e.id,
          donnees: {
            'eleve_id': enfant.id,
            'agent_id': agents.first['id'],
            'date_visite': a.debut,
            'statut': 'valide',
            'type_visite': 'systematique',
            'hpv': 'non_fait',
            'hpv_motif': 'refus_parents',
          });
      try {
        await depot.transaction((tx) => tx.ecrire(v));
        final jeu = await SourceStatistiquesPoste(depot).charger(a);
        final vs = jeu.visites.singleWhere((x) => x.id == v.id);
        expect((vs.hpv, vs.hpvMotif), (StatutHpv.nonFait, MotifHpv.refusParents));
        expect((await r.visites(enfant.id)).single.hpv, StatutHpv.nonFait);
        await expectLater(
            depot.requete("UPDATE visite SET hpv = 'peut_etre' WHERE id = CAST(@id AS uuid)", {'id': v.id}), throwsA(anything));
      } finally {
        await depot.requete('DELETE FROM visite WHERE id = CAST(@id AS uuid)', {'id': v.id});
      }
    }, skip: ignorer);

    test('effectifs saisis sur PostgreSQL (migration 070) et établissement sans code', () async {
      final a = (await r.anneeCourante())!;
      final admin = Droits(utilisateurId: nouvelId(), role: RoleCode.admin, permissions: matriceParDefaut[RoleCode.admin]!);
      final e = await g.creerEtablissement(admin, {'nom': 'Collège sans code ${nouvelId().substring(30)}', 'type': 'secondaire',
        'statut': 'public'});
      expect((e.donnees['code'] as String).startsWith('COLSANCOD'), isTrue);
      final sixieme = await g.creerClasse(admin, etablissementId: e.id, anneeScolaireId: a.id, libelle: '6ème 1');
      final troisieme = await g.creerClasse(admin, etablissementId: e.id, anneeScolaireId: a.id, libelle: '3ème 2');
      await g.enregistrerEffectifs(admin, [
        EffectifSaisi(sixieme.id, garcons: 30, filles: 28, visitesGarcons: 25, visitesFilles: 20),
        EffectifSaisi(troisieme.id, garcons: 22, filles: 24, visitesGarcons: 20, visitesFilles: 24, aptitudeGarcons: 18,
            aptitudeFilles: 19),
      ]);
      final classes = {for (final c in await r.classes(e.id, a)) c.libelle: c};
      expect((classes['6ème 1']!.effectifsSaisis, classes['6ème 1']!.saisi!.effectif, classes['3ème 2']!.aptitude),
          (true, 58, true));
      final etab = (await r.etablissements(a)).singleWhere((x) => x.id == e.id);
      expect((etab.effectif, etab.effectifSaisi, etab.effectifTotal, etab.examinesTotal), (0, 104, 104, 89));
      final jeu = await SourceStatistiquesPoste(depot).charger(a);
      final s = calculerStatistiques(jeu, FiltreStatistiques(etablissementId: e.id));
      expect((s.generale.effectif, s.generale.garcons, s.generale.examines, s.nbClassesSaisies), (104, 52, 89, 2));
      final apt = calculerStatistiques(jeu, FiltreStatistiques(etablissementId: e.id, typeVisite: TypeVisite.aptitude));
      expect((apt.generale.effectif, apt.generale.examines), (46, 37));
      await expectLater(
          depot.requete('UPDATE effectif_classe SET garcons = -1 WHERE classe_id = CAST(@c AS uuid)', {'c': sixieme.id}),
          throwsA(anything));
    }, skip: ignorer);

    test('création d\'établissement et de classe, rediffusion par établissement', () async {
      final a = (await r.anneeCourante())!;
      final e = await g.creerEtablissement(chef, {'nom': 'École PG', 'code': 'PG-${nouvelId().substring(30)}', 'type': 'primaire', 'statut': 'public'});
      final c = await g.creerClasse(chef, etablissementId: e.id, anneeScolaireId: a.id, libelle: 'CP1');
      final portee = await depot.transaction((tx) => tx.parPortee('classe', e.id));
      expect(portee.map((x) => x.id), [c.id]);
      expect((await r.classes(e.id, a)).single.libelle, 'CP1');
      await g.archiverClasse(chef, c.id);
      expect(await r.classes(e.id, a), isEmpty);
    }, skip: ignorer);
  });
}
