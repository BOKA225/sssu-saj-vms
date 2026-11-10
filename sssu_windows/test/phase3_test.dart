import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:sssu_windows/donnees/depot_postgres.dart';
import 'package:sssu_windows/donnees/migrations.dart';
import 'package:sssu_windows/donnees/requetes_poste.dart';
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
      final classes = await r.classes(etabs.first.id, a);
      expect(classes.first.effectif, greaterThan(0));
      final eleves = await r.eleves(a, classeId: classes.first.id);
      expect(eleves.length, classes.first.effectif);
      expect(await r.eleves(a, texte: eleves.first.nom), isNotEmpty);
      expect(await r.inscriptions(eleves.first.id), isNotEmpty);
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
