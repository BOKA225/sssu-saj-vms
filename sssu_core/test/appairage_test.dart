import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

import 'outils/environnement.dart';

Matcher _erreur(String code) => throwsA(isA<ErreurProtocole>().having((e) => e.code, 'code', code));

void main() {
  late Environnement env;

  setUp(() async => env = await Environnement.creer());

  Future<ContenuQrAppairage> preparer() async => env.appairage.preparer(
        acteur: await env.droits(env.admin),
        nomAppareil: 'Téléphone 1',
        titulaireId: env.agent1.id,
        etablissementIds: [env.etabA],
        urlServeur: 'https://192.168.1.10:8443',
        empreinteCertificat: 'ab' * 32,
      );

  test('le QR code se relit à l\'identique', () async {
    final qr = await preparer();
    final relu = ContenuQrAppairage.depuisTexte(qr.versTexte());
    expect(relu.code, qr.code);
    expect(relu.appareilId, qr.appareilId);
    expect(relu.empreinteCertificat, 'ab' * 32);
    expect(qr.code, matches(RegExp(r'^[A-HJ-NP-Z2-9]{8}$')));
    expect(() => ContenuQrAppairage.depuisTexte('{"autre":1}'), throwsFormatException);
  });

  test('seul l\'administrateur prépare un appairage', () async {
    expect(
        () async => env.appairage.preparer(
            acteur: await env.droits(env.chef),
            nomAppareil: 'x',
            etablissementIds: [env.etabA],
            urlServeur: 'u',
            empreinteCertificat: null),
        throwsStateError);
  });

  test('appairage puis jeton', () async {
    final qr = await preparer();
    final id = await IdentiteAppareil.generer(qr.appareilId);
    final rep = await env.appairage.finaliser(
        DemandeAppairage(appareilId: qr.appareilId, code: qr.code.toLowerCase(), clePublique: await id.clePubliqueBase64()));
    expect(rep.etablissements, [env.etabA]);
    final jeton = await env.jetons.emettre(await id.demandeJeton(env.horloge));
    expect(await env.jetons.appareilDuJeton(jeton.jeton), qr.appareilId);
  });

  test('code faux, expiré ou réutilisé : refusé', () async {
    final qr = await preparer();
    final id = await IdentiteAppareil.generer(qr.appareilId);
    final cle = await id.clePubliqueBase64();
    await expectLater(env.appairage.finaliser(DemandeAppairage(appareilId: qr.appareilId, code: 'AAAAAAAA', clePublique: cle)),
        _erreur('code_invalide'));

    env.horloge.avancer(const Duration(minutes: 11));
    await expectLater(env.appairage.finaliser(DemandeAppairage(appareilId: qr.appareilId, code: qr.code, clePublique: cle)),
        _erreur('code_invalide'));

    final qr2 = await preparer();
    final id2 = await IdentiteAppareil.generer(qr2.appareilId);
    final d = DemandeAppairage(appareilId: qr2.appareilId, code: qr2.code, clePublique: await id2.clePubliqueBase64());
    await env.appairage.finaliser(d);
    await expectLater(env.appairage.finaliser(d), _erreur('code_invalide'));
  });

  test('jeton : signature d\'un autre appareil, rejeu, horloge décalée, expiration', () async {
    final vrai = await env.appairer('A', [env.etabA]);
    final intrus = await IdentiteAppareil.generer(vrai.appareilId); // autre clé, même identifiant
    await expectLater(env.jetons.emettre(await intrus.demandeJeton(env.horloge)), _erreur('signature'));

    final demande = await vrai.demandeJeton(env.horloge);
    await env.jetons.emettre(demande);
    await expectLater(env.jetons.emettre(demande), _erreur('rejeu'));

    final decalee = await vrai.demandeJeton(HorlogeFixe(env.horloge.maintenant().add(const Duration(minutes: 6))));
    await expectLater(env.jetons.emettre(decalee), _erreur('horloge'));

    final j = await env.jetons.emettre(await vrai.demandeJeton(env.horloge));
    env.horloge.avancer(const Duration(hours: 1, seconds: 1));
    await expectLater(env.jetons.appareilDuJeton(j.jeton), _erreur('jeton'));
    await expectLater(env.jetons.appareilDuJeton(null), _erreur('jeton'));
  });

  test('téléphone bloqué : jetons refusés', () async {
    final id = await env.appairer('Perdu', [env.etabA]);
    final j = await env.jetons.emettre(await id.demandeJeton(env.horloge));
    await env.appairage.bloquer(id.appareilId, await env.droits(env.admin));
    await expectLater(env.jetons.appareilDuJeton(j.jeton), _erreur('appareil_bloque'));
    await expectLater(env.jetons.emettre(await id.demandeJeton(env.horloge)), _erreur('appareil_bloque'));
  });

  test('téléphone supprimé : retiré de la liste, effacé à son prochain contact, QR code inutilisable', () async {
    final id = await env.appairer('Ancien', [env.etabA]);
    final j = await env.jetons.emettre(await id.demandeJeton(env.horloge));
    final admin = await env.droits(env.admin);
    await expectLater(env.appairage.supprimer(id.appareilId, await env.droits(env.chef)), throwsStateError);
    await env.appairage.supprimer(id.appareilId, admin);
    expect(await env.depot.transaction((tx) => tx.chercher('appareil', const {})),
        isNot(contains(predicate<Enregistrement>((a) => a.id == id.appareilId))));
    await expectLater(env.jetons.appareilDuJeton(j.jeton), _erreur('appareil_bloque'));
    await expectLater(env.jetons.emettre(await id.demandeJeton(env.horloge)), _erreur('appareil_bloque'));
    await env.appairage.supprimer(id.appareilId, admin); // sans effet la seconde fois

    // Appairage préparé mais jamais terminé : le QR code ne sert plus.
    final qr = await env.appairage.preparer(
        acteur: admin, nomAppareil: 'Jamais', etablissementIds: [env.etabA], urlServeur: 'x', empreinteCertificat: null);
    await env.appairage.supprimer(qr.appareilId, admin);
    final autre = await IdentiteAppareil.generer(qr.appareilId);
    await expectLater(
        env.appairage.finaliser(DemandeAppairage(
            appareilId: qr.appareilId, code: qr.code, clePublique: await autre.clePubliqueBase64())),
        _erreur('code_invalide'));
  });

  test('l\'identité du téléphone se restaure depuis sa graine', () async {
    final id = await IdentiteAppareil.generer('app-1');
    final restauree = await IdentiteAppareil.depuisGraine('app-1', await id.graine());
    expect(await restauree.clePubliqueBase64(), await id.clePubliqueBase64());
  });

  group('enregistrement sans QR code', () {
    Future<(IdentiteAppareil, DemandeEnregistrement)> demande(
        {String identifiant = 'agent1', String motDePasse = Environnement.motDePasse, String? nouveau}) async {
      final appareilId = nouvelId();
      final id = await IdentiteAppareil.generer(appareilId);
      return (
        id,
        DemandeEnregistrement(
          identifiant: identifiant,
          motDePasse: motDePasse,
          nouveauMotDePasse: nouveau,
          appareilId: appareilId,
          clePublique: await id.clePubliqueBase64(),
          nomAppareil: 'Téléphone de terrain',
        )
      );
    }

    test('mot de passe faux refusé ; mot de passe temporaire remplacé dans la même demande', () async {
      final (_, faux) = await demande(motDePasse: 'Mauvais-2026');
      await expectLater(env.appairage.enregistrer(faux), _erreur('identifiants'));

      final (_, sansNouveau) = await demande();
      await expectLater(env.appairage.enregistrer(sansNouveau), _erreur('mot_de_passe_temporaire'));
      final (_, nouveauCourt) = await demande(nouveau: 'court');
      await expectLater(env.appairage.enregistrer(nouveauCourt), _erreur('mot_de_passe'));

      final (_, d) = await demande(nouveau: 'Terrain-2026');
      final rep = await env.appairage.enregistrer(d);
      expect(rep.enAttente, isTrue);
      final r = await env.auth.connecter('agent1', 'Terrain-2026');
      expect(r.session!.doitChangerMotDePasse, isFalse);
      // Nouvel essai identique (réponse perdue) : accepté sans doublon.
      final d2 = DemandeEnregistrement(
          identifiant: 'agent1',
          motDePasse: 'Terrain-2026',
          appareilId: d.appareilId,
          clePublique: d.clePublique,
          nomAppareil: d.nomAppareil);
      expect((await env.appairage.enregistrer(d2)).appareilId, d.appareilId);
      expect(env.depot.tousDirect('appareil').where((a) => a.id == d.appareilId).length, 1);
    });

    test('en attente : aucun jeton ; accepté avec ses établissements : jeton et données', () async {
      final (id, d) = await demande(nouveau: 'Terrain-2026');
      await env.appairage.enregistrer(d);
      final appareil = env.depot.lireDirect('appareil', d.appareilId)!;
      expect(appareil.donnees['titulaire_id'], env.agent1.id);
      expect(appareil.donnees['en_attente'], isTrue);
      await expectLater(env.jetons.emettre(await id.demandeJeton(env.horloge)), _erreur('appareil_en_attente'));

      final admin = await env.droits(env.admin);
      // Sans établissement, la validation est refusée.
      await expectLater(env.appairage.accepter(d.appareilId, admin), throwsStateError);
      await expectLater(env.appairage.accepter(d.appareilId, await env.droits(env.chef)), throwsStateError);
      final gestion = ServiceGestion(
          depot: env.depot, horloge: env.horloge, hacheur: HacheurMotDePasse(parametres: ParametresArgon2.tests));
      await gestion.affecterEtablissements(admin, d.appareilId, {env.etabA});
      await env.appairage.accepter(d.appareilId, admin);

      final jeton = await env.jetons.emettre(await id.demandeJeton(env.horloge));
      expect(await env.jetons.appareilDuJeton(jeton.jeton), d.appareilId);
      final reception = await env.sync.preparerReception(d.appareilId, 0);
      final eleves = reception.changements.where((c) => c.enregistrement.table == 'eleve').map((c) => c.enregistrement.id).toSet();
      expect(eleves, contains(env.eleveA));
      expect(eleves, isNot(contains(env.eleveB)));
    });

    test('refus : le téléphone ne peut jamais se synchroniser', () async {
      final (id, d) = await demande(nouveau: 'Terrain-2026');
      await env.appairage.enregistrer(d);
      await env.appairage.refuser(d.appareilId, await env.droits(env.admin));
      await expectLater(env.jetons.emettre(await id.demandeJeton(env.horloge)), _erreur('appareil_inconnu'));
      await expectLater(env.appairage.enregistrer(DemandeEnregistrement(
          identifiant: 'agent1',
          motDePasse: 'Terrain-2026',
          appareilId: d.appareilId,
          clePublique: d.clePublique,
          nomAppareil: 'x')), _erreur('deja_appaire'));
    });

    test('compte désactivé refusé ; trois téléphones en attente au plus par compte', () async {
      final admin = await env.droits(env.admin);
      final gestion = ServiceGestion(
          depot: env.depot, horloge: env.horloge, hacheur: HacheurMotDePasse(parametres: ParametresArgon2.tests));
      await gestion.definirActif(admin, env.agent2.id, actif: false);
      final (_, inactif) = await demande(identifiant: 'agent2', nouveau: 'Terrain-2026');
      await expectLater(env.appairage.enregistrer(inactif), _erreur('identifiants'));

      final (_, premier) = await demande(nouveau: 'Terrain-2026');
      await env.appairage.enregistrer(premier);
      for (var i = 0; i < 2; i++) {
        final (_, d) = await demande(motDePasse: 'Terrain-2026');
        await env.appairage.enregistrer(d);
      }
      final (_, quatrieme) = await demande(motDePasse: 'Terrain-2026');
      await expectLater(env.appairage.enregistrer(quatrieme), _erreur('trop_d_attentes'));
    });
  });
}
