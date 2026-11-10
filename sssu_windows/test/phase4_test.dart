import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:sssu_windows/donnees/depot_postgres.dart';
import 'package:sssu_windows/donnees/migrations.dart';
import 'package:sssu_windows/donnees/stockage_photos.dart';

/// Phase 4 côté poste : réception des photographies dans le stockage chiffré
/// du poste, sur la base en mémoire puis sur PostgreSQL ; conflits sur PostgreSQL.
void main() {
  final horloge = HorlogeFixe(DateTime.utc(2026, 11, 10, 8));
  late Directory dossier;
  setUp(() async => dossier = await Directory.systemTemp.createTemp('sssu_p4'));
  tearDown(() => dossier.delete(recursive: true));

  Enregistrement nouveau(String table, Map<String, Object?> d, {String? etab, String? id}) => Enregistrement(
      table: table,
      id: id ?? nouvelId(),
      version: 1,
      versionBase: 1,
      createdAt: horloge.maintenant(),
      updatedAt: horloge.maintenant(),
      etablissementId: etab,
      donnees: d);

  /// Utilisateur, appareil affecté à [etab], visite, consentement et photo de [eleve].
  Future<({String appareil, Enregistrement photo})> preparer(DepotServeur depot, String etab, String eleve,
      List<int> jpeg, {required String roleId}) async {
    final appareil = nouvelId();
    late Enregistrement photo;
    await depot.transaction((tx) async {
      final u = nouveau('utilisateur', {'identifiant': 'p4-${nouvelId().substring(28)}', 'nom': 'AGENT P4', 'role_id': roleId});
      await tx.ecrire(u);
      await tx.ecrire(nouveau('appareil', {'nom': 'Tel P4', 'bloque': false}, id: appareil));
      await tx.ecrire(nouveau('appareil_etablissement', {'appareil_id': appareil, 'etablissement_id': etab}));
      final v = nouveau('visite', {'eleve_id': eleve, 'agent_id': u.id, 'date_visite': '2026-11-10'}, etab: etab);
      await tx.ecrire(v);
      final c = nouveau(
          'consentement',
          {
            'eleve_id': eleve,
            'visite_id': v.id,
            'obtenu': true,
            'forme': 'oral',
            'nom_repondant': 'Parent fictif',
            'date_consentement': '2026-11-10'
          },
          etab: etab);
      await tx.ecrire(c);
      photo = nouveau(
          'photo',
          {
            'visite_id': v.id,
            'eleve_id': eleve,
            'auteur_id': u.id,
            'consentement_id': c.id,
            'chemin_chiffre': 'photos/x.enc',
            'empreinte_sha256': sha256Hex(jpeg),
            'taille_octets': jpeg.length,
            'pris_le': '2026-11-10T09:00:00.000Z',
          },
          etab: etab);
      await tx.ecrire(photo);
    });
    return (appareil: appareil, photo: photo);
  }

  Future<void> envoyer(ServiceFichiers f, String appareil, String id, List<int> jpeg) async {
    final n = (jpeg.length + tailleMorceau - 1) ~/ tailleMorceau;
    for (var i = n - 1; i >= 0; i--) {
      final fin = (i + 1) * tailleMorceau;
      await f.recevoirMorceau(appareil, 'photo', id, i, jpeg.sublist(i * tailleMorceau, fin > jpeg.length ? jpeg.length : fin));
    }
    await f.terminer(appareil, 'photo', id, n);
  }

  test('réception par morceaux dans le stockage chiffré du poste (base en mémoire)', () async {
    final depot = DepotServeurMemoire();
    final etab = nouvelId();
    final eleve = nouvelId();
    await depot.transaction((tx) async {
      await tx.ecrire(nouveau('etablissement', {'nom': 'École', 'code': 'E', 'type': 'primaire', 'statut': 'public'},
          etab: etab, id: etab));
      await tx.ecrire(nouveau('eleve', {'nom': 'KOUASSI', 'prenoms': 'Aya', 'sexe': 'F'}, etab: etab, id: eleve));
    });
    final jpeg = List<int>.generate(tailleMorceau + 1234, (i) => (i * 13) % 256);
    final p = await preparer(depot, etab, eleve, jpeg, roleId: nouvelId());
    final stockage = await StockagePhotosPoste.ouvrir(dossier);
    final f = ServiceFichiers(depot: depot, stockage: stockage, horloge: horloge);
    await envoyer(f, p.appareil, p.photo.id, jpeg);
    expect(await stockage.lire(p.photo.id), jpeg);
    expect(depot.lireDirect('photo', p.photo.id)!.donnees['statut_transfert'], 'confirme');
    expect((await f.etat(p.appareil, 'photo', p.photo.id)).complet, isTrue);
  });

  final url = Platform.environment['SSSU_PG_TEST_URL'];
  final ignorer = url == null ? 'SSSU_PG_TEST_URL non définie' : null;

  group('PostgreSQL', () {
    late DepotPostgres depot;
    late String etab;
    late String eleve;
    late String roleId;

    setUpAll(() async {
      if (url == null) return;
      depot = await DepotPostgres.ouvrir(ConfigPostgres.depuisUrl(url));
      await MigrationsPoste(depot, Directory('../sql/postgres')).appliquer();
      final l = await depot.requete(
          'SELECT CAST(e.id AS text) AS eleve, CAST(s.scope AS text) AS etab FROM eleve e '
          "JOIN sync_changement s ON s.table_name = 'eleve' AND s.record_id = e.id "
          'WHERE e.deleted_at IS NULL AND s.scope IS NOT NULL ORDER BY s.seq LIMIT 1');
      eleve = l.single['eleve'] as String;
      etab = l.single['etab'] as String;
      roleId = (await depot.requete("SELECT CAST(id AS text) AS id FROM role WHERE code = 'agent'")).single['id'] as String;
    });
    tearDownAll(() async {
      if (url != null) await depot.fermer();
    });

    test('photo reçue : fichier chiffré, statut « confirme », même version', () async {
      final jpeg = List<int>.generate(3 * tailleMorceau - 7, (i) => (i * 31) % 256);
      final p = await preparer(depot, etab, eleve, jpeg, roleId: roleId);
      final stockage = await StockagePhotosPoste.ouvrir(dossier);
      final f = ServiceFichiers(depot: depot, stockage: stockage, horloge: horloge);
      expect((await f.etat(p.appareil, 'photo', p.photo.id)).complet, isFalse);
      await envoyer(f, p.appareil, p.photo.id, jpeg);
      final e = (await depot.transaction((tx) => tx.lire('photo', p.photo.id)))!;
      expect((e.version, e.donnees['statut_transfert']), (1, 'confirme'));
      expect(await stockage.lire(p.photo.id), jpeg);
      // Un autre appareil, non affecté à l'établissement, n'a pas accès.
      await expectLater(f.etat(nouvelId(), 'photo', p.photo.id),
          throwsA(isA<ErreurProtocole>().having((x) => x.code, 'code', 'etablissement_non_affecte')));
    }, skip: ignorer);

    test('conflit lu depuis PostgreSQL et clos par le Médecin-Chef', () async {
      final conflits = ServiceConflits(depot: depot, horloge: horloge);
      final chef =
          Droits(utilisateurId: nouvelId(), role: RoleCode.medecinChef, permissions: matriceParDefaut[RoleCode.medecinChef]!);
      final appareilVersion = nouveau('inscription', {'eleve_id': eleve, 'statut': 'inscrit'}, etab: etab);
      final c = nouveau('conflit', {
        'table_cible': 'inscription',
        'enregistrement_id': appareilVersion.id,
        'type': TypesConflit.unicite,
        'version_serveur': null,
        'version_appareil': appareilVersion.versJson(),
        'statut': 'ouvert',
      });
      await depot.transaction((tx) => tx.ecrire(c));
      final ouverts = await conflits.ouverts();
      final lu = ouverts.firstWhere((x) => x.id == c.id);
      expect(Enregistrement.depuisJson(Map<String, Object?>.from(lu.donnees['version_appareil']! as Map)).id,
          appareilVersion.id);
      await conflits.fermer(c.id, acteur: chef);
      expect((await conflits.ouverts()).where((x) => x.id == c.id), isEmpty);
    }, skip: ignorer);
  });
}
