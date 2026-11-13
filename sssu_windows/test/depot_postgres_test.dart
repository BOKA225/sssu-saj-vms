/// Tests du dépôt PostgreSQL. Ils s'exécutent seulement si la variable
/// d'environnement SSSU_PG_TEST_URL désigne une base de TEST où le schéma
/// `sql/postgres/001_schema.sql` a été chargé, par exemple :
///
///   SSSU_PG_TEST_URL=postgres://postgres:motdepasse@localhost:5432/sssu_saj_test flutter test
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:sssu_windows/donnees/depot_postgres.dart';
import 'package:sssu_windows/donnees/migrations.dart';

void main() {
  final url = Platform.environment['SSSU_PG_TEST_URL'];
  final ignorer = url == null ? 'SSSU_PG_TEST_URL non définie' : null;

  late DepotPostgres depot;
  final horloge = HorlogeFixe(DateTime.utc(2026, 11, 10, 8));

  setUpAll(() async {
    if (url != null) {
      depot = await DepotPostgres.ouvrir(ConfigPostgres.depuisUrl(url));
      await MigrationsPoste(depot, Directory('../sql/postgres')).appliquer();
    }
  });
  tearDownAll(() async {
    if (url != null) await depot.fermer();
  });

  Enregistrement nouveau(String table, Map<String, Object?> d, {String? etab, String? id}) => Enregistrement(
      table: table,
      id: id ?? nouvelId(),
      version: 1,
      versionBase: 1,
      createdAt: horloge.maintenant(),
      updatedAt: horloge.maintenant(),
      etablissementId: etab,
      donnees: d);

  test('écriture et relecture de tous les types de colonnes', () async {
    final etab = nouvelId();
    await depot.transaction((tx) async {
      await tx.ecrire(nouveau('etablissement', {'nom': 'École PG', 'code': 'PG-$etab', 'type': 'primaire', 'statut': 'public'},
          id: etab));
      await tx.ecrire(nouveau('annee_scolaire',
          {'libelle': 'T-$etab', 'date_debut': '2026-09-14', 'date_fin': '2027-07-16', 'active': false}));
    });
    final insp = nouveau('critere_inspection', {'rubrique': 'eau_potable', 'code': 'c-$etab', 'libelle': 'Eau', 'ordre': 3});
    final j = nouveau('journal_audit', {
      'action': 'export',
      'apres': {'cle': 'valeur', 'n': 2},
      'survenu_le': '2026-11-10T08:00:00.000Z',
      'enregistrement_id': etab,
    });
    await depot.transaction((tx) async {
      await tx.ecrire(insp);
      await tx.ecrire(j);
    });
    final relu = await depot.transaction((tx) => tx.lire('journal_audit', j.id));
    expect(relu!.donnees['apres'], {'cle': 'valeur', 'n': 2});
    expect(relu.donnees['survenu_le'], '2026-11-10T08:00:00.000Z');
    final c = await depot.transaction((tx) => tx.lire('critere_inspection', insp.id));
    expect(c!.donnees['actif'], isTrue); // valeur par défaut fournie par la base
    expect(c.donnees['ordre'], 3);
    final e = await depot.transaction((tx) => tx.lire('etablissement', etab));
    expect(e!.etablissementId, etab);
  }, skip: ignorer);

  test('journal des changements filtré par établissement', () async {
    final a = nouvelId(), b = nouvelId();
    final avant = await depot.transaction(
        (tx) async => (await tx.changementsDepuis(0, tables: {'etablissement'}, etablissements: {}, limite: 100000)).length);
    expect(avant, 0, reason: 'un établissement n\'est diffusé qu\'aux téléphones qui y sont affectés');
    await depot.transaction((tx) async {
      await tx.ecrire(nouveau('etablissement', {'nom': 'A', 'code': 'A-$a', 'type': 'primaire', 'statut': 'public'}, id: a));
      await tx.ecrire(nouveau('etablissement', {'nom': 'B', 'code': 'B-$b', 'type': 'primaire', 'statut': 'public'}, id: b));
    });
    final vus = await depot.transaction((tx) async =>
        (await tx.changementsDepuis(0, tables: {'etablissement'}, etablissements: {a}, limite: 100000))
            .map((c) => c.enregistrement.id)
            .toSet());
    expect(vus, contains(a));
    expect(vus, isNot(contains(b)));
  }, skip: ignorer);

  test('synchronisation complète sur PostgreSQL : conflit détecté, rien de perdu', () async {
    await initialiserRoles(depot, horloge: horloge);
    final auth = ServiceAuthentification(
        depot: DepotUtilisateursServeur(depot, horloge: horloge),
        hacheur: HacheurMotDePasse(parametres: ParametresArgon2.tests),
        horloge: horloge);
    final roleAgent = await auth.depot.roleIdParCode(RoleCode.agent);
    final agent = Utilisateur(id: nouvelId(), identifiant: 'pg-${nouvelId().substring(0, 8)}', nom: 'AGENT', roleId: roleAgent!);
    await auth.depot.enregistrer(agent);
    final etab = nouvelId();
    final eleve = nouveau('eleve', {'nom': 'KOUASSI', 'prenoms': 'Aya', 'sexe': 'F'}, etab: etab);
    await depot.transaction((tx) async {
      await tx.ecrire(nouveau('etablissement', {'nom': 'E', 'code': 'E-$etab', 'type': 'primaire', 'statut': 'public'}, id: etab));
      await tx.ecrire(eleve);
    });
    final adminDroits = Droits(utilisateurId: agent.id, role: RoleCode.admin, permissions: matriceParDefaut[RoleCode.admin]!);
    final appairage = ServiceAppairage(depot: depot, horloge: horloge);
    final qr = await appairage.preparer(
        acteur: adminDroits, nomAppareil: 'PG', etablissementIds: [etab], urlServeur: 'x', empreinteCertificat: null);
    final id = await IdentiteAppareil.generer(qr.appareilId);
    await appairage.finaliser(DemandeAppairage(appareilId: qr.appareilId, code: qr.code, clePublique: await id.clePubliqueBase64()));

    final sync = ServiceSynchronisation(depot: depot, horloge: horloge);
    Enregistrement modif(String nom) => eleve.copier(
        version: 2, versionBase: 1, updatedBy: agent.id, donnees: {...eleve.donnees, 'nom': nom});
    final r1 = await sync.recevoirEnvoi(qr.appareilId, DemandeEnvoi(enregistrements: [modif('KOUASSY')]));
    final r2 = await sync.recevoirEnvoi(qr.appareilId, DemandeEnvoi(enregistrements: [modif('KOUASI')]));
    expect(r1.accuses.single.statut, StatutAccuse.accepte);
    expect(r2.accuses.single.statut, StatutAccuse.conflit);
    final serveur = await depot.transaction((tx) => tx.lire('eleve', eleve.id));
    expect(serveur!.donnees['nom'], 'KOUASSY');
    expect(serveur.version, 2);
    final conflits = await depot.transaction((tx) => tx.chercher('conflit', {'enregistrement_id': eleve.id}));
    expect(((conflits.single.donnees['version_appareil']! as Map)['donnees'] as Map)['nom'], 'KOUASI');

    final reception = await sync.preparerReception(qr.appareilId, 0, limite: 100000);
    expect(reception.changements.any((c) => c.enregistrement.id == eleve.id && c.enregistrement.version == 2), isTrue);
  }, skip: ignorer);

  test('enregistrement d\'un téléphone sans QR code sur PostgreSQL : attente, validation, jeton', () async {
    final hacheur = HacheurMotDePasse(parametres: ParametresArgon2.tests);
    final auth = ServiceAuthentification(
        depot: DepotUtilisateursServeur(depot, horloge: horloge), hacheur: hacheur, horloge: horloge);
    final roleAgent = await auth.depot.roleIdParCode(RoleCode.agent);
    final aleatoire = nouvelId();
    final ident = 'pg-enr-${aleatoire.substring(aleatoire.length - 12)}';
    final agent = Utilisateur(
        id: nouvelId(),
        identifiant: ident,
        nom: 'AGENT',
        roleId: roleAgent!,
        hashMotDePasse: await hacheur.hacher('Temp-2026'),
        doitChangerMotDePasse: true);
    await auth.depot.enregistrer(agent);
    final etab = nouvelId();
    await depot.transaction((tx) =>
        tx.ecrire(nouveau('etablissement', {'nom': 'E', 'code': 'R-$etab', 'type': 'primaire', 'statut': 'public'}, id: etab)));

    final appairage = ServiceAppairage(depot: depot, horloge: horloge, auth: auth);
    final jetons = ServiceJetons(depot: depot, horloge: horloge);
    final appareilId = nouvelId();
    final id = await IdentiteAppareil.generer(appareilId);
    await appairage.enregistrer(DemandeEnregistrement(
        identifiant: ident,
        motDePasse: 'Temp-2026',
        nouveauMotDePasse: 'Terrain-2026',
        appareilId: appareilId,
        clePublique: await id.clePubliqueBase64(),
        nomAppareil: 'Téléphone PG'));
    final attente = await depot.transaction((tx) => tx.chercher('appareil', {'titulaire_id': agent.id, 'en_attente': true}));
    expect(attente.single.id, appareilId);
    await expectLater(jetons.emettre(await id.demandeJeton(horloge)),
        throwsA(isA<ErreurProtocole>().having((e) => e.code, 'code', 'appareil_en_attente')));

    final admin = Droits(utilisateurId: agent.id, role: RoleCode.admin, permissions: matriceParDefaut[RoleCode.admin]!);
    await ServiceGestion(depot: depot, horloge: horloge, hacheur: hacheur).affecterEtablissements(admin, appareilId, {etab});
    await appairage.accepter(appareilId, admin);
    final jeton = await jetons.emettre(await id.demandeJeton(horloge));
    expect(await jetons.appareilDuJeton(jeton.jeton), appareilId);
  }, skip: ignorer);

  test('grille d\'inspection nationale installée par la migration 040 : identique au paquet commun', () async {
    final l = await depot.requete(
        'SELECT CAST(id AS text) AS id, code, libelle, rubrique, ordre, actif FROM critere_inspection WHERE deleted_at IS NULL');
    final parId = {for (final x in l) x['id'] as String: x};
    for (final c in criteresGrille) {
      final x = parId[c.id];
      expect(x, isNotNull, reason: c.code);
      expect([x!['code'], x['libelle'], x['rubrique'], x['ordre'], x['actif']], [c.code, c.libelle, c.rubrique.code, c.ordre, true],
          reason: c.code);
    }
    // Ancienne grille livrée (002_referentiels) désactivée ; diffusée aux téléphones.
    final anciens = await depot.requete('SELECT actif FROM critere_inspection '
        "WHERE created_at = CAST('2026-11-10T08:00:00Z' AS timestamptz) AND rubrique IN ('eau_potable', 'toilettes', "
        "'lavage_mains', 'dechets', 'environnement', 'cantine', 'vendeuses', 'infirmerie', 'securite')");
    expect(anciens, isNotEmpty);
    expect(anciens.where((x) => x['actif'] == true), isEmpty);
    final diffuses = await depot.requete(
        "SELECT COUNT(DISTINCT record_id) AS n FROM sync_changement WHERE table_name = 'critere_inspection' "
        'AND record_id IN (SELECT id FROM critere_inspection WHERE code = ANY(CAST(@codes AS text[])))',
        {'codes': '{${criteresGrille.map((c) => c.code).join(',')}}'});
    expect(diffuses.single['n'], 118);
  }, skip: ignorer);
}
