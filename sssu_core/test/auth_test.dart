import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

void main() {
  final hacheur = HacheurMotDePasse(parametres: ParametresArgon2.tests);

  group('Hachage Argon2id', () {
    test('format PHC, vérification et sel aléatoire', () async {
      final h1 = await hacheur.hacher('Secret-2026');
      final h2 = await hacheur.hacher('Secret-2026');
      expect(h1, startsWith(r'$argon2id$v=19$m=1024,t=1,p=1$'));
      expect(h1, isNot(h2));
      expect(await hacheur.verifier('Secret-2026', h1), isTrue);
      expect(await hacheur.verifier('secret-2026', h1), isFalse);
    });

    test('empreinte absente ou corrompue', () async {
      expect(await hacheur.verifier('x', null), isFalse);
      expect(await hacheur.verifier('x', r'$argon2id$v=19$m=1024$abc$def'), isFalse);
      expect(await hacheur.verifier('x', 'texte'), isFalse);
    });

    test('les paramètres sont lus dans l\'empreinte stockée', () async {
      final ancien = await HacheurMotDePasse(parametres: const ParametresArgon2(memoireKio: 512, iterations: 1, parallelisme: 1))
          .hacher('Secret-2026');
      expect(await hacheur.verifier('Secret-2026', ancien), isTrue);
    });
  });

  group('Règles de saisie', () {
    test('mot de passe', () {
      expect(controlerMotDePasse('court1'), isNotNull);
      expect(controlerMotDePasse('sanschiffre'), isNotNull);
      expect(controlerMotDePasse('12345678'), isNotNull);
      expect(controlerMotDePasse('Visite2026'), isNull);
    });

    test('code PIN', () {
      expect(controlerPin('12345'), isNotNull);
      expect(controlerPin('111111'), isNotNull);
      expect(controlerPin('123456'), isNotNull);
      expect(controlerPin('654321'), isNotNull);
      expect(controlerPin('482915'), isNull);
    });
  });

  group('Droits', () {
    test('matrice : l\'administrateur n\'accède pas aux données médicales', () {
      final admin = matriceParDefaut[RoleCode.admin]!;
      expect(admin, contains(Permission.comptesGerer));
      expect(admin.where((p) => p.code.startsWith('visite.') || p.code.startsWith('photo.')), isEmpty);
    });

    test('modification des visites selon le rôle', () {
      final agent = Droits(utilisateurId: 'a1', role: RoleCode.agent, permissions: matriceParDefaut[RoleCode.agent]!);
      final chef = Droits(
          utilisateurId: 'c1', role: RoleCode.medecinChef, permissions: matriceParDefaut[RoleCode.medecinChef]!);
      expect(agent.peutModifierVisite(agentId: 'a1', validee: false), isTrue);
      expect(agent.peutModifierVisite(agentId: 'a2', validee: false), isFalse);
      expect(chef.peutModifierVisite(agentId: 'a2', validee: false), isTrue);
      expect(chef.peutModifierVisite(agentId: 'a2', validee: true), isFalse);
      expect(agent.peutVoirPhoto(auteurId: 'a2'), isFalse);
      expect(chef.peutVoirPhoto(auteurId: 'a2'), isTrue);
    });

    test('codes de permission uniques et reconnus', () {
      final codes = Permission.values.map((p) => p.code).toSet();
      expect(codes.length, Permission.values.length);
      for (final c in codes) {
        expect(Permission.depuisCode(c)?.code, c);
      }
      expect(Permission.depuisCode('inconnue'), isNull);
    });
  });

  group('Connexion', () {
    late DepotUtilisateursMemoire depot;
    late HorlogeFixe horloge;
    late ServiceAuthentification auth;
    late Droits droitsAdmin;

    setUp(() async {
      depot = DepotUtilisateursMemoire();
      horloge = HorlogeFixe(DateTime.utc(2026, 11, 10, 8));
      auth = ServiceAuthentification(depot: depot, hacheur: hacheur, horloge: horloge);
      final admin =
          await auth.creerPremierAdministrateur(identifiant: 'Admin', nom: 'Admin', motDePasse: 'Admin-2026');
      droitsAdmin = await auth.droitsDe(admin);
    });

    test('un seul premier administrateur', () async {
      await expectLater(
          () => auth.creerPremierAdministrateur(identifiant: 'admin2', nom: 'X', motDePasse: 'Admin-2026'),
          throwsA(isA<ErreurAutorisation>()));
    });

    test('connexion réussie, identifiant insensible à la casse', () async {
      final r = await auth.connecter('ADMIN ', 'Admin-2026');
      expect(r.reussie, isTrue);
      expect(r.session!.droits.role, RoleCode.admin);
      expect(r.session!.doitChangerMotDePasse, isFalse);
    });

    test('création de compte réservée et changement obligatoire du mot de passe temporaire', () async {
      final u = await auth.creerUtilisateur(droitsAdmin,
          identifiant: 'agent1', nom: 'Agent', role: RoleCode.agent, motDePasseTemporaire: 'Temp-2026');
      final r = await auth.connecter('agent1', 'Temp-2026');
      expect(r.session!.doitChangerMotDePasse, isTrue);

      await expectLater(
          () => auth.creerUtilisateur(r.session!.droits,
              identifiant: 'x1', nom: 'X', role: RoleCode.agent, motDePasseTemporaire: 'Temp-2026'),
          throwsA(isA<ErreurAutorisation>()));
      await expectLater(
          () => auth.creerUtilisateur(droitsAdmin,
              identifiant: 'agent1', nom: 'Doublon', role: RoleCode.agent, motDePasseTemporaire: 'Temp-2026'),
          throwsA(isA<ErreurSaisie>()));

      final s = await auth.changerMotDePasse(r.session!, ancien: 'Temp-2026', nouveau: 'Terrain-2026');
      expect(s.doitChangerMotDePasse, isFalse);
      expect((await auth.connecter('agent1', 'Terrain-2026')).reussie, isTrue);
      expect((await auth.connecter('agent1', 'Temp-2026')).reussie, isFalse);
      expect(u.id, s.utilisateur.id);
    });

    test('blocage 15 minutes après 5 échecs', () async {
      for (var i = 0; i < 4; i++) {
        expect((await auth.connecter('admin', 'mauvais-1')).motif, MotifEchec.identifiantsInvalides);
      }
      final cinquieme = await auth.connecter('admin', 'mauvais-1');
      expect(cinquieme.motif, MotifEchec.compteBloque);
      // Même le bon mot de passe est refusé pendant le blocage.
      expect((await auth.connecter('admin', 'Admin-2026')).motif, MotifEchec.compteBloque);
      horloge.avancer(const Duration(minutes: 15, seconds: 1));
      expect((await auth.connecter('admin', 'Admin-2026')).reussie, isTrue);
    });

    test('compte désactivé', () async {
      final u = await auth.creerUtilisateur(droitsAdmin,
          identifiant: 'parti', nom: 'Parti', role: RoleCode.infirmier, motDePasseTemporaire: 'Temp-2026');
      await depot.enregistrer(u.copier(actif: false));
      expect((await auth.connecter('parti', 'Temp-2026')).motif, MotifEchec.compteInactif);
    });

    test('identifiant inconnu', () async {
      expect((await auth.connecter('personne', 'Admin-2026')).motif, MotifEchec.identifiantsInvalides);
    });

    test('déverrouillage par code PIN', () async {
      final r = await auth.connecter('admin', 'Admin-2026');
      expect((await auth.connecterParPin(r.session!.utilisateur.id, '482915')).motif, MotifEchec.pinNonDefini);
      await expectLater(() => auth.definirPin(r.session!, '123456'), throwsA(isA<ErreurSaisie>()));
      await auth.definirPin(r.session!, '482915');
      expect((await auth.connecterParPin(r.session!.utilisateur.id, '482915')).reussie, isTrue);
      expect((await auth.connecterParPin(r.session!.utilisateur.id, '482916')).reussie, isFalse);
    });
  });
}
