import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sssu_core/sssu_core.dart';
import 'package:sssu_windows/donnees/depot_postgres.dart';
import 'package:sssu_windows/donnees/migrations.dart';
import 'package:sssu_windows/donnees/requetes_poste.dart';
import 'package:sssu_windows/sauvegarde/archive_chiffree.dart';
import 'package:sssu_windows/sauvegarde/service_sauvegarde.dart';
import 'package:sssu_windows/securite/protection_cles.dart';

/// Phase 6 côté poste : archive chiffrée, planification, migrations,
/// recherche sans accents, sauvegarde puis restauration réelles sur
/// PostgreSQL (pg_dump et pg_restore dans le PATH ou dans SSSU_PG_BIN).
void main() {
  late Directory dossier;
  setUp(() async => dossier = await Directory.systemTemp.createTemp('sssu_p6'));
  tearDown(() async {
    if (await dossier.exists()) await dossier.delete(recursive: true);
  });

  group('Archive chiffrée', () {
    final cle = List<int>.generate(32, (i) => i * 7 % 256);
    final aleatoire = Random(42);

    Future<File> archive(Map<String, List<int>> entrees) async {
      final f = File(p.join(dossier.path, 'a.sssubak'));
      final e = await EcrivainArchive.creer(f, cle, {'format': 1});
      for (final x in entrees.entries) {
        if (x.value.length > 100000) {
          final src = File(p.join(dossier.path, 'source.bin'))..writeAsBytesSync(x.value);
          await e.ajouterFichier(x.key, src);
        } else {
          await e.ajouterOctets(x.key, x.value);
        }
      }
      await e.fermer();
      return f;
    }

    test('aller-retour : plusieurs blocs, fichier vide, sous-dossiers', () async {
      final gros = List<int>.generate(tailleBloc * 3 + 12345, (_) => aleatoire.nextInt(256));
      final f = await archive({'manifeste.json': [123, 125], 'vide.bin': [], 'photos/a.enc': gros});
      expect((await lireEnteteArchive(f))['format'], 1);
      final dest = Directory(p.join(dossier.path, 'x'));
      final noms = await extraireArchive(f, cle, dest);
      expect(noms, ['manifeste.json', 'vide.bin', 'photos/a.enc']);
      expect(File(p.join(dest.path, 'photos', 'a.enc')).readAsBytesSync(), gros);
      expect(File(p.join(dest.path, 'vide.bin')).lengthSync(), 0);
    });

    test('clé fausse, octet modifié, archive tronquée : détectés', () async {
      final f = await archive({'a': List<int>.generate(tailleBloc + 10, (i) => i % 256)});
      final dest = Directory(p.join(dossier.path, 'x'));
      await expectLater(extraireArchive(f, List<int>.filled(32, 1), dest), throwsA(isA<ArchiveInvalide>()));
      final octets = f.readAsBytesSync();
      final modifie = File(p.join(dossier.path, 'm.sssubak'))..writeAsBytesSync([...octets]..[octets.length - 40] ^= 1);
      await expectLater(extraireArchive(modifie, cle, dest), throwsA(isA<ArchiveInvalide>()));
      final tronque = File(p.join(dossier.path, 't.sssubak'))..writeAsBytesSync(octets.sublist(0, octets.length - 100));
      await expectLater(extraireArchive(tronque, cle, dest), throwsA(isA<ArchiveInvalide>()));
      // Bloc final supprimé (coupure nette entre deux blocs) : détecté aussi.
      final dernierBlocRetire = File(p.join(dossier.path, 'b.sssubak'))
        ..writeAsBytesSync(octets.sublist(0, octets.length - (5 + 12 + 16 + 30)));
      await expectLater(extraireArchive(dernierBlocRetire, cle, dest), throwsA(isA<ArchiveInvalide>()));
    });

    test('nom de fichier dangereux refusé à l\'extraction', () async {
      final f = await archive({'../hors.txt': [1]});
      await expectLater(extraireArchive(f, cle, Directory(p.join(dossier.path, 'x'))), throwsA(isA<ArchiveInvalide>()));
      expect(File(p.join(dossier.path, 'hors.txt')).existsSync(), isFalse);
    });

    test('phrase de passe : dérivation reproductible et contrôle', () async {
      final d = DerivationCle(sel: List<int>.filled(16, 3), memoireKio: 1024, iterations: 1);
      final k1 = await d.deriver('une phrase de passe');
      final k2 = await DerivationCle.depuisJson(d.versJson()).deriver('une phrase de passe');
      expect(k1, k2);
      final c = await controlePhrase(k1);
      expect(await verifierControle(k1, c), isTrue);
      expect(await verifierControle(await d.deriver('une autre phrase'), c), isFalse);
      expect(ServiceSauvegarde.controlerPhrase('court'), isNotNull);
      expect(ServiceSauvegarde.controlerPhrase('trois mots suffisent ici'), isNull);
    });
  });

  test('échéance de la sauvegarde automatique', () {
    final r = ReglagesSauvegarde(dossier: 'x', heure: 13, minute: 0, derivation: const {'algo': 'argon2id'}, controle: 'c');
    final j = DateTime(2026, 11, 10);
    expect(ServiceSauvegarde.echeance(r, j.add(const Duration(hours: 12, minutes: 59))), isFalse);
    expect(ServiceSauvegarde.echeance(r, j.add(const Duration(hours: 13, minutes: 1))), isTrue);
    r.derniereReussie = j.add(const Duration(hours: 13, minutes: 2));
    expect(ServiceSauvegarde.echeance(r, j.add(const Duration(hours: 18))), isFalse, reason: 'déjà faite aujourd\'hui');
    expect(ServiceSauvegarde.echeance(r, j.add(const Duration(days: 1, hours: 9))), isFalse);
    expect(ServiceSauvegarde.echeance(r, j.add(const Duration(days: 2, hours: 8))), isTrue, reason: 'rattrapage');
    r.derniereTentative = j.add(const Duration(days: 2, hours: 7, minutes: 30));
    expect(ServiceSauvegarde.echeance(r, j.add(const Duration(days: 2, hours: 8))), isFalse, reason: 'échec récent');
    r.active = false;
    expect(ServiceSauvegarde.echeance(r, j.add(const Duration(days: 3, hours: 14))), isFalse);
  });

  test('clé protégée : écriture puis relecture', () async {
    final f = File(p.join(dossier.path, 'cle.bin'));
    await ecrireCle(f, [1, 2, 3], ProtectionCles.systeme());
    expect(await lireCle(f, ProtectionCles.systeme()), [1, 2, 3]);
  });

  final url = Platform.environment['SSSU_PG_TEST_URL'];
  final ignorer = url == null ? 'SSSU_PG_TEST_URL non définie' : null;

  group('PostgreSQL', () {
    late ConfigPostgres config;
    late DepotPostgres depot;
    setUpAll(() async {
      if (url == null) return;
      config = ConfigPostgres.depuisUrl(url);
      depot = await DepotPostgres.ouvrir(config);
      await MigrationsPoste(depot, Directory('../sql/postgres')).appliquer();
    });
    tearDownAll(() async {
      if (url != null) await depot.fermer();
    });

    test('migrations idempotentes, génération, recherche sans accents', () async {
      final m = await MigrationsPoste(depot, Directory('../sql/postgres')).appliquer();
      expect(m.map((x) => x.nom), containsAll(['001_schema.sql', '002_referentiels.sql', '020_phase6.sql']));
      expect(m.where((x) => x.appliqueeMaintenant), isEmpty);
      expect(m.map((x) => x.nom), isNot(contains('010_initialiser_journal_sync.sql')));
      final g = await depot.generation();
      await depot.renouvelerGeneration();
      expect(await depot.generation(), isNot(g));
      final annee = (await RequetesPoste(depot).anneeCourante())!;
      final r = await RequetesPoste(depot).eleves(annee, texte: 'kouame');
      expect(r.any((e) => e.nom == 'KOUAMÉ'), isTrue, reason: '« kouame » trouve « KOUAMÉ »');
    }, skip: ignorer);

    test('sauvegarde puis restauration réelles', () async {
      final service = ServiceSauvegarde(
        postgres: config,
        dossierBin: Platform.environment['SSSU_PG_BIN'],
        dossierDonnees: dossier,
        depot: depot,
        protection: const SansProtection(),
      );
      final admin = Droits(utilisateurId: nouvelId(), role: RoleCode.admin, permissions: matriceParDefaut[RoleCode.admin]!);
      await expectLater(service.sauvegarder(), throwsA(isA<ErreurSauvegarde>()), reason: 'phrase non définie');
      await expectLater(
          service.definirPhrase(Droits(utilisateurId: 'x', role: RoleCode.medecinChef, permissions: const {}), 'a b c d e f g h'),
          throwsA(isA<ErreurSauvegarde>()));
      await service.definirPhrase(admin, 'phrase de passe des sauvegardes 2026');
      Directory(p.join(dossier.path, 'photos')).createSync();
      final photo = '${nouvelId()}.enc';
      File(p.join(dossier.path, 'photos', photo)).writeAsBytesSync(List<int>.filled(5000, 9));
      File(p.join(dossier.path, 'cle_photos.bin')).writeAsBytesSync(List<int>.filled(32, 4));

      final s = await service.sauvegarder();
      expect(s.photos, 1);
      expect((await service.sauvegardes()).single.path, s.fichier.path);
      final manifeste = await service.verifier(s.fichier, 'phrase de passe des sauvegardes 2026');
      expect(manifeste['photos'], 1);
      await expectLater(service.verifier(s.fichier, 'mauvaise phrase de passe'), throwsA(isA<ErreurSauvegarde>()));

      // Après la sauvegarde : un paramètre modifié et la photo effacée.
      final avant = await depot.generation();
      await depot.requete("UPDATE parametre SET valeur = 'MODIFIÉ' WHERE cle = 'entete_ligne_1'");
      File(p.join(dossier.path, 'photos', photo)).deleteSync();

      await service.restaurer(s.fichier, 'phrase de passe des sauvegardes 2026', admin,
          arreterPoste: () => depot.fermer(), sauvegardeDeSecurite: true);
      depot = await DepotPostgres.ouvrir(config);
      final valeur = (await depot.requete("SELECT valeur FROM parametre WHERE cle = 'entete_ligne_1'")).single['valeur'];
      expect(valeur, 'MINISTÈRE EN CHARGE DE LA SANTÉ');
      expect(await depot.generation(), isNot(avant), reason: 'les téléphones feront une reprise');
      expect(File(p.join(dossier.path, 'photos', photo)).readAsBytesSync(), List<int>.filled(5000, 9));
      expect((await service.sauvegardes()).any((f) => f.path.contains('avant_restauration')), isTrue);
      final trace = await depot.requete("SELECT COUNT(*) AS n FROM journal_audit WHERE action = 'restauration'");
      expect((trace.single['n'] as num).toInt(), greaterThan(0));
    }, skip: ignorer, timeout: const Timeout(Duration(minutes: 5)));
  });
}
