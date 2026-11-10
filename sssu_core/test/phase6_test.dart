/// Phase 6 : recette automatique de la synchronisation.
/// - plusieurs téléphones sur plusieurs établissements ;
/// - fonctionnement hors ligne et coupures réseau (accusé perdu, réception
///   interrompue) ;
/// - modifications concurrentes sans perte ;
/// - reprise après restauration d'une sauvegarde du poste central ;
/// - sécurité des envois et de la diffusion.
library;

import 'dart:io';

import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

import 'outils/environnement.dart';

/// Transport direct vers les services du poste, avec coupures simulées.
class _Reseau implements TransportSync {
  final Environnement env;
  final int pageReception;
  bool horsLigne = false;

  /// Coupe la connexion APRÈS que le poste a traité le n-ième envoi (accusé perdu).
  int? coupureApresEnvoi;

  /// Coupe la connexion avant la n-ième page de réception.
  int? coupureAvantPage;
  int envois = 0;
  int pages = 0;
  _Reseau(this.env, {this.pageReception = 500});

  void _verifier() {
    if (horsLigne) throw const SocketException('Réseau indisponible');
  }

  @override
  Future<ReponseAppairage> appairer(DemandeAppairage d) => env.appairage.finaliser(d);
  @override
  Future<ReponseJeton> obtenirJeton(DemandeJeton d) async {
    _verifier();
    return env.jetons.emettre(d);
  }

  @override
  Future<ReponseEnvoi> envoyer(String jeton, DemandeEnvoi d) async {
    _verifier();
    final r = await env.sync.recevoirEnvoi(await env.jetons.appareilDuJeton(jeton), d);
    envois++;
    if (coupureApresEnvoi == envois) throw const SocketException('Connexion perdue avant l\'accusé');
    return r;
  }

  @override
  Future<ReponseReception> recevoir(String jeton, int curseur) async {
    _verifier();
    pages++;
    if (coupureAvantPage == pages) throw const SocketException('Connexion perdue pendant la réception');
    return env.sync.preparerReception(await env.jetons.appareilDuJeton(jeton), curseur, limite: pageReception);
  }

  @override
  Future<EtatFichier> etatFichier(String jeton, String table, String id) async =>
      env.fichiers.etat(await env.jetons.appareilDuJeton(jeton), table, id);
  @override
  Future<void> envoyerMorceau(String jeton, String table, String id, int numero, List<int> octets) async =>
      env.fichiers.recevoirMorceau(await env.jetons.appareilDuJeton(jeton), table, id, numero, octets);
  @override
  Future<void> terminerFichier(String jeton, String table, String id, int n) async =>
      env.fichiers.terminer(await env.jetons.appareilDuJeton(jeton), table, id, n);
}

class _Tel {
  final String appareilId;
  final DepotLocalMemoire base;
  final _Reseau reseau;
  final ClientSynchronisation client;
  _Tel(this.appareilId, this.base, this.reseau, this.client);
  Future<RapportSync> sync() => client.synchroniser();
}

void main() {
  late Environnement env;
  setUp(() async => env = await Environnement.creer());

  Future<_Tel> telephone(List<String> etabs, {int pageReception = 500, int tailleLot = 200}) async {
    final identite = await env.appairer('Tel', etabs);
    final base = DepotLocalMemoire(horloge: env.horloge, appareilId: identite.appareilId);
    final reseau = _Reseau(env, pageReception: pageReception);
    return _Tel(
        identite.appareilId,
        base,
        reseau,
        ClientSynchronisation(
            depot: base, transport: reseau, identite: identite, horloge: env.horloge, tailleLot: tailleLot));
  }

  Enregistrement visite(_Tel t, Utilisateur agent, String eleve, String etab, int jour, {String? observations}) =>
      t.base.creer(
          'visite',
          {
            'eleve_id': eleve,
            'agent_id': agent.id,
            'date_visite': '2026-10-${jour.toString().padLeft(2, '0')}',
            'statut': 'en_attente',
            if (observations != null) 'observations': observations,
          },
          utilisateurId: agent.id,
          etablissementId: etab);

  List<Enregistrement> visitesServeur() => env.depot.tousDirect('visite').where((v) => !v.supprime).toList();

  group('Plusieurs téléphones', () {
    test('5 téléphones, 2 établissements : tout arrive, chacun ne reçoit que ses établissements', () async {
      final a = [for (var i = 0; i < 3; i++) await telephone([env.etabA])];
      final b = [for (var i = 0; i < 2; i++) await telephone([env.etabB])];
      final agents = [env.agent1, env.agent2, env.medecin];
      for (final t in [...a, ...b]) {
        await t.sync();
      }
      var jour = 1;
      for (final (i, t) in a.indexed) {
        for (var k = 0; k < 4; k++) {
          visite(t, agents[i], env.eleveA, env.etabA, jour++);
        }
      }
      for (final (i, t) in b.indexed) {
        for (var k = 0; k < 4; k++) {
          visite(t, agents[i], env.eleveB, env.etabB, jour++);
        }
      }
      // Ordre de synchronisation mélangé, puis second passage pour recevoir les saisies des autres.
      for (final t in [b[1], a[2], a[0], b[0], a[1]]) {
        expect((await t.sync()).acceptes, 4);
      }
      for (final t in [...a, ...b]) {
        await t.sync();
      }
      expect(visitesServeur(), hasLength(20));
      for (final t in a) {
        expect(t.base.tous('visite').length, 12);
        expect(t.base.tous('visite').every((v) => v.donnees['eleve_id'] == env.eleveA), isTrue);
      }
      for (final t in b) {
        expect(t.base.tous('visite').length, 8);
      }
      // Toutes les copies identiques à celle du poste central.
      for (final v in visitesServeur()) {
        for (final t in v.donnees['eleve_id'] == env.eleveA ? a : b) {
          expect(t.base.lire('visite', v.id)!.version, v.version);
          expect(t.base.ligne('visite', v.id)!.etat, EtatSync.synchronise);
        }
      }
    });

    test('modification concurrente du même dossier : conflit, aucune perte, décision diffusée', () async {
      final t1 = await telephone([env.etabA]);
      final t2 = await telephone([env.etabA]);
      await t1.sync();
      await t2.sync();
      t1.base.modifier('eleve', env.eleveA, {'telephone_contact': '0701010101'}, utilisateurId: env.agent1.id);
      t2.base.modifier('eleve', env.eleveA, {'telephone_contact': '0502020202'}, utilisateurId: env.agent2.id);
      expect((await t1.sync()).acceptes, 1);
      final r2 = await t2.sync();
      expect(r2.conflits, 1);
      expect(t2.base.ligne('eleve', env.eleveA)!.etat, EtatSync.conflit);
      expect(t2.base.lire('eleve', env.eleveA)!.donnees['telephone_contact'], '0502020202',
          reason: 'la saisie du téléphone n\'est jamais écrasée sans décision');
      final conflit = env.depot.tousDirect('conflit').single;
      await env.conflits.resoudre(conflit.id, choix: ChoixConflit.appareil, acteur: await env.droits(env.chef));
      await t1.sync();
      await t2.sync();
      for (final t in [t1, t2]) {
        expect(t.base.lire('eleve', env.eleveA)!.donnees['telephone_contact'], '0502020202');
        expect(t.base.ligne('eleve', env.eleveA)!.etat, EtatSync.synchronise);
      }
    });
  });

  group('Hors ligne et coupures', () {
    test('hors ligne : rien n\'est perdu, tout part au retour du réseau', () async {
      final t = await telephone([env.etabA]);
      await t.sync();
      t.reseau.horsLigne = true;
      for (var j = 1; j <= 5; j++) {
        visite(t, env.agent1, env.eleveA, env.etabA, j);
      }
      await expectLater(t.sync(), throwsA(isA<SocketException>()));
      expect(t.base.tous('visite').where((v) => t.base.ligne('visite', v.id)!.etat == EtatSync.enAttente), hasLength(5));
      t.reseau.horsLigne = false;
      expect((await t.sync()).acceptes, 5);
      expect(visitesServeur(), hasLength(5));
    });

    test('accusé de réception perdu : renvoi reconnu, aucun doublon', () async {
      final t = await telephone([env.etabA], tailleLot: 2);
      await t.sync();
      for (var j = 1; j <= 5; j++) {
        visite(t, env.agent1, env.eleveA, env.etabA, j);
      }
      t.reseau.coupureApresEnvoi = t.reseau.envois + 2; // 2e lot traité par le poste, accusé perdu
      await expectLater(t.sync(), throwsA(isA<SocketException>()));
      expect(visitesServeur(), hasLength(4), reason: 'deux lots de 2 enregistrés par le poste');
      final r = await t.sync();
      expect((r.dejaRecus, r.acceptes, r.conflits), (2, 1, 0));
      expect(visitesServeur(), hasLength(5));
    });

    test('réception interrompue : reprise au bon endroit, état final identique', () async {
      final source = await telephone([env.etabA]);
      await source.sync();
      for (var j = 1; j <= 23; j++) {
        visite(source, env.agent1, env.eleveA, env.etabA, j);
      }
      await source.sync();
      final coupe = await telephone([env.etabA], pageReception: 5);
      final temoin = await telephone([env.etabA], pageReception: 5);
      coupe.reseau.coupureAvantPage = 4;
      await expectLater(coupe.sync(), throwsA(isA<SocketException>()));
      final curseurApresCoupure = await coupe.base.curseur();
      expect(curseurApresCoupure, greaterThan(0), reason: 'les pages appliquées ne sont pas redemandées');
      await coupe.sync();
      await temoin.sync();
      expect(coupe.base.tous('visite').length, 23);
      for (final table in ['eleve', 'inscription', 'utilisateur', 'pathologie', 'visite']) {
        expect(coupe.base.tous(table).map((e) => '${e.id}:${e.version}').toSet(),
            temoin.base.tous(table).map((e) => '${e.id}:${e.version}').toSet(),
            reason: table);
      }
    });
  });

  group('Reprise après restauration du poste central', () {
    test('les téléphones renvoient ce que la sauvegarde ne contenait pas ; la version la plus récente l\'emporte', () async {
      final a = await telephone([env.etabA]);
      final b = await telephone([env.etabA]);
      final c = await telephone([env.etabA]);
      for (final t in [a, b, c]) {
        await t.sync();
      }
      final v1 = visite(a, env.agent1, env.eleveA, env.etabA, 1, observations: 'avant');
      await a.sync();
      await c.sync(); // c détient v1 en version 1
      final sauvegarde = env.depot.instantane();

      // Après la sauvegarde : v1 modifiée, v2 créée, reçues par b.
      a.base.modifier('visite', v1.id, {'observations': 'après'}, utilisateurId: env.agent1.id);
      final v2 = visite(a, env.agent1, env.eleveA, env.etabA, 2);
      await a.sync();
      await b.sync();
      expect(env.depot.lireDirect('visite', v1.id)!.version, 2);

      // Panne du poste : restauration de la sauvegarde.
      env.depot.restaurer(sauvegarde);
      expect(env.depot.lireDirect('visite', v2.id), isNull);

      // c (copie ancienne) puis b (copie récente reçue) puis a.
      final rc = await c.sync();
      expect(rc.reprise, isTrue);
      expect(env.depot.lireDirect('visite', v1.id)!.donnees['observations'], 'avant');
      final rb = await b.sync();
      expect(rb.reprise, isTrue);
      expect(env.depot.lireDirect('visite', v1.id)!.donnees['observations'], 'après',
          reason: 'la copie de b (version 2) est plus récente que la sauvegarde');
      expect(env.depot.lireDirect('visite', v1.id)!.version, 2, reason: 'numéro de version conservé');
      expect(env.depot.lireDirect('visite', v2.id), isNotNull, reason: 'recréée à partir de la copie de b');
      final ra = await a.sync();
      expect(ra.reprise, isTrue);
      expect(ra.acceptes, 0, reason: 'tout était déjà revenu par b');

      // c reçoit la version récente ; les synchronisations suivantes sont normales.
      await c.sync();
      expect(c.base.lire('visite', v1.id)!.donnees['observations'], 'après');
      expect(c.base.lire('visite', v2.id), isNotNull);
      for (final t in [a, b, c]) {
        expect((await t.sync()).reprise, isFalse);
      }
      expect(env.depot.tousDirect('conflit').where((x) => x.donnees['type'] == TypesConflit.modificationConcurrente), isEmpty);
    });

    test('modification locale non transmise au moment de la restauration : transmise', () async {
      final a = await telephone([env.etabA]);
      await a.sync();
      final v = visite(a, env.agent1, env.eleveA, env.etabA, 3);
      await a.sync();
      final sauvegarde = env.depot.instantane();
      a.base.modifier('visite', v.id, {'observations': 'saisie hors ligne'}, utilisateurId: env.agent1.id);
      env.depot.restaurer(sauvegarde);
      final r = await a.sync();
      expect(r.reprise, isTrue);
      expect(env.depot.lireDirect('visite', v.id)!.donnees['observations'], 'saisie hors ligne');
    });
  });

  group('Sécurité des envois et de la diffusion', () {
    late _Tel t;
    late Droits droitsAgent;
    setUp(() async {
      t = await telephone([env.etabA]);
      await t.sync();
      droitsAgent = await env.droits(env.agent1);
    });

    Enregistrement forge(String table, Map<String, Object?> d, {String? etab, String? auteur, String? id}) {
      final m = env.horloge.maintenant();
      return Enregistrement(
          table: table,
          id: id ?? nouvelId(),
          version: 1,
          versionBase: 0,
          createdAt: m,
          updatedAt: m,
          updatedBy: auteur ?? env.agent1.id,
          etablissementId: etab,
          donnees: d);
    }

    Future<String?> motif(Enregistrement e) async =>
        (await env.sync.recevoirEnvoi(t.appareilId, DemandeEnvoi(enregistrements: [e]))).accuses.single.motif;

    test('établissement non affecté, table réservée au poste, auteur inconnu ou désactivé', () async {
      final v = {'eleve_id': env.eleveB, 'agent_id': env.agent1.id, 'date_visite': '2026-10-01', 'statut': 'en_attente'};
      expect(await motif(forge('visite', v, etab: env.etabB)), 'etablissement_non_affecte');
      // Élévation de privilèges par la synchronisation : refusée.
      expect(await motif(forge('utilisateur', {'identifiant': 'pirate', 'nom': 'X', 'role_id': nouvelId()})),
          'table_non_autorisee');
      expect(await motif(forge('role_permission', {'role_id': nouvelId(), 'permission': 'comptes.gerer'})),
          'table_non_autorisee');
      expect(await motif(forge('parametre', {'cle': 'nom_medecin_chef', 'valeur': 'X'})), 'table_non_autorisee');
      final va = {...v, 'eleve_id': env.eleveA};
      expect(await motif(forge('visite', va, etab: env.etabA, auteur: nouvelId())), 'utilisateur_inconnu_ou_inactif');
      await ServiceGestion(depot: env.depot, horloge: env.horloge)
          .definirActif(await env.droits(env.admin), env.agent2.id, actif: false);
      expect(await motif(forge('visite', {...va, 'agent_id': env.agent2.id}, etab: env.etabA, auteur: env.agent2.id)),
          'utilisateur_inconnu_ou_inactif');
      expect(droitsAgent.peut(Permission.comptesGerer), isFalse);
    });

    test('un agent ne modifie pas la visite d\'un autre agent ; une visite validée ne se modifie plus', () async {
      final v = visite(t, env.agent1, env.eleveA, env.etabA, 4);
      await t.sync();
      final serveur = env.depot.lireDirect('visite', v.id)!;
      final parAgent2 = serveur.copier(
          version: serveur.version + 1, updatedBy: env.agent2.id, donnees: {...serveur.donnees, 'observations': 'X'});
      expect(await motif(parAgent2), 'droits_insuffisants');
      await ServiceGestion(depot: env.depot, horloge: env.horloge).validerVisite(await env.droits(env.chef), v.id);
      final valide = env.depot.lireDirect('visite', v.id)!;
      final retouche = valide.copier(version: valide.version + 1, donnees: {...valide.donnees, 'observations': 'Y'});
      expect(await motif(retouche), isNotNull);
      expect(env.depot.lireDirect('visite', v.id)!.donnees['observations'], isNull);
    });

    test('lot trop grand refusé ; le téléphone ne reçoit ni journaux, ni conflits, ni autre établissement', () async {
      await expectLater(
          env.sync.recevoirEnvoi(t.appareilId,
              DemandeEnvoi(enregistrements: List.generate(env.sync.tailleMaxLot + 1, (_) => forge('journal_audit', {})))),
          throwsA(isA<ErreurProtocole>().having((e) => e.code, 'code', 'lot_trop_grand')));
      final r = await env.sync.preparerReception(t.appareilId, 0, limite: 100000);
      final tables = {for (final c in r.changements) c.enregistrement.table};
      for (final interdite in ['journal_audit', 'journal_sync', 'conflit', 'appareil', 'appareil_etablissement', 'appairage_code']) {
        expect(tables, isNot(contains(interdite)), reason: interdite);
      }
      expect(r.changements.any((c) => c.enregistrement.etablissementId == env.etabB), isFalse);
      expect(r.changements.any((c) => c.enregistrement.id == env.eleveB), isFalse);
    });

    test('jeton : absent, inventé ou d\'un appareil bloqué', () async {
      for (final j in [null, 'jeton-invente']) {
        await expectLater(env.jetons.appareilDuJeton(j), throwsA(isA<ErreurProtocole>().having((e) => e.codeHttp, 'codeHttp', 401)));
      }
      await t.sync();
      await env.depot.transaction((tx) async {
        final a = (await tx.lire('appareil', t.appareilId))!;
        await tx.ecrire(a.copier(version: a.version + 1, donnees: {...a.donnees, 'bloque': true}));
      });
      await expectLater(t.sync(), throwsA(isA<ErreurProtocole>().having((e) => e.code, 'code', 'appareil_bloque')));
    });
  });
}
