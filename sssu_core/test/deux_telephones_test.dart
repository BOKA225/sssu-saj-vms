/// Test de bout en bout : deux téléphones et le poste central, en HTTP réel
/// sur la machine locale. Vérifie l'appairage, l'envoi par lots, les accusés,
/// la réception, la détection d'un conflit sans perte de données et sa
/// résolution par le Médecin-Chef.
library;

import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

import 'outils/environnement.dart';

class _Telephone {
  final String nom;
  final DepotLocalMemoire base;
  final ClientSynchronisation client;
  _Telephone(this.nom, this.base, this.client);

  Future<RapportSync> synchroniser() => client.synchroniser();
}

void main() {
  late Environnement env;
  late HttpServer serveur;
  late Uri adresse;

  setUp(() async {
    env = await Environnement.creer();
    final api = construireApi(
        sync: env.sync, appairage: env.appairage, jetons: env.jetons, fichiers: env.fichiers, horloge: env.horloge);
    serveur = await shelf_io.serve(api, InternetAddress.loopbackIPv4, 0);
    adresse = Uri.parse('http://${serveur.address.host}:${serveur.port}');
  });

  tearDown(() => serveur.close(force: true));

  /// Appairage complet tel qu'il se fait sur le terrain : QR code préparé sur
  /// le poste central, lu par le téléphone, qui génère sa clé et s'enregistre.
  Future<_Telephone> nouveauTelephone(String nom, Utilisateur titulaire) async {
    final qr = ContenuQrAppairage.depuisTexte((await env.appairage.preparer(
      acteur: await env.droits(env.admin),
      nomAppareil: nom,
      titulaireId: titulaire.id,
      etablissementIds: [env.etabA],
      urlServeur: adresse.toString(),
      empreinteCertificat: null,
    ))
        .versTexte());
    final transport = TransportHttp(Uri.parse(qr.urlServeur));
    final identite = await IdentiteAppareil.generer(qr.appareilId);
    final rep = await transport.appairer(
        DemandeAppairage(appareilId: qr.appareilId, code: qr.code, clePublique: await identite.clePubliqueBase64()));
    expect(rep.etablissements, [env.etabA]);
    final base = DepotLocalMemoire(horloge: env.horloge, appareilId: qr.appareilId);
    return _Telephone(nom, base,
        ClientSynchronisation(depot: base, transport: transport, identite: identite, horloge: env.horloge, tailleLot: 3));
  }

  test('état du poste central', () async {
    expect(await TransportHttp(adresse).etat(), isTrue);
  });

  test('deux téléphones : envoi, réception, conflit sans perte, résolution', () async {
    final telA = await nouveauTelephone('Téléphone A', env.agent1);
    final telB = await nouveauTelephone('Téléphone B', env.agent2);

    // 1. Première synchronisation : chaque téléphone reçoit les référentiels,
    //    les comptes et les élèves de l'établissement A uniquement.
    for (final t in [telA, telB]) {
      final r = await t.synchroniser();
      expect(r.recus, greaterThan(0));
      expect(t.base.lire('eleve', env.eleveA), isNotNull);
      expect(t.base.lire('eleve', env.eleveB), isNull, reason: 'élève d\'un autre établissement');
      expect(t.base.lire('utilisateur', env.agent1.id)!.donnees['hash_mot_de_passe'], isNotNull,
          reason: 'connexion hors ligne possible');
    }

    // 2. Saisies hors ligne : 7 visites sur A (envoyées par lots de 3), 1 sur B.
    final visitesA = [
      for (var i = 0; i < 7; i++)
        telA.base.creer(
            'visite',
            {
              'eleve_id': env.eleveA,
              'agent_id': env.agent1.id,
              'date_visite': '2026-11-${(i + 1).toString().padLeft(2, '0')}',
              'statut': 'en_attente',
              'poids_kg': 30.0 + i,
            },
            utilisateurId: env.agent1.id,
            etablissementId: env.etabA)
    ];
    telB.base.creer(
        'visite',
        {'eleve_id': env.eleveA, 'agent_id': env.agent2.id, 'date_visite': '2026-11-01', 'statut': 'en_attente'},
        utilisateurId: env.agent2.id,
        etablissementId: env.etabA);

    // 3. Les deux téléphones modifient le même élève depuis la même version.
    telA.base.modifier('eleve', env.eleveA, {'telephone_contact': '0701020304'}, utilisateurId: env.agent1.id);
    telB.base.modifier('eleve', env.eleveA, {'nom': 'KOUASSY'}, utilisateurId: env.agent2.id);

    // 4. A synchronise en premier : tout est accepté.
    final rA = await telA.synchroniser();
    expect(rA.acceptes, 8);
    expect(rA.sansIncident, isTrue);
    for (final v in visitesA) {
      expect(env.depot.lireDirect('visite', v.id), isNotNull);
      expect(telA.base.ligne('visite', v.id)!.etat, EtatSync.synchronise);
    }
    expect(env.depot.lireDirect('eleve', env.eleveA)!.version, 2);

    // 5. B synchronise : sa visite est acceptée (doublon du même jour signalé),
    //    sa modification de l'élève est en conflit.
    final rB = await telB.synchroniser();
    expect(rB.acceptes, 1);
    expect(rB.conflits, 1);
    expect(telB.base.ligne('eleve', env.eleveA)!.etat, EtatSync.conflit);

    // Aucune perte : le poste central garde la version de A, la table des
    // conflits garde celle de B, et B conserve sa saisie localement.
    final serveur = env.depot.lireDirect('eleve', env.eleveA)!;
    expect(serveur.donnees['telephone_contact'], '0701020304');
    expect(serveur.donnees['nom'], 'KOUASSI');
    final conflits = env.depot.tousDirect('conflit');
    final conflitEleve = conflits.singleWhere((c) => c.donnees['table_cible'] == 'eleve');
    expect(conflitEleve.donnees['type'], TypesConflit.modificationConcurrente);
    expect((conflitEleve.donnees['version_appareil']! as Map)['donnees'], containsPair('nom', 'KOUASSY'));
    expect(conflits.where((c) => c.donnees['type'] == TypesConflit.doublonVisite), hasLength(1));
    expect(telB.base.lire('eleve', env.eleveA)!.donnees['nom'], 'KOUASSY');

    // B a reçu les visites de A ; A recevra celle de B.
    expect(telB.base.tous('visite'), hasLength(8));
    await telA.synchroniser();
    expect(telA.base.tous('visite'), hasLength(8));

    // 6. Une nouvelle synchronisation de B ne renvoie rien et ne perd rien.
    final rB2 = await telB.synchroniser();
    expect(rB2.envoyes, 0);
    expect(telB.base.lire('eleve', env.eleveA)!.donnees['nom'], 'KOUASSY');

    // 7. Le Médecin-Chef fusionne : nom corrigé par B, téléphone saisi par A.
    final retenu = await env.conflits.resoudre(conflitEleve.id,
        choix: ChoixConflit.fusion, acteur: await env.droits(env.chef), donneesFusion: {'nom': 'KOUASSY'});
    expect(retenu.version, 3);
    expect(retenu.donnees['nom'], 'KOUASSY');
    expect(retenu.donnees['telephone_contact'], '0701020304');

    // 8. Les deux téléphones reçoivent la décision.
    await telB.synchroniser();
    await telA.synchroniser();
    for (final t in [telA, telB]) {
      final l = t.base.ligne('eleve', env.eleveA)!;
      expect(l.etat, EtatSync.synchronise, reason: t.nom);
      expect(l.enregistrement.version, 3, reason: t.nom);
      expect(l.enregistrement.donnees['nom'], 'KOUASSY', reason: t.nom);
      expect(l.enregistrement.donnees['telephone_contact'], '0701020304', reason: t.nom);
    }
    expect(env.depot.lireDirect('conflit', conflitEleve.id)!.donnees['statut'], 'resolu');
  });

  test('photographie : données puis fichier par morceaux, empreinte vérifiée, copie locale effacée', () async {
    final tel = await nouveauTelephone('Téléphone P', env.agent1);
    await tel.synchroniser();
    final v = tel.base.creer('visite',
        {'eleve_id': env.eleveA, 'agent_id': env.agent1.id, 'date_visite': '2026-11-10', 'statut': 'en_attente'},
        utilisateurId: env.agent1.id, etablissementId: env.etabA);
    final c = tel.base.creer('consentement',
        {'eleve_id': env.eleveA, 'visite_id': v.id, 'obtenu': true, 'forme': 'oral', 'nom_repondant': 'Parent', 'date_consentement': '2026-11-10'},
        utilisateurId: env.agent1.id, etablissementId: env.etabA);
    // Photo de 1,2 Mo : trois morceaux.
    final jpeg = List<int>.generate(1200 * 1024, (i) => (i * 7) % 256);
    final p = tel.base.creer(
        'photo',
        {
          'visite_id': v.id,
          'eleve_id': env.eleveA,
          'auteur_id': env.agent1.id,
          'consentement_id': c.id,
          'chemin_chiffre': 'photos/x.enc',
          'empreinte_sha256': sha256Hex(jpeg),
          'taille_octets': jpeg.length,
          'pris_le': '2026-11-10T09:00:00.000Z',
          'statut_transfert': 'en_attente',
        },
        utilisateurId: env.agent1.id,
        etablissementId: env.etabA);
    tel.base.fichiers[p.id] = jpeg;

    final r = await tel.synchroniser();
    expect(r.acceptes, 3);
    expect(r.fichiers, 1);
    expect(env.stockage.fichiers[p.id], jpeg);
    expect(env.depot.lireDirect('photo', p.id)!.donnees['statut_transfert'], 'confirme');
    expect(tel.base.lire('photo', p.id)!.donnees['statut_transfert'], 'confirme');
    expect(tel.base.fichiers.containsKey(p.id), isFalse, reason: 'copie du téléphone effacée après confirmation');
    // Rien à renvoyer ensuite.
    expect((await tel.synchroniser()).fichiers, 0);
  });

  test('découverte du poste sur le réseau local', () async {
    final rep = await RepondeurDecouverte.demarrer(
        portHttps: 8443, empreinteCertificat: 'ab12', port: 48444, adresse: InternetAddress.loopbackIPv4);
    try {
      final postes = await decouvrirPostes(
          destination: InternetAddress.loopbackIPv4, port: 48444, duree: const Duration(milliseconds: 500));
      expect(postes.single.empreinteCertificat, 'ab12');
      expect(postes.single.url.toString(), 'https://127.0.0.1:8443');
    } finally {
      rep.arreter();
    }
  });

  test('accusé perdu : le renvoi ne crée pas de doublon', () async {
    final tel = await nouveauTelephone('Téléphone C', env.agent1);
    await tel.synchroniser();
    final v = tel.base.creer('visite',
        {'eleve_id': env.eleveA, 'agent_id': env.agent1.id, 'date_visite': '2026-11-10', 'statut': 'en_attente'},
        utilisateurId: env.agent1.id, etablissementId: env.etabA);

    // Envoi direct dont on « perd » la réponse : le téléphone ne marque rien.
    final transport = TransportHttp(adresse);
    final jeton = await transport.obtenirJeton(await tel.client.identite.demandeJeton(env.horloge));
    await transport.envoyer(jeton.jeton, DemandeEnvoi(enregistrements: [v]));
    expect(tel.base.ligne('visite', v.id)!.etat, EtatSync.enAttente);

    final r = await tel.synchroniser();
    expect(r.dejaRecus, 1);
    expect(env.depot.tousDirect('visite').where((x) => x.id == v.id), hasLength(1));
    expect(tel.base.ligne('visite', v.id)!.etat, EtatSync.synchronise);
  });

  test('modification locale pendant l\'envoi : reste à transmettre', () async {
    final tel = await nouveauTelephone('Téléphone D', env.agent1);
    await tel.synchroniser();
    final v = tel.base.creer('visite',
        {'eleve_id': env.eleveA, 'agent_id': env.agent1.id, 'date_visite': '2026-11-10', 'statut': 'en_attente'},
        utilisateurId: env.agent1.id, etablissementId: env.etabA);
    final envoye = (await tel.base.enAttente(limite: 10)).single;
    env.horloge.avancer(const Duration(seconds: 5));
    tel.base.modifier('visite', v.id, {'observations': 'ajout après envoi'}, utilisateurId: env.agent1.id);
    await tel.base.marquerSynchronise(envoye, 1);
    final l = tel.base.ligne('visite', v.id)!;
    expect(l.etat, EtatSync.enAttente);
    expect(l.enregistrement.versionBase, 1);
    expect(l.enregistrement.version, 2);
  });

  test('requêtes sans jeton ou mal formées : refusées proprement', () async {
    final client = HttpClient();
    Future<int> statut(String methode, String chemin, [String? corps]) async {
      final req = await client.openUrl(methode, adresse.resolve(chemin));
      if (corps != null) req.write(corps);
      final rep = await req.close();
      await rep.drain<void>();
      return rep.statusCode;
    }

    expect(await statut('GET', '/api/v1/sync/reception?curseur=0'), 401);
    expect(await statut('POST', '/api/v1/sync/envoi', '{}'), 401);
    expect(await statut('POST', '/api/v1/auth/jeton', 'pas du json'), 400);
    expect(await statut('POST', '/api/v1/auth/jeton', '{"appareil_id": 3}'), 400);
    expect(await statut('GET', '/api/v1/inconnu'), 404);
    client.close();
  });
}
