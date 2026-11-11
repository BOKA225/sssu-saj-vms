import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:sssu_mobile/data/base_locale.dart' hide Utilisateur, Eleve;
import 'package:sssu_mobile/data/depot_local_drift.dart';
import 'package:sssu_mobile/data/depot_utilisateurs_drift.dart';

import 'outils/transport_direct.dart';

/// Comptes modifiés sur le poste central et reçus par le téléphone :
/// - 1.0.1 : mot de passe temporaire changé sur le poste, reçu par une
///   synchronisation lancée depuis l'écran de connexion (sans session) ;
/// - 1.0.2 : compte supprimé sur le poste, connexion refusée sur le téléphone.
void main() {
  test('mot de passe temporaire changé sur le poste, reçu par le téléphone sans connexion préalable', () async {
    final horloge = HorlogeFixe(DateTime.utc(2026, 11, 11, 8));
    final db = BaseLocale(NativeDatabase.memory(setup: (d) => d.execute('PRAGMA foreign_keys = ON;')));
    addTearDown(db.close);
    final serveur = DepotServeurMemoire();
    await initialiserRoles(serveur, horloge: horloge);
    final hacheur = HacheurMotDePasse(parametres: ParametresArgon2.tests);
    final auth = ServiceAuthentification(
        depot: DepotUtilisateursServeur(serveur, horloge: horloge), hacheur: hacheur, horloge: horloge);
    final admin = await auth.creerPremierAdministrateur(identifiant: 'admin', nom: 'ADMIN', motDePasse: 'Admin-2026');
    final droitsAdmin = await auth.droitsDe(admin);
    await auth.creerUtilisateur(droitsAdmin,
        identifiant: 'agent1', nom: 'AGENT', role: RoleCode.agent, motDePasseTemporaire: 'Temp-2026');
    final etab = nouvelId();
    await serveur.transaction((tx) => tx.ecrire(Enregistrement(
        table: 'etablissement',
        id: etab,
        version: 1,
        versionBase: 1,
        createdAt: horloge.maintenant(),
        updatedAt: horloge.maintenant(),
        etablissementId: etab,
        donnees: {'nom': 'École A', 'code': 'A', 'type': 'primaire', 'statut': 'public'})));

    final appairage = ServiceAppairage(depot: serveur, horloge: horloge);
    final transport = TransportDirect(ServiceSynchronisation(depot: serveur, horloge: horloge), appairage,
        ServiceJetons(depot: serveur, horloge: horloge));
    final qr = await appairage.preparer(
        acteur: droitsAdmin, nomAppareil: 'Tel', etablissementIds: [etab], urlServeur: 'x', empreinteCertificat: null);
    final identite = await IdentiteAppareil.generer(qr.appareilId);
    await transport.appairer(
        DemandeAppairage(appareilId: qr.appareilId, code: qr.code, clePublique: await identite.clePubliqueBase64()));
    final client = ClientSynchronisation(
        depot: DepotLocalDrift(db, horloge: horloge, appareilId: qr.appareilId),
        transport: transport,
        identite: identite,
        horloge: horloge);
    await client.synchroniser();

    // Sur le téléphone : compte reçu, mot de passe encore temporaire.
    final authMobile = ServiceAuthentification(depot: DepotUtilisateursDrift(db), hacheur: hacheur, horloge: horloge);
    final avant = await authMobile.connecter('agent1', 'Temp-2026');
    expect(avant.session!.doitChangerMotDePasse, isTrue);

    // L'agent choisit son mot de passe sur le poste central.
    final surPoste = (await auth.connecter('agent1', 'Temp-2026')).session!;
    await auth.changerMotDePasse(surPoste, ancien: 'Temp-2026', nouveau: 'Terrain-2026');

    // Synchronisation sans session (bouton de l'écran de connexion).
    final r = await client.synchroniser();
    expect(r.recus, greaterThan(0));

    final apres = await authMobile.connecter('agent1', 'Terrain-2026');
    expect(apres.reussie, isTrue);
    expect(apres.session!.doitChangerMotDePasse, isFalse);
    expect((await authMobile.connecter('agent1', 'Temp-2026')).reussie, isFalse);
  });

  test('compte supprimé sur le poste : connexion refusée sur le téléphone après synchronisation', () async {
    final horloge = HorlogeFixe(DateTime.utc(2026, 11, 11, 8));
    final db = BaseLocale(NativeDatabase.memory(setup: (d) => d.execute('PRAGMA foreign_keys = ON;')));
    addTearDown(db.close);
    final serveur = DepotServeurMemoire();
    await initialiserRoles(serveur, horloge: horloge);
    final hacheur = HacheurMotDePasse(parametres: ParametresArgon2.tests);
    final auth = ServiceAuthentification(
        depot: DepotUtilisateursServeur(serveur, horloge: horloge), hacheur: hacheur, horloge: horloge);
    final admin = await auth.creerPremierAdministrateur(identifiant: 'admin', nom: 'ADMIN', motDePasse: 'Admin-2026');
    final droitsAdmin = await auth.droitsDe(admin);
    final agent = await auth.creerUtilisateur(droitsAdmin,
        identifiant: 'agent1', nom: 'AGENT', role: RoleCode.agent, motDePasseTemporaire: 'Temp-2026');
    final surPoste = (await auth.connecter('agent1', 'Temp-2026')).session!;
    await auth.changerMotDePasse(surPoste, ancien: 'Temp-2026', nouveau: 'Terrain-2026');
    final etab = nouvelId();
    await serveur.transaction((tx) => tx.ecrire(Enregistrement(
        table: 'etablissement',
        id: etab,
        version: 1,
        versionBase: 1,
        createdAt: horloge.maintenant(),
        updatedAt: horloge.maintenant(),
        etablissementId: etab,
        donnees: {'nom': 'École A', 'code': 'A', 'type': 'primaire', 'statut': 'public'})));
    final appairage = ServiceAppairage(depot: serveur, horloge: horloge);
    final transport = TransportDirect(ServiceSynchronisation(depot: serveur, horloge: horloge), appairage,
        ServiceJetons(depot: serveur, horloge: horloge));
    final qr = await appairage.preparer(
        acteur: droitsAdmin, nomAppareil: 'Tel', etablissementIds: [etab], urlServeur: 'x', empreinteCertificat: null);
    final identite = await IdentiteAppareil.generer(qr.appareilId);
    await transport.appairer(
        DemandeAppairage(appareilId: qr.appareilId, code: qr.code, clePublique: await identite.clePubliqueBase64()));
    final client = ClientSynchronisation(
        depot: DepotLocalDrift(db, horloge: horloge, appareilId: qr.appareilId),
        transport: transport,
        identite: identite,
        horloge: horloge);
    await client.synchroniser();
    final authMobile = ServiceAuthentification(depot: DepotUtilisateursDrift(db), hacheur: hacheur, horloge: horloge);
    expect((await authMobile.connecter('agent1', 'Terrain-2026')).reussie, isTrue);

    await ServiceGestion(depot: serveur, horloge: horloge, hacheur: hacheur)
        .supprimerCompte(droitsAdmin, agent.id, motif: 'Départ du service');
    await client.synchroniser();

    expect((await authMobile.connecter('agent1', 'Terrain-2026')).reussie, isFalse);
    expect(await DepotUtilisateursDrift(db).parId(agent.id), isNull);
  });
}
