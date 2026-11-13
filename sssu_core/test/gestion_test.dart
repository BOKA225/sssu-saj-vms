import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

import 'outils/environnement.dart';

void main() {
  late Environnement env;
  late ServiceGestion g;
  late Droits admin, chef, agent;

  setUp(() async {
    env = await Environnement.creer();
    g = ServiceGestion(depot: env.depot, horloge: env.horloge, hacheur: HacheurMotDePasse(parametres: ParametresArgon2.tests));
    admin = await env.droits(env.admin);
    chef = await env.droits(env.chef);
    agent = await env.droits(env.agent1);
  });

  Matcher erreur(String debut) => throwsA(isA<ErreurGestion>().having((e) => e.message, 'message', startsWith(debut)));

  /// Visite enregistrée directement sur le poste central (comme reçue d'un téléphone).
  Future<Enregistrement> visite(String eleveId, String etab, {String statut = 'en_attente'}) => env.depot.transaction((tx) async {
        final m = env.horloge.maintenant();
        final v = Enregistrement(
          table: 'visite',
          id: nouvelId(),
          version: 1,
          versionBase: 1,
          createdAt: m,
          updatedAt: m,
          updatedBy: env.agent1.id,
          etablissementId: etab,
          donnees: {'eleve_id': eleveId, 'agent_id': env.agent1.id, 'date_visite': '2026-11-10', 'statut': statut},
        );
        await tx.ecrire(v);
        return v;
      });

  group('Établissements et classes', () {
    test('création réservée, code unique, modification tracée', () async {
      final d = {'nom': 'Lycée TEST', 'code': 'lt-1', 'type': 'secondaire', 'statut': 'public'};
      await expectLater(g.creerEtablissement(agent, d), erreur('Vous n\'êtes pas autorisé'));
      final e = await g.creerEtablissement(chef, d);
      expect(e.donnees['code'], 'LT-1');
      expect(e.etablissementId, e.id);
      await expectLater(g.creerEtablissement(chef, {...d, 'nom': 'Autre'}), erreur('Un établissement porte déjà ce code'));
      await expectLater(g.creerEtablissement(chef, {...d, 'code': 'X', 'type': 'inconnu'}), throwsArgumentError);
      final m = await g.modifierEtablissement(chef, e.id, {'responsable': 'M. TEST'});
      expect(m.version, 2);
      final audit = env.depot.tousDirect('journal_audit').where((j) => j.donnees['enregistrement_id'] == e.id);
      expect(audit.map((j) => j.donnees['action']), ['creation', 'modification']);
    });

    test('classes : unicité, archivage refusé tant qu\'il y a des inscrits', () async {
      final c = await g.creerClasse(chef, etablissementId: env.etabA, anneeScolaireId: env.anneeId, libelle: 'CE2 B');
      await expectLater(g.creerClasse(chef, etablissementId: env.etabA, anneeScolaireId: env.anneeId, libelle: 'CE2 B'),
          erreur('Cette classe existe déjà'));
      await g.archiverClasse(chef, c.id);
      expect(env.depot.lireDirect('classe', c.id)!.supprime, isTrue);
      await expectLater(g.archiverClasse(chef, env.classeA), erreur('Archivage impossible'));
    });

    test('archivage d\'un établissement : refusé s\'il existe des dossiers médicaux', () async {
      await visite(env.eleveA, env.etabA);
      await expectLater(g.archiverEtablissement(admin, env.etabA), erreur('Archivage impossible'));
      await expectLater(g.archiverEtablissement(chef, env.etabB), erreur('Vous n\'êtes pas autorisé'));
      await g.archiverEtablissement(admin, env.etabB);
      expect(env.depot.lireDirect('etablissement', env.etabB)!.supprime, isTrue);
      expect(env.depot.lireDirect('classe', env.classeB)!.supprime, isTrue);
    });

    test('une seule année scolaire active', () async {
      final nouvelle = await g.creerAnnee(chef,
          libelle: '2027-2028', debut: DateTime.utc(2027, 9, 13), fin: DateTime.utc(2028, 7, 14), active: true);
      expect(env.depot.lireDirect('annee_scolaire', env.anneeId)!.donnees['active'], isFalse);
      await g.activerAnnee(chef, env.anneeId);
      expect(env.depot.lireDirect('annee_scolaire', env.anneeId)!.donnees['active'], isTrue);
      expect(env.depot.lireDirect('annee_scolaire', nouvelle.id)!.donnees['active'], isFalse);
      await expectLater(
          g.creerAnnee(chef, libelle: 'X', debut: DateTime.utc(2028, 1, 1), fin: DateTime.utc(2027, 1, 1)), erreur('La date de fin'));
    });
  });

  group('Visites', () {
    test('validation et réouverture selon les droits, avec motif tracé', () async {
      final v = await visite(env.eleveA, env.etabA);
      await expectLater(g.validerVisite(agent, v.id), erreur('Vous n\'êtes pas autorisé'));
      final validee = await g.validerVisite(chef, v.id);
      expect(validee.donnees['statut'], 'valide');
      expect(validee.donnees['validateur_id'], env.chef.id);
      await expectLater(g.rouvrirVisite(chef, v.id, motif: ' '), erreur('Indiquer le motif'));
      await expectLater(g.rouvrirVisite(await env.droits(env.medecin), v.id, motif: 'x'), erreur('Vous n\'êtes pas autorisé'));
      final rouverte = await g.rouvrirVisite(chef, v.id, motif: 'Erreur de poids');
      expect(rouverte.donnees['statut'], 'enregistre');
      expect(rouverte.donnees['validateur_id'], isNull);
      final derniere = env.depot.tousDirect('journal_audit').last;
      expect((derniere.donnees['apres']! as Map)['motif'], 'Erreur de poids');
      final ebauche = await visite(env.eleveA, env.etabA, statut: 'ebauche');
      await expectLater(g.validerVisite(chef, ebauche.id), erreur('Une ébauche'));
    });
  });

  group('Diffusion aux téléphones', () {
    Future<List<Enregistrement>> recevoir(String appareilId, int curseur) async =>
        [for (final c in (await env.sync.preparerReception(appareilId, curseur, limite: 10000)).changements) c.enregistrement];

    test('affectation d\'un nouvel établissement : toutes ses données sont rediffusées, parents d\'abord', () async {
      final tel = await env.appairer('Tel', [env.etabA]);
      final r0 = await env.sync.preparerReception(tel.appareilId, 0, limite: 10000);
      expect(r0.changements.any((c) => c.enregistrement.id == env.eleveB), isFalse);
      await g.affecterEtablissements(admin, tel.appareilId, {env.etabA, env.etabB});
      final recus = await recevoir(tel.appareilId, r0.curseur);
      final ordre = recus.map((e) => e.table).toList();
      expect(recus.map((e) => e.id), containsAll([env.etabB, env.classeB, env.eleveB]));
      expect(ordre.indexOf('etablissement') < ordre.indexOf('classe'), isTrue);
      expect(ordre.indexOf('eleve') < ordre.indexOf('inscription'), isTrue);

      // Retrait de l'établissement A : le téléphone ne reçoit plus ses changements.
      await g.affecterEtablissements(admin, tel.appareilId, {env.etabB});
      final curseur = (await env.sync.preparerReception(tel.appareilId, 0, limite: 10000)).curseur;
      await g.modifierEleve(chef, env.eleveA, {'telephone_contact': '0700000000'});
      expect((await recevoir(tel.appareilId, curseur)).where((e) => e.id == env.eleveA), isEmpty);
    });

    test('changement d\'établissement : le dossier médical suit l\'élève', () async {
      final v = await visite(env.eleveA, env.etabA);
      final telB = await env.appairer('Tel B', [env.etabB]);
      final curseur = (await env.sync.preparerReception(telB.appareilId, 0, limite: 10000)).curseur;
      final inscription = (await env.depot.transaction((tx) => tx.chercher('inscription', {'eleve_id': env.eleveA}))).single;
      await g.changerClasse(chef, inscription.id, env.classeB);
      final recus = await recevoir(telB.appareilId, curseur);
      final ids = recus.map((e) => e.id).toList();
      expect(ids, containsAll([env.eleveA, v.id, inscription.id]));
      expect(ids.indexOf(env.eleveA) < ids.indexOf(inscription.id), isTrue);
    });

    test('inscription envoyée par un téléphone pour un élève d\'un autre établissement', () async {
      final tel = await env.appairer('Tel', [env.etabA, env.etabB]);
      final m = env.horloge.maintenant();
      // L'élève B (établissement B) est réinscrit dans la classe A : son inscription existante est modifiée.
      final ins = (await env.depot.transaction((tx) => tx.chercher('inscription', {'eleve_id': env.eleveB}))).single;
      final modif = ins.copier(
          version: 2,
          versionBase: 1,
          updatedAt: m,
          updatedBy: env.medecin.id,
          etablissementId: env.etabA,
          donnees: {...ins.donnees, 'classe_id': env.classeA});
      final a = (await env.sync.recevoirEnvoi(tel.appareilId, DemandeEnvoi(enregistrements: [modif]))).accuses.single;
      expect(a.statut, StatutAccuse.accepte);
      expect(env.depot.lireDirect('eleve', env.eleveB)!.etablissementId, env.etabA);
    });
  });

  group('Importation sur le poste central', () {
    test('création, rattachement, journal', () async {
      final t = tableauDepuisLignes([
        ['Matricule', 'Nom', 'Prénoms', 'Sexe', 'Date de naissance'],
        ['87654321B', 'KONAN', 'Aya', 'F', '12/04/2015'],
        ['44444444D', 'YAO', 'Koffi', 'M', '02/01/2015'],
      ], format: 'csv');
      final lignes = analyserTableau(t);
      final existants = [
        for (final e in env.depot.tousDirect('eleve'))
          IdentiteEleve(id: e.id, matricule: e.donnees['matricule'] as String?, nom: e.donnees['nom']! as String, prenoms: e.donnees['prenoms']! as String),
      ];
      controlerLignes(lignes, existants: existants, dateReference: env.horloge.maintenant());
      expect(lignes.first.action, ActionImport.rattacher);
      await expectLater(
          g.importerListe(agent, lignes: lignes, classeId: env.classeA, format: 'csv', nomFichier: 'l.csv', empreinteSha256: 'x'),
          erreur('Vous n\'êtes pas autorisé'));
      final r = await g.importerListe(await env.droits(env.medecin),
          lignes: lignes, classeId: env.classeA, format: 'csv', nomFichier: 'l.csv', empreinteSha256: 'x');
      expect((r.crees, r.rattaches, r.changementsDeClasse), (1, 1, 1));
      // L'élève B (établissement B) rejoint la classe A : dossier réaffecté.
      expect(env.depot.lireDirect('eleve', env.eleveB)!.etablissementId, env.etabA);
      expect(env.depot.tousDirect('import_ligne').length, 2);
    });

    test('fichier de plusieurs classes : un lot par classe, en une seule importation', () async {
      final medecin = await env.droits(env.medecin);
      final g1 = await g.creerClasse(chef,
          etablissementId: env.etabA, anneeScolaireId: env.anneeId, libelle: '2nde G1', niveau: niveauDeClasse('2nde G1'));
      expect(g1.donnees['niveau'], '2NDE');
      final groupes = grouperParClasse([
        tableauDepuisLignes([
          ['N°', 'Classe', 'Nom', 'Prénoms', 'Sexe', 'Date de naissance'],
          ['1', 'CM2 A', 'SORO', 'Ali', 'M', '03/05/2014'],
          ['2', '2nd G1', 'KOFFI', 'Ange', 'F', '12/09/2009'],
        ], format: 'xlsx', feuille: 'Liste'),
      ]);
      expect(groupes.map((x) => x.classeLue!.libelle), ['CM2 A', '2nde G1']);
      final lignes = [
        for (final gr in groupes)
          for (final l in analyserTableau(gr.tableau)) l..groupe = gr.libelle
      ];
      controlerLignes(lignes, dateReference: env.horloge.maintenant());
      final parties = [
        PartieImport(env.classeA, [lignes[0]], origine: groupes[0].origine),
        PartieImport(g1.id, [lignes[1]], origine: groupes[1].origine),
      ];
      await expectLater(
          g.importerListes(medecin,
              parties: [parties[0], PartieImport(env.classeA, [lignes[1]])],
              format: 'xlsx',
              nomFichier: 'eleves.xlsx',
              empreinteSha256: 'x'),
          erreur('Deux parties du fichier'));
      final lots = env.depot.tousDirect('import_lot').length;
      final r = await g.importerListes(medecin, parties: parties, format: 'xlsx', nomFichier: 'eleves.xlsx', empreinteSha256: 'x');
      expect(r.map((x) => x.crees), [1, 1]);
      expect(env.depot.tousDirect('import_lot').length, lots + 2);
      final noms = env.depot.tousDirect('import_lot').map((l) => l.donnees['fichier_nom']).toList();
      expect(noms, contains('eleves.xlsx — Classe « 2nd G1 »'));
      final koffi = env.depot.tousDirect('eleve').singleWhere((e) => e.donnees['nom'] == 'KOFFI');
      final ins = env.depot.tousDirect('inscription').singleWhere((i) => i.donnees['eleve_id'] == koffi.id);
      expect(ins.donnees['classe_id'], g1.id);
    });
  });

  group('Comptes', () {
    test('désactivation, réinitialisation du mot de passe, rôle ; jamais d\'empreinte dans le journal', () async {
      await expectLater(g.definirActif(admin, env.admin.id, actif: false), erreur('Vous ne pouvez pas'));
      await g.definirActif(admin, env.agent2.id, actif: false);
      expect((await env.auth.connecter('agent2', Environnement.motDePasse)).motif, MotifEchec.compteInactif);
      await g.definirActif(admin, env.agent2.id, actif: true);

      await expectLater(g.reinitialiserMotDePasse(admin, env.agent2.id, 'court'), erreur('Le mot de passe'));
      await g.reinitialiserMotDePasse(admin, env.agent2.id, 'Nouveau-2026');
      final r = await env.auth.connecter('agent2', 'Nouveau-2026');
      expect(r.reussie, isTrue);
      expect(r.session!.doitChangerMotDePasse, isTrue);
      final journal = env.depot.tousDirect('journal_audit').map((j) => '${j.donnees['avant']} ${j.donnees['apres']}').join();
      expect(journal, isNot(contains(r'$argon2id')));

      await g.changerRole(admin, env.agent2.id, RoleCode.infirmier);
      expect((await env.auth.connecter('agent2', 'Nouveau-2026')).session!.droits.role, RoleCode.infirmier);
      await expectLater(g.changerRole(admin, env.admin.id, RoleCode.agent), erreur('Vous ne pouvez pas'));
    });

    test('suppression d\'un compte : connexion refusée, identifiant libéré, traces conservées', () async {
      await expectLater(g.supprimerCompte(admin, env.admin.id, motif: 'x'), erreur('Vous ne pouvez pas'));
      await expectLater(g.supprimerCompte(admin, env.agent2.id, motif: '  '), erreur('Indiquez le motif'));
      await expectLater(g.supprimerCompte(agent, env.agent2.id, motif: 'départ'), erreur('Vous n\'êtes pas'));

      await g.supprimerCompte(admin, env.agent2.id, motif: 'Départ du service');
      expect((await env.auth.connecter('agent2', Environnement.motDePasse)).reussie, isFalse);
      final ligne = env.depot.lireDirect('utilisateur', env.agent2.id)!;
      expect(ligne.supprime, isTrue);
      expect(ligne.donnees['nom'], env.agent2.nom);
      expect(ligne.donnees['hash_mot_de_passe'], isNull);
      final journal = env.depot.tousDirect('journal_audit').where((j) => j.donnees['enregistrement_id'] == env.agent2.id);
      expect(journal.any((j) => j.donnees['action'] == 'suppression' && '${j.donnees['apres']}'.contains('Départ du service')),
          isTrue);
      expect('${journal.map((j) => j.donnees['avant'])}', isNot(contains(r'$argon2id')));

      // L'identifiant peut servir à un nouveau compte.
      final nouveau = await env.auth.creerUtilisateur(admin,
          identifiant: 'agent2', nom: 'NOUVEL AGENT', role: RoleCode.agent, motDePasseTemporaire: 'Temp-2026');
      expect((await env.auth.connecter('agent2', 'Temp-2026')).session!.utilisateur.id, nouveau.id);
    });

    test('consultations tracées', () async {
      await g.noterAcces(chef, 'consultation', table: 'eleve', id: env.eleveA);
      final j = env.depot.tousDirect('journal_audit').last;
      expect((j.donnees['action'], j.donnees['utilisateur_id']), ('consultation', env.chef.id));
    });
  });

  test('lecture du TSV de Tesseract', () {
    const tsv = 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n'
        '1\t1\t0\t0\t0\t0\t0\t0\t2480\t3508\t-1\t\n'
        '5\t1\t1\t1\t1\t1\t120\t300\t180\t40\t96.5\tKOUASSI\n'
        '5\t1\t1\t1\t1\t2\t320\t300\t90\t40\t41.0\tAya\n'
        '5\t1\t1\t1\t1\t3\t420\t300\t10\t40\t-1\t \n';
    final mots = motsDepuisTsvTesseract(tsv, page: 2);
    expect(mots.map((m) => m.mot.texte), ['KOUASSI', 'Aya']);
    expect(mots[1].confiance, 41.0);
    expect(mots[0].mot.page, 2);
    expect(mots[0].mot.largeur, 180);
    expect(() => motsDepuisTsvTesseract('pas un tsv'), throwsFormatException);
  });
}
