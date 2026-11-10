import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:sssu_mobile/data/base_locale.dart';
import 'package:sssu_mobile/data/depot_local_drift.dart';
import 'package:sssu_mobile/data/depot_utilisateurs_drift.dart';

import 'outils/transport_direct.dart';

BaseLocale _base() => BaseLocale(NativeDatabase.memory(setup: (db) {
      db.execute('PRAGMA foreign_keys = ON;');
    }));

void main() {
  late BaseLocale db;
  final horloge = HorlogeFixe(DateTime.utc(2026, 11, 10, 8));

  setUp(() async {
    db = _base();
    await db.customSelect('SELECT 1').get(); // création du schéma
  });

  tearDown(() => db.close());

  test('le schéma drift est identique au registre du paquet commun', () async {
    for (final spec in registre.where((t) => t.surMobile)) {
      final colonnes = await db.customSelect('PRAGMA table_info(${spec.nom})').get();
      final noms = colonnes.map((c) => c.read<String>('name')).toSet();
      expect(noms, containsAll(spec.nomsColonnes), reason: spec.nom);
      expect(noms.difference({...spec.nomsColonnes, ...colonnesCommunes}),
          {'base_version', 'sync_status', 'portee_etablissement_id'},
          reason: spec.nom);
    }
  });

  test('chargement du jeu de données de test', () async {
    await db.customStatement(File('../sql/seed/donnees_test.sql').readAsStringSync());
    final n = await db.customSelect('SELECT COUNT(*) AS n FROM eleve').getSingle();
    expect(n.read<int>('n'), 120);
    final fk = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(fk, isEmpty);
  });

  test('saisie locale, envoi, accusé et modification pendant l\'envoi', () async {
    final depot = DepotLocalDrift(db, horloge: horloge, appareilId: 'tel-1');
    final e = await depot.creer('eleve', {'nom': 'YAO', 'prenoms': 'Koffi', 'sexe': 'M', 'date_naissance': '2014-01-02'},
        utilisateurId: 'u1', etablissementId: 'etab-1');
    final brouillon = await depot.creer('eleve', {'nom': 'AKA', 'prenoms': 'Awa', 'sexe': 'F'},
        utilisateurId: 'u1', aTransmettre: false);

    final attente = await depot.enAttente(limite: 10);
    expect(attente.map((x) => x.id), [e.id]); // l'ébauche n'est pas envoyée
    expect(attente.single.etablissementId, 'etab-1');
    expect(attente.single.donnees['date_naissance'], '2014-01-02');

    await depot.marquerSynchronise(attente.single, 1);
    expect(await depot.etat('eleve', e.id), EtatSync.synchronise);

    final m = await depot.modifier('eleve', e.id, {'telephone_contact': '0700000000'}, utilisateurId: 'u1');
    expect(m.version, 2);
    final envoye = (await depot.enAttente(limite: 10)).single;
    horloge.avancer(const Duration(seconds: 3));
    await depot.modifier('eleve', e.id, {'prenoms': 'Koffi Jean'}, utilisateurId: 'u1');
    await depot.marquerSynchronise(envoye, 2);
    final apres = (await depot.lire('eleve', e.id))!;
    expect(await depot.etat('eleve', e.id), EtatSync.enAttente);
    expect(apres.versionBase, 2);
    expect(apres.version, 3);
    expect(await depot.etat('eleve', brouillon.id), EtatSync.local);
  });

  test('réception : une modification locale ou en conflit n\'est pas écrasée', () async {
    final depot = DepotLocalDrift(db, horloge: horloge);
    final e = await depot.creer('eleve', {'nom': 'YAO', 'prenoms': 'Koffi', 'sexe': 'M'}, utilisateurId: 'u1');
    final distant = e.copier(version: 5, donnees: {...e.donnees, 'nom': 'SERVEUR'});

    await depot.appliquerDistant(distant, resolutionConflit: false);
    expect((await depot.lire('eleve', e.id))!.donnees['nom'], 'YAO');

    await depot.marquerConflit(e, 'modification concurrente');
    await depot.appliquerDistant(distant, resolutionConflit: false);
    expect((await depot.lire('eleve', e.id))!.donnees['nom'], 'YAO');
    expect(await depot.motifConflit('eleve', e.id), 'modification concurrente');

    await depot.appliquerDistant(distant, resolutionConflit: true);
    final l = (await depot.lire('eleve', e.id))!;
    expect(l.donnees['nom'], 'SERVEUR');
    expect(l.versionBase, 5);
    expect(await depot.etat('eleve', e.id), EtatSync.synchronise);
    expect(await depot.motifConflit('eleve', e.id), isNull);
  });

  test('une photo exige un consentement obtenu (déclencheur SQLite)', () async {
    await db.customStatement(File('../sql/seed/donnees_test.sql').readAsStringSync());
    final depot = DepotLocalDrift(db, horloge: horloge);
    final role = await db.customSelect("SELECT id FROM role WHERE code = 'agent'").getSingle();
    final ins = await db.customSelect('SELECT id, eleve_id FROM inscription LIMIT 1').getSingle();
    final u = await depot.creer('utilisateur', {'identifiant': 'agent1', 'nom': 'AGENT', 'role_id': role.read<String>('id')},
        utilisateurId: 'x');
    final v = await depot.creer('visite', {
      'eleve_id': ins.read<String>('eleve_id'),
      'inscription_id': ins.read<String>('id'),
      'agent_id': u.id,
      'date_visite': '2026-11-10',
    }, utilisateurId: u.id);
    final refus = await depot.creer('consentement',
        {'eleve_id': ins.read<String>('eleve_id'), 'visite_id': v.id, 'obtenu': false, 'date_consentement': '2026-11-10'},
        utilisateurId: u.id);
    Map<String, Object?> photo(String consentementId) => {
          'visite_id': v.id,
          'eleve_id': ins.read<String>('eleve_id'),
          'auteur_id': u.id,
          'consentement_id': consentementId,
          'chemin_chiffre': 'photos/x.enc',
          'empreinte_sha256': 'abc',
          'taille_octets': 1000,
          'pris_le': formaterHorodatage(horloge.maintenant()),
        };
    await expectLater(depot.creer('photo', photo(refus.id), utilisateurId: u.id), throwsA(anything));
    final accord = await depot.creer(
        'consentement',
        {
          'eleve_id': ins.read<String>('eleve_id'),
          'visite_id': v.id,
          'obtenu': true,
          'forme': 'oral',
          'nom_repondant': 'Parent fictif',
          'date_consentement': '2026-11-10',
        },
        utilisateurId: u.id);
    expect((await depot.creer('photo', photo(accord.id), utilisateurId: u.id)).table, 'photo');
  });

  test('synchronisation réelle de la base SQLite avec un poste central simulé', () async {
    // Poste central en mémoire avec un établissement, un élève et un agent.
    final serveur = DepotServeurMemoire();
    await initialiserRoles(serveur, horloge: horloge);
    final auth = ServiceAuthentification(
        depot: DepotUtilisateursServeur(serveur, horloge: horloge),
        hacheur: HacheurMotDePasse(parametres: ParametresArgon2.tests),
        horloge: horloge);
    final admin = await auth.creerPremierAdministrateur(identifiant: 'admin', nom: 'ADMIN', motDePasse: 'Admin-2026');
    final droitsAdmin = await auth.droitsDe(admin);
    final agent = await auth.creerUtilisateur(droitsAdmin,
        identifiant: 'agent1', nom: 'AGENT', role: RoleCode.agent, motDePasseTemporaire: 'Temp-2026');
    // Le mot de passe temporaire est changé sur le poste central.
    final sessionAgent = (await auth.connecter('agent1', 'Temp-2026')).session!;
    await auth.changerMotDePasse(sessionAgent, ancien: 'Temp-2026', nouveau: 'Terrain-2026');

    final etab = nouvelId();
    final eleve = nouvelId();
    await serveur.transaction((tx) async {
      Enregistrement n(String t, String id, Map<String, Object?> d, {String? portee}) => Enregistrement(
          table: t,
          id: id,
          version: 1,
          versionBase: 1,
          createdAt: horloge.maintenant(),
          updatedAt: horloge.maintenant(),
          etablissementId: portee,
          donnees: d);
      await tx.ecrire(n('etablissement', etab, {'nom': 'École TEST', 'code': 'T1', 'type': 'primaire', 'statut': 'public'},
          portee: etab));
      await tx.ecrire(n('eleve', eleve, {'nom': 'KOUASSI', 'prenoms': 'Aya', 'sexe': 'F'}, portee: etab));
    });

    final sync = ServiceSynchronisation(depot: serveur, horloge: horloge);
    final appairage = ServiceAppairage(depot: serveur, horloge: horloge);
    final jetons = ServiceJetons(depot: serveur, horloge: horloge);
    final qr = await appairage.preparer(
        acteur: droitsAdmin, nomAppareil: 'Tel', etablissementIds: [etab], urlServeur: 'x', empreinteCertificat: null);
    final identite = await IdentiteAppareil.generer(qr.appareilId);
    final transport = TransportDirect(sync, appairage, jetons);
    await transport.appairer(
        DemandeAppairage(appareilId: qr.appareilId, code: qr.code, clePublique: await identite.clePubliqueBase64()));

    final depot = DepotLocalDrift(db, horloge: horloge, appareilId: qr.appareilId);
    final client = ClientSynchronisation(depot: depot, transport: transport, identite: identite, horloge: horloge);

    // Réception : comptes et rôles arrivent dans la base SQLite.
    final r1 = await client.synchroniser();
    expect(r1.recus, greaterThan(0));
    expect((await depot.lire('eleve', eleve))!.donnees['nom'], 'KOUASSI');

    // Connexion hors ligne sur le téléphone avec le compte reçu, puis code PIN.
    final authMobile = ServiceAuthentification(
        depot: DepotUtilisateursDrift(db), hacheur: HacheurMotDePasse(parametres: ParametresArgon2.tests), horloge: horloge);
    final session = (await authMobile.connecter('agent1', 'Terrain-2026')).session!;
    expect(session.droits.role, RoleCode.agent);
    await authMobile.definirPin(session, '482915');

    // Saisie d'une visite sur le téléphone, envoi, accusé.
    final v = await depot.creer('visite',
        {'eleve_id': eleve, 'agent_id': agent.id, 'date_visite': '2026-11-10', 'statut': 'en_attente', 'poids_kg': 31.5},
        utilisateurId: agent.id, etablissementId: etab);
    final r2 = await client.synchroniser();
    expect(r2.acceptes, 1);
    expect(serveur.lireDirect('visite', v.id)!.donnees['poids_kg'], 31.5);
    expect(await depot.etat('visite', v.id), EtatSync.synchronise);

    // Une mise à jour du compte sur le poste central ne doit pas effacer le PIN du téléphone.
    await auth.depot.enregistrer((await auth.depot.parId(agent.id))!.copier(doitChangerMotDePasse: false));
    await client.synchroniser();
    expect((await authMobile.connecterParPin(agent.id, '482915')).reussie, isTrue);
  });
}
