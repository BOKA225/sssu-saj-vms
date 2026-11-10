import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

import 'outils/environnement.dart';

void main() {
  late Environnement env;
  late String tel;

  setUp(() async {
    env = await Environnement.creer();
    tel = (await env.appairer('Tel', [env.etabA])).appareilId;
  });

  Enregistrement nouveau(String table, Map<String, Object?> d, {String? etab, String? id}) {
    final m = env.horloge.maintenant();
    return Enregistrement(
        table: table,
        id: id ?? nouvelId(),
        version: 1,
        versionBase: 1,
        createdAt: m,
        updatedAt: m,
        updatedBy: env.agent1.id,
        etablissementId: etab ?? env.etabA,
        donnees: d);
  }

  Future<Enregistrement> photo(List<int> contenu, {String? etab, String? eleve}) => env.depot.transaction((tx) async {
        final v = nouveau('visite',
            {'eleve_id': eleve ?? env.eleveA, 'agent_id': env.agent1.id, 'date_visite': '2026-11-10', 'statut': 'en_attente'},
            etab: etab);
        await tx.ecrire(v);
        final c = nouveau('consentement',
            {'eleve_id': eleve ?? env.eleveA, 'visite_id': v.id, 'obtenu': true, 'forme': 'oral', 'nom_repondant': 'P', 'date_consentement': '2026-11-10'},
            etab: etab);
        await tx.ecrire(c);
        final p = nouveau(
            'photo',
            {
              'visite_id': v.id,
              'eleve_id': eleve ?? env.eleveA,
              'auteur_id': env.agent1.id,
              'consentement_id': c.id,
              'chemin_chiffre': 'x',
              'empreinte_sha256': sha256Hex(contenu),
              'taille_octets': contenu.length,
              'pris_le': '2026-11-10T09:00:00.000Z',
              'statut_transfert': 'en_attente',
            },
            etab: etab);
        await tx.ecrire(p);
        return p;
      });

  Matcher code(String c) => throwsA(isA<ErreurProtocole>().having((e) => e.code, 'code', c));

  group('Réception des fichiers', () {
    test('morceaux dans le désordre, reprise après interruption, confirmation idempotente', () async {
      final contenu = List<int>.generate(tailleMorceau * 2 + 10, (i) => i % 251);
      final p = await photo(contenu);
      final f = env.fichiers;
      await f.recevoirMorceau(tel, 'photo', p.id, 2, contenu.sublist(2 * tailleMorceau));
      await f.recevoirMorceau(tel, 'photo', p.id, 0, contenu.sublist(0, tailleMorceau));
      expect((await f.etat(tel, 'photo', p.id)).morceauxRecus, [0, 2]);
      await expectLater(f.terminer(tel, 'photo', p.id, 3), code('incomplet'));
      await f.recevoirMorceau(tel, 'photo', p.id, 1, contenu.sublist(tailleMorceau, 2 * tailleMorceau));
      await f.terminer(tel, 'photo', p.id, 3);
      expect(env.stockage.fichiers[p.id], contenu);
      expect((await f.etat(tel, 'photo', p.id)).complet, isTrue);
      await f.terminer(tel, 'photo', p.id, 3); // confirmation perdue puis renvoyée
    });

    test('fichier altéré : refusé, à renvoyer', () async {
      final p = await photo([1, 2, 3]);
      await env.fichiers.recevoirMorceau(tel, 'photo', p.id, 0, [1, 2, 4]);
      await expectLater(env.fichiers.terminer(tel, 'photo', p.id, 1), code('empreinte'));
      expect(env.stockage.fichiers, isEmpty);
      expect((await env.fichiers.etat(tel, 'photo', p.id)).morceauxRecus, isEmpty);
    });

    test('contrôles d\'accès : photo inconnue, autre établissement, table sans fichier, morceau trop gros', () async {
      await expectLater(env.fichiers.etat(tel, 'photo', nouvelId()), code('inconnu'));
      final autre = await photo([1], etab: env.etabB, eleve: env.eleveB);
      await expectLater(env.fichiers.etat(tel, 'photo', autre.id), code('etablissement_non_affecte'));
      await expectLater(env.fichiers.etat(tel, 'eleve', env.eleveA), code('table'));
      final p = await photo([1]);
      await expectLater(
          env.fichiers.recevoirMorceau(tel, 'photo', p.id, 0, List<int>.filled(tailleMorceau + 1, 0)), code('morceau'));
    });
  });

  group('Résolution des conflits', () {
    late Droits chef;
    setUp(() async => chef = await env.droits(env.chef));

    test('doublon d\'élève : fusion des dossiers, conflit clos', () async {
      // Un téléphone crée un second dossier avec le même matricule.
      final m = env.horloge.maintenant();
      final doublon = Enregistrement(
        table: 'eleve',
        id: nouvelId(),
        version: 1,
        versionBase: 0,
        createdAt: m,
        updatedAt: m,
        updatedBy: env.medecin.id,
        etablissementId: env.etabA,
        donnees: {'matricule': '12345678A', 'nom': 'KOUASSI', 'prenoms': 'Aya', 'sexe': 'F', 'telephone_contact': '0707070707'},
      );
      await env.sync.recevoirEnvoi(tel, DemandeEnvoi(enregistrements: [doublon]));
      final v = nouveau('visite', {'eleve_id': doublon.id, 'agent_id': env.agent1.id, 'date_visite': '2026-11-10', 'statut': 'en_attente'});
      await env.depot.transaction((tx) => tx.ecrire(v));
      final conflit = env.depot.tousDirect('conflit').single;
      expect(conflit.donnees['type'], TypesConflit.doublonEleve);

      final garde = await env.conflits.fusionnerEleves(garderId: env.eleveA, absorberId: doublon.id, acteur: chef);
      expect(garde.donnees['telephone_contact'], '0707070707', reason: 'identité complétée');
      expect(env.depot.lireDirect('eleve', doublon.id)!.supprime, isTrue);
      expect(env.depot.lireDirect('visite', v.id)!.donnees['eleve_id'], env.eleveA);
      expect(env.depot.lireDirect('conflit', conflit.id)!.donnees['statut'], 'resolu');
      // Les téléphones reçoivent la fusion comme une décision sur conflit.
      final r = await env.sync.preparerReception(tel, 0, limite: 10000);
      expect(r.changements.where((c) => c.enregistrement.id == v.id).last.resolutionConflit, isTrue);
    });

    test('doublon de visite : archivage de l\'une, clôture', () async {
      final v1 = nouveau('visite', {'eleve_id': env.eleveA, 'agent_id': env.agent1.id, 'date_visite': '2026-11-10', 'statut': 'en_attente'});
      await env.depot.transaction((tx) => tx.ecrire(v1));
      final m = env.horloge.maintenant();
      final v2 = Enregistrement(
          table: 'visite',
          id: nouvelId(),
          version: 1,
          versionBase: 0,
          createdAt: m,
          updatedAt: m,
          updatedBy: env.agent2.id,
          etablissementId: env.etabA,
          donnees: {'eleve_id': env.eleveA, 'agent_id': env.agent2.id, 'date_visite': '2026-11-10', 'statut': 'en_attente'});
      await env.sync.recevoirEnvoi(tel, DemandeEnvoi(enregistrements: [v2]));
      final conflit = env.depot.tousDirect('conflit').single;
      await env.conflits.archiverVisite(conflit.id, v2.id, acteur: chef);
      expect(env.depot.lireDirect('visite', v2.id)!.supprime, isTrue);
      expect(env.depot.lireDirect('visite', v1.id)!.supprime, isFalse);
      expect(env.depot.lireDirect('conflit', conflit.id)!.donnees['statut'], 'resolu');
    });

    test('doublon d\'inscription : clôture seulement ; « garder » est refusé pour ce type', () async {
      final m = env.horloge.maintenant();
      final ins = Enregistrement(
          table: 'inscription',
          id: nouvelId(),
          version: 1,
          versionBase: 0,
          createdAt: m,
          updatedAt: m,
          updatedBy: env.medecin.id,
          etablissementId: env.etabA,
          donnees: {'eleve_id': env.eleveA, 'classe_id': env.classeA, 'annee_scolaire_id': env.anneeId, 'statut': 'inscrit'});
      await env.sync.recevoirEnvoi(tel, DemandeEnvoi(enregistrements: [ins]));
      final conflit = env.depot.tousDirect('conflit').single;
      await expectLater(env.conflits.resoudre(conflit.id, choix: ChoixConflit.appareil, acteur: chef), throwsStateError);
      await expectLater(env.conflits.fermer(conflit.id, acteur: await env.droits(env.agent1)), throwsStateError);
      await env.conflits.fermer(conflit.id, acteur: chef);
      expect(env.depot.lireDirect('conflit', conflit.id)!.donnees['statut'], 'resolu');
      expect(env.depot.lireDirect('inscription', ins.id), isNull, reason: 'jamais enregistrée sur le poste');
    });
  });

  test('QR code avec adresse Internet facultative', () {
    const qr = ContenuQrAppairage(
        urlServeur: 'https://192.168.1.10:8443',
        empreinteCertificat: 'ab',
        appareilId: 'a',
        nomAppareil: 'n',
        code: 'C',
        urlInternet: 'https://poste.exemple.ci:8443');
    expect(ContenuQrAppairage.depuisTexte(qr.versTexte()).urlInternet, 'https://poste.exemple.ci:8443');
  });
}
