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

  test('l\'identité du téléphone se restaure depuis sa graine', () async {
    final id = await IdentiteAppareil.generer('app-1');
    final restauree = await IdentiteAppareil.depuisGraine('app-1', await id.graine());
    expect(await restauree.clePubliqueBase64(), await id.clePubliqueBase64());
  });
}
