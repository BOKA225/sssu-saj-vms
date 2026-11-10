import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:sssu_mobile/data/base_locale.dart' hide Utilisateur, Eleve;
import 'package:sssu_mobile/data/depot_local_drift.dart';
import 'package:sssu_mobile/fichiers/stockage_chiffre.dart';

import 'outils/transport_direct.dart';

/// Phase 4 : transfert des photographies depuis la base SQLite réelle,
/// éléments refusés à vérifier et abandon d'une version jamais acceptée.
void main() {
  final horloge = HorlogeFixe(DateTime.utc(2026, 11, 10, 8));
  late BaseLocale db;
  late Directory dossier;
  late StockageChiffre fichiersTel;
  late DepotServeurMemoire serveur;
  late StockageFichiersMemoire stockagePoste;
  late DepotLocalDrift depot;
  late ClientSynchronisation client;
  late Utilisateur agent;
  late String etab;
  late String etabNonAffecte;
  late String eleve;

  setUp(() async {
    db = BaseLocale(NativeDatabase.memory(setup: (d) => d.execute('PRAGMA foreign_keys = ON;')));
    dossier = await Directory.systemTemp.createTemp('sssu_p4');
    fichiersTel = StockageChiffre(dossier, ChiffreurFichiers(List<int>.generate(32, (i) => 255 - i)));

    serveur = DepotServeurMemoire();
    await initialiserRoles(serveur, horloge: horloge);
    final auth = ServiceAuthentification(
        depot: DepotUtilisateursServeur(serveur, horloge: horloge),
        hacheur: HacheurMotDePasse(parametres: ParametresArgon2.tests),
        horloge: horloge);
    final admin = await auth.creerPremierAdministrateur(identifiant: 'admin', nom: 'ADMIN', motDePasse: 'Admin-2026');
    final droitsAdmin = await auth.droitsDe(admin);
    agent = await auth.creerUtilisateur(droitsAdmin,
        identifiant: 'agent1', nom: 'AGENT', role: RoleCode.agent, motDePasseTemporaire: 'Temp-2026');

    etab = nouvelId();
    etabNonAffecte = nouvelId();
    eleve = nouvelId();
    await serveur.transaction((tx) async {
      Enregistrement n(String t, String id, Map<String, Object?> d, String portee) => Enregistrement(
          table: t,
          id: id,
          version: 1,
          versionBase: 1,
          createdAt: horloge.maintenant(),
          updatedAt: horloge.maintenant(),
          etablissementId: portee,
          donnees: d);
      await tx.ecrire(n('etablissement', etab, {'nom': 'École A', 'code': 'A', 'type': 'primaire', 'statut': 'public'}, etab));
      await tx.ecrire(n('etablissement', etabNonAffecte,
          {'nom': 'École B', 'code': 'B', 'type': 'primaire', 'statut': 'public'}, etabNonAffecte));
      await tx.ecrire(n('eleve', eleve, {'nom': 'KOUASSI', 'prenoms': 'Aya', 'sexe': 'F'}, etab));
    });

    final appairage = ServiceAppairage(depot: serveur, horloge: horloge);
    final jetons = ServiceJetons(depot: serveur, horloge: horloge);
    stockagePoste = StockageFichiersMemoire();
    final transport = TransportDirect(ServiceSynchronisation(depot: serveur, horloge: horloge), appairage, jetons,
        fichiers: ServiceFichiers(depot: serveur, stockage: stockagePoste, horloge: horloge));
    final qr = await appairage.preparer(
        acteur: droitsAdmin, nomAppareil: 'Tel', etablissementIds: [etab], urlServeur: 'x', empreinteCertificat: null);
    final identite = await IdentiteAppareil.generer(qr.appareilId);
    await transport.appairer(
        DemandeAppairage(appareilId: qr.appareilId, code: qr.code, clePublique: await identite.clePubliqueBase64()));
    depot = DepotLocalDrift(db, horloge: horloge, appareilId: qr.appareilId, fichiers: fichiersTel);
    client = ClientSynchronisation(depot: depot, transport: transport, identite: identite, horloge: horloge);
    await client.synchroniser(); // comptes, établissement, élève
  });

  tearDown(() async {
    await db.close();
    await dossier.delete(recursive: true);
  });

  Future<(Enregistrement, List<int>)> prendrePhoto() async {
    final v = await depot.creer(
        'visite', {'eleve_id': eleve, 'agent_id': agent.id, 'date_visite': '2026-11-10', 'statut': 'en_attente'},
        utilisateurId: agent.id, etablissementId: etab);
    final c = await depot.creer(
        'consentement',
        {
          'eleve_id': eleve,
          'visite_id': v.id,
          'obtenu': true,
          'forme': 'oral',
          'nom_repondant': 'Parent fictif',
          'date_consentement': '2026-11-10'
        },
        utilisateurId: agent.id,
        etablissementId: etab);
    final jpeg = List<int>.generate(700 * 1024, (i) => (i * 7) % 256); // 2 morceaux
    final id = nouvelId();
    final chemin = await fichiersTel.ecrire('photos', id, jpeg);
    final p = await depot.creer(
        'photo',
        {
          'visite_id': v.id,
          'eleve_id': eleve,
          'auteur_id': agent.id,
          'consentement_id': c.id,
          'chemin_chiffre': chemin,
          'empreinte_sha256': sha256Hex(jpeg),
          'taille_octets': jpeg.length,
          'pris_le': formaterHorodatage(horloge.maintenant()),
          'statut_transfert': 'en_attente',
        },
        utilisateurId: agent.id,
        etablissementId: etab,
        id: id);
    return (p, jpeg);
  }

  test('photographie : données puis fichier ; copie du téléphone effacée après confirmation', () async {
    final (p, jpeg) = await prendrePhoto();
    final chemin = p.donnees['chemin_chiffre']! as String;
    expect(await depot.fichiersATransferer(), isEmpty, reason: 'données pas encore acceptées par le poste');

    final r = await client.synchroniser();
    expect(r.acceptes, 3);
    expect(r.fichiers, 1);
    expect(stockagePoste.fichiers[p.id], jpeg);
    expect(serveur.lireDirect('photo', p.id)!.donnees['statut_transfert'], 'confirme');
    expect((await depot.lire('photo', p.id))!.donnees['statut_transfert'], 'confirme');
    expect(await fichiersTel.existe(chemin), isFalse);
    expect(await depot.fichiersATransferer(), isEmpty);

    // Commentaire ajouté ensuite sur le téléphone : le poste garde le statut « confirme ».
    await depot.modifier('photo', p.id, {'commentaire': 'Lésion avant-bras'}, utilisateurId: agent.id, etablissementId: etab);
    final r2 = await client.synchroniser();
    expect(r2.acceptes, 1);
    final poste = serveur.lireDirect('photo', p.id)!;
    expect((poste.donnees['commentaire'], poste.donnees['statut_transfert']), ('Lésion avant-bras', 'confirme'));
  });

  test('fichier local manquant : signalé en échec, données conservées', () async {
    final (p, _) = await prendrePhoto();
    await fichiersTel.supprimer(p.donnees['chemin_chiffre']! as String);
    final r = await client.synchroniser();
    expect(r.acceptes, 3);
    expect(r.fichiersEnEchec, 1);
    expect((await depot.lire('photo', p.id))!.donnees['statut_transfert'], 'en_attente');
  });

  test('éléments refusés : listés avec leur motif, puis abandonnés avec leurs dépendances', () async {
    // Élève créé par erreur pour un établissement non affecté au téléphone, avec une visite.
    final e = await depot.creer('eleve', {'nom': 'YAO', 'prenoms': 'Koffi', 'sexe': 'M'},
        utilisateurId: agent.id, etablissementId: etabNonAffecte);
    final v = await depot.creer(
        'visite', {'eleve_id': e.id, 'agent_id': agent.id, 'date_visite': '2026-11-10', 'statut': 'en_attente'},
        utilisateurId: agent.id, etablissementId: etabNonAffecte);
    final r = await client.synchroniser();
    expect(r.refuses + r.conflits, 2);
    final liste = await depot.enConflit();
    expect(liste.map((x) => x.enregistrement.id).toSet(), {e.id, v.id});
    expect(liste.every((x) => x.motif != null), isTrue);

    // Un dossier reçu du poste central ne peut pas être abandonné.
    await expectLater(depot.abandonner('eleve', eleve), throwsStateError);

    expect(await depot.abandonner('eleve', e.id), 2);
    expect(await depot.lire('eleve', e.id), isNull);
    expect(await depot.lire('visite', v.id), isNull);
    expect(await depot.enConflit(), isEmpty);
    expect(await depot.motifConflit('eleve', e.id), isNull);
  });
}
