import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

import 'outils/environnement.dart';

void main() {
  late Environnement env;
  late String telephone; // identifiant de l'appareil appairé (établissement A)

  setUp(() async {
    env = await Environnement.creer();
    telephone = (await env.appairer('Téléphone test', [env.etabA])).appareilId;
  });

  Enregistrement entrant(String table, Map<String, Object?> donnees,
      {String? id, int version = 1, int base = 0, required Utilisateur auteur, String? etab}) {
    final m = env.horloge.maintenant();
    return Enregistrement(
      table: table,
      id: id ?? nouvelId(),
      version: version,
      versionBase: base,
      createdAt: m,
      updatedAt: m,
      createdBy: auteur.id,
      updatedBy: auteur.id,
      etablissementId: etab ?? env.etabA,
      donnees: donnees,
    );
  }

  Map<String, Object?> visite({required Utilisateur agent, String statut = 'en_attente'}) => {
        'eleve_id': env.eleveA,
        'agent_id': agent.id,
        'date_visite': '2026-11-10',
        'statut': statut,
        'poids_kg': 32.5,
        'taille_cm': 140.0,
      };

  Future<List<Accuse>> envoyer(List<Enregistrement> lot) async =>
      (await env.sync.recevoirEnvoi(telephone, DemandeEnvoi(enregistrements: lot))).accuses;

  test('création acceptée en version 1, appareil imposé par le jeton', () async {
    final v = entrant('visite', visite(agent: env.agent1), auteur: env.agent1);
    final a = (await envoyer([v.copier(deviceId: 'autre-appareil')])).single;
    expect(a.statut, StatutAccuse.accepte);
    expect(a.version, 1);
    final stocke = env.depot.lireDirect('visite', v.id)!;
    expect(stocke.deviceId, telephone);
    expect(stocke.donnees['poids_kg'], 32.5);
  });

  test('renvoi du même lot (accusé perdu) : déjà reçu, aucune duplication', () async {
    final v = entrant('visite', visite(agent: env.agent1), auteur: env.agent1);
    await envoyer([v]);
    final a = (await envoyer([v])).single;
    expect(a.statut, StatutAccuse.dejaRecu);
    expect(env.depot.tousDirect('visite').length, 1);
    expect(env.depot.lireDirect('visite', v.id)!.version, 1);
  });

  test('modification de sa propre visite, puis modification concurrente', () async {
    final v = entrant('visite', visite(agent: env.agent1), auteur: env.agent1);
    await envoyer([v]);
    final m1 = v.copier(version: 2, versionBase: 1, donnees: {...v.donnees, 'observations': 'RAS'});
    expect((await envoyer([m1])).single.version, 2);
    // Un second envoi reposant encore sur la version 1 : conflit, conservé.
    final m2 = v.copier(version: 2, versionBase: 1, donnees: {...v.donnees, 'observations': 'autre'});
    final a = (await envoyer([m2])).single;
    expect(a.statut, StatutAccuse.conflit);
    expect(env.depot.lireDirect('visite', v.id)!.donnees['observations'], 'RAS');
    final conflit = env.depot.tousDirect('conflit').single;
    expect(conflit.donnees['type'], TypesConflit.modificationConcurrente);
    expect((conflit.donnees['version_appareil']! as Map)['donnees'], containsPair('observations', 'autre'));
  });

  test('un agent ne modifie pas la visite d\'un autre agent', () async {
    final v = entrant('visite', visite(agent: env.agent1), auteur: env.agent1);
    await envoyer([v]);
    final m = v.copier(version: 2, versionBase: 1, updatedBy: env.agent2.id, donnees: {...v.donnees, 'fc': 90});
    expect((await envoyer([m])).single.motif, 'droits_insuffisants');
  });

  test('validation réservée, puis visite validée non modifiable', () async {
    final v = entrant('visite', visite(agent: env.agent1), auteur: env.agent1);
    await envoyer([v]);
    final parAgent = v.copier(version: 2, versionBase: 1, donnees: {...v.donnees, 'statut': 'valide'});
    expect((await envoyer([parAgent])).single.motif, 'validation_non_autorisee');

    final parChef = v.copier(
        version: 2, versionBase: 1, updatedBy: env.chef.id, donnees: {...v.donnees, 'statut': 'valide'});
    expect((await envoyer([parChef])).single.statut, StatutAccuse.accepte);

    final apres = parChef.copier(version: 3, versionBase: 2, donnees: {...parChef.donnees, 'fc': 80});
    expect((await envoyer([apres])).single.motif, 'visite_validee');
  });

  test('l\'administrateur ne peut pas envoyer de données médicales', () async {
    final v = entrant('visite', visite(agent: env.admin), auteur: env.admin);
    expect((await envoyer([v])).single.motif, 'droits_insuffisants');
  });

  test('établissement non affecté au téléphone : refusé', () async {
    final e = entrant('eleve', {'nom': 'YAO', 'prenoms': 'Koffi', 'sexe': 'M'}, auteur: env.medecin, etab: env.etabB);
    expect((await envoyer([e])).single.motif, 'etablissement_non_affecte');
  });

  test('table non autorisée et colonnes invalides : refusées', () async {
    final u = entrant('utilisateur', {'identifiant': 'pirate', 'nom': 'X', 'role_id': 'r'}, auteur: env.agent1);
    expect((await envoyer([u])).single.motif, 'table_non_autorisee');
    final e = entrant('eleve', {'nom': 'YAO', 'prenoms': 'Koffi', 'sexe': 'M', 'inconnue': 1}, auteur: env.medecin);
    expect((await envoyer([e])).single.motif, startsWith('donnees_invalides'));
  });

  test('deuxième inscription la même année : conflit d\'unicité', () async {
    final i = entrant('inscription',
        {'eleve_id': env.eleveA, 'classe_id': env.classeA, 'annee_scolaire_id': env.anneeId, 'statut': 'inscrit'},
        auteur: env.medecin);
    final a = (await envoyer([i])).single;
    expect(a.statut, StatutAccuse.conflit);
    expect(env.depot.tousDirect('conflit').single.donnees['type'], TypesConflit.unicite);
  });

  test('élève créé avec un matricule existant : accepté et signalé', () async {
    final e = entrant('eleve', {'matricule': '12345678A', 'nom': 'KOUASSI', 'prenoms': 'Aya', 'sexe': 'F'},
        auteur: env.medecin);
    expect((await envoyer([e])).single.statut, StatutAccuse.accepte);
    expect(env.depot.tousDirect('conflit').single.donnees['type'], TypesConflit.doublonEleve);
  });

  test('deux visites du même élève le même jour : acceptées et signalées', () async {
    await envoyer([entrant('visite', visite(agent: env.agent1), auteur: env.agent1)]);
    await envoyer([entrant('visite', visite(agent: env.agent2), auteur: env.agent2)]);
    expect(env.depot.tousDirect('visite').length, 2);
    expect(env.depot.tousDirect('conflit').single.donnees['type'], TypesConflit.doublonVisite);
  });

  test('un enregistrement invalide est refusé sans bloquer le reste du lot', () async {
    final v = entrant('visite', visite(agent: env.agent1), auteur: env.agent1);
    // Second élément invalide (nom obligatoire manquant).
    final casse = entrant('eleve', {'nom': 'X', 'prenoms': 'Y', 'sexe': 'M'}, auteur: env.medecin);
    final lot = [v, casse.copier(donnees: {'nom': null, 'prenoms': 'Y', 'sexe': 'M'})];
    final accuses = await envoyer(lot);
    expect(accuses[0].statut, StatutAccuse.accepte);
    expect(accuses[1].statut, StatutAccuse.refuse); // refus contrôlé, sans annuler le reste
    expect(env.depot.lireDirect('visite', v.id), isNotNull);
  });

  test('classe créée sur le téléphone : réservée au Médecin-Chef', () async {
    Map<String, Object?> classe(String libelle) =>
        {'etablissement_id': env.etabA, 'annee_scolaire_id': env.anneeId, 'libelle': libelle, 'niveau': 'CE2'};
    expect((await envoyer([entrant('classe', classe('CE2 A'), auteur: env.agent1)])).single.motif, 'droits_insuffisants');
    expect((await envoyer([entrant('classe', classe('CE2 A'), auteur: env.chef)])).single.statut, StatutAccuse.accepte);
    // Même libellé la même année dans le même établissement : conflit d'unicité.
    expect((await envoyer([entrant('classe', classe('CE2 A'), auteur: env.chef)])).single.statut, StatutAccuse.conflit);
  });

  test('journal de synchronisation alimenté', () async {
    await envoyer([entrant('visite', visite(agent: env.agent1), auteur: env.agent1)]);
    final j = env.depot.tousDirect('journal_sync').single;
    expect(j.donnees['envoyes'], 1);
    expect(j.donnees['appareil_id'], telephone);
  });

  test('réception limitée aux référentiels et à l\'établissement du téléphone', () async {
    final r = await env.sync.preparerReception(telephone, 0);
    final tables = r.changements.map((c) => c.enregistrement.table).toSet();
    expect(tables, containsAll(['role', 'role_permission', 'utilisateur', 'annee_scolaire', 'etablissement', 'classe', 'eleve', 'inscription']));
    final eleves = r.changements.where((c) => c.enregistrement.table == 'eleve').map((c) => c.enregistrement.id);
    expect(eleves, [env.eleveA]);
    expect(r.changements.any((c) => c.enregistrement.table == 'appareil'), isFalse);
    expect(r.suite, isFalse);
    // Rien de nouveau depuis le curseur rendu.
    expect((await env.sync.preparerReception(telephone, r.curseur)).changements, isEmpty);
  });

  test('réception par pages', () async {
    final p1 = await env.sync.preparerReception(telephone, 0, limite: 5);
    expect(p1.changements.length, 5);
    expect(p1.suite, isTrue);
    final p2 = await env.sync.preparerReception(telephone, p1.curseur, limite: 500);
    expect(p2.changements.first.enregistrement.id, isNot(p1.changements.last.enregistrement.id));
  });
}
