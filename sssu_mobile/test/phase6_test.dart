import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:sssu_mobile/data/base_locale.dart' hide Utilisateur, Eleve;
import 'package:sssu_mobile/data/depot_local_drift.dart';

import 'outils/transport_direct.dart';

/// Phase 6 sur la vraie base SQLite : reprise après restauration du poste
/// central et téléphone bloqué.
void main() {
  final horloge = HorlogeFixe(DateTime.utc(2026, 11, 10, 8));
  late BaseLocale db;
  late DepotServeurMemoire serveur;
  late DepotLocalDrift depot;
  late ClientSynchronisation client;
  late Utilisateur agent;
  late String etab;
  late String eleve;
  late String appareil;

  setUp(() async {
    db = BaseLocale(NativeDatabase.memory(setup: (d) => d.execute('PRAGMA foreign_keys = ON;')));
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
    eleve = nouvelId();
    await serveur.transaction((tx) async {
      Enregistrement n(String t, String id, Map<String, Object?> d) => Enregistrement(
          table: t,
          id: id,
          version: 1,
          versionBase: 1,
          createdAt: horloge.maintenant(),
          updatedAt: horloge.maintenant(),
          etablissementId: etab,
          donnees: d);
      await tx.ecrire(n('etablissement', etab, {'nom': 'École A', 'code': 'A', 'type': 'primaire', 'statut': 'public'}));
      await tx.ecrire(n('eleve', eleve, {'nom': 'KOUASSI', 'prenoms': 'Aya', 'sexe': 'F'}));
    });
    final appairage = ServiceAppairage(depot: serveur, horloge: horloge);
    final jetons = ServiceJetons(depot: serveur, horloge: horloge);
    final transport = TransportDirect(ServiceSynchronisation(depot: serveur, horloge: horloge), appairage, jetons);
    final qr = await appairage.preparer(
        acteur: droitsAdmin, nomAppareil: 'Tel', etablissementIds: [etab], urlServeur: 'x', empreinteCertificat: null);
    appareil = qr.appareilId;
    final identite = await IdentiteAppareil.generer(qr.appareilId);
    await transport.appairer(
        DemandeAppairage(appareilId: qr.appareilId, code: qr.code, clePublique: await identite.clePubliqueBase64()));
    depot = DepotLocalDrift(db, horloge: horloge, appareilId: qr.appareilId);
    client = ClientSynchronisation(depot: depot, transport: transport, identite: identite, horloge: horloge);
    await client.synchroniser();
  });

  tearDown(() => db.close());

  Future<Enregistrement> visite(String date) => depot.creer(
      'visite', {'eleve_id': eleve, 'agent_id': agent.id, 'date_visite': date, 'statut': 'en_attente'},
      utilisateurId: agent.id, etablissementId: etab);

  test('reprise : génération mémorisée, données renvoyées, curseur repris à zéro', () async {
    expect(await depot.generationServeur(), await serveur.generation());
    final v1 = await visite('2026-11-03');
    await client.synchroniser();
    final sauvegarde = serveur.instantane();
    final v2 = await visite('2026-11-04');
    await client.synchroniser();
    expect(await depot.curseur(), greaterThan(0));

    serveur.restaurer(sauvegarde);
    final r = await client.synchroniser();
    expect(r.reprise, isTrue);
    expect(serveur.lireDirect('visite', v2.id), isNotNull, reason: 'visite postérieure à la sauvegarde, renvoyée');
    expect(serveur.lireDirect('visite', v1.id), isNotNull);
    expect(await depot.generationServeur(), await serveur.generation());
    expect(await depot.etat('visite', v2.id), EtatSync.synchronise);
    expect((await client.synchroniser()).reprise, isFalse);
  });

  test('préparation de la reprise : seules les données synchronisées des tables envoyables repassent en attente', () async {
    final v = await visite('2026-11-05');
    final ebauche = await depot.creer(
        'visite', {'eleve_id': eleve, 'agent_id': agent.id, 'date_visite': '2026-11-06', 'statut': 'ebauche'},
        utilisateurId: agent.id, etablissementId: etab, aTransmettre: false);
    await client.synchroniser();
    final cles = await depot.preparerReprise();
    expect(cles, containsAll(['visite/${v.id}', 'eleve/$eleve']));
    expect(cles.any((c) => c.startsWith('utilisateur/')), isFalse, reason: 'les comptes ne s\'envoient pas');
    expect(cles, isNot(contains('visite/${ebauche.id}')), reason: 'une ébauche reste sur le téléphone');
    expect(await depot.etat('visite', ebauche.id), EtatSync.local);
  });

  test('téléphone bloqué : la synchronisation est refusée (le service mobile efface alors le téléphone)', () async {
    await serveur.transaction((tx) async {
      final a = (await tx.lire('appareil', appareil))!;
      await tx.ecrire(a.copier(version: a.version + 1, donnees: {...a.donnees, 'bloque': true}));
    });
    await expectLater(client.synchroniser(), throwsA(isA<ErreurProtocole>().having((e) => e.code, 'code', 'appareil_bloque')));
  });
}
