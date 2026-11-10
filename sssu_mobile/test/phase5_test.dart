import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:sssu_mobile/data/base_locale.dart' hide Utilisateur, Eleve;
import 'package:sssu_mobile/data/depot_local_drift.dart';
import 'package:sssu_mobile/data/requetes.dart';
import 'package:sssu_mobile/fichiers/stockage_chiffre.dart';
import 'package:sssu_mobile/inspection/depot_inspection.dart';

import 'outils/transport_direct.dart';

/// Phase 5 sur la vraie base SQLite : inspection sanitaire (ébauche,
/// transmission avec réponses et photo, rechargement) et statistiques de l'appareil.
void main() {
  final horloge = HorlogeFixe(DateTime.utc(2026, 11, 10, 8));
  late BaseLocale db;
  late Directory dossier;
  late DepotServeurMemoire serveur;
  late StockageFichiersMemoire stockagePoste;
  late DepotLocalDrift depot;
  late DepotInspection inspections;
  late ClientSynchronisation client;
  late Utilisateur agent;
  late String etab;
  late String annee;
  late String classe;
  late List<String> criteres;
  late String eleve;

  setUp(() async {
    db = BaseLocale(NativeDatabase.memory(setup: (d) => d.execute('PRAGMA foreign_keys = ON;')));
    dossier = await Directory.systemTemp.createTemp('sssu_p5');
    final fichiersTel = StockageChiffre(dossier, ChiffreurFichiers(List<int>.generate(32, (i) => i)));
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
    annee = nouvelId();
    classe = nouvelId();
    eleve = nouvelId();
    criteres = [nouvelId(), nouvelId(), nouvelId()];
    await serveur.transaction((tx) async {
      Enregistrement n(String t, Map<String, Object?> d, {String? id, String? portee}) => Enregistrement(
          table: t,
          id: id ?? nouvelId(),
          version: 1,
          versionBase: 1,
          createdAt: horloge.maintenant(),
          updatedAt: horloge.maintenant(),
          etablissementId: portee,
          donnees: d);
      await tx.ecrire(n('etablissement', {'nom': 'École A', 'code': 'A', 'type': 'primaire', 'statut': 'public'},
          id: etab, portee: etab));
      await tx.ecrire(n('annee_scolaire',
          {'libelle': '2026-2027', 'date_debut': '2026-09-01', 'date_fin': '2027-07-31', 'active': true}, id: annee));
      await tx.ecrire(n('classe', {'etablissement_id': etab, 'annee_scolaire_id': annee, 'libelle': 'CP1'},
          id: classe, portee: etab));
      for (final (i, (e, s)) in [(nouvelId(), 'M'), (eleve, 'F')].indexed) {
        await tx.ecrire(n('eleve', {'nom': 'ELEVE$i', 'prenoms': 'X', 'sexe': s}, id: e, portee: etab));
        await tx.ecrire(n('inscription',
            {'eleve_id': e, 'classe_id': classe, 'annee_scolaire_id': annee, 'statut': 'inscrit'}, portee: etab));
      }
      final libelles = [('eau_potable', 'Eau disponible'), ('toilettes', 'Latrines propres'), ('lavage_mains', 'Savon')];
      for (var i = 0; i < 3; i++) {
        await tx.ecrire(n('critere_inspection',
            {'rubrique': libelles[i].$1, 'code': 'k$i', 'libelle': libelles[i].$2, 'ordre': 1, 'actif': true},
            id: criteres[i]));
      }
      await tx.ecrire(n('critere_inspection',
          {'rubrique': 'securite', 'code': 'ancien', 'libelle': 'Critère retiré', 'ordre': 1, 'actif': false}));
    });

    final appairage = ServiceAppairage(depot: serveur, horloge: horloge);
    final jetons = ServiceJetons(depot: serveur, horloge: horloge);
    stockagePoste = StockageFichiersMemoire();
    final transport = TransportDirect(ServiceSynchronisation(depot: serveur, horloge: horloge), appairage, jetons,
        fichiers: ServiceFichiers(depot: serveur, stockage: stockagePoste, horloge: horloge));
    final qr = await appairage.preparer(
        acteur: droitsAdmin, nomAppareil: 'Tel', etablissementIds: [etab], urlServeur: 'x', empreinteCertificat: null);
    final identite = await IdentiteAppareil.generer(qr.appareilId);
    await transport.appairer(
        DemandeAppairage(appareilId: qr.appareilId, code: qr.code, clePublique: await identite.clePubliqueBase64()));
    depot = DepotLocalDrift(db, horloge: horloge, appareilId: qr.appareilId, fichiers: fichiersTel);
    inspections = DepotInspection(db, depot, fichiersTel);
    client = ClientSynchronisation(depot: depot, transport: transport, identite: identite, horloge: horloge);
    await client.synchroniser();
  });

  tearDown(() async {
    await db.close();
    await dossier.delete(recursive: true);
  });

  test('inspection : ébauche gardée sur le téléphone, puis transmise avec ses réponses et sa photo', () async {
    final d = await inspections.nouvelle(
        etablissementId: etab, anneeScolaireId: annee, inspecteurId: agent.id, date: DateTime.utc(2026, 11, 10));
    expect(d.formulaire.criteres.map((c) => c.id).toSet(), criteres.toSet(), reason: 'critères actifs seulement');
    final f = d.formulaire;
    f.reponses[criteres[0]]!.resultat = ResultatInspection.conforme;
    f.reponses[criteres[1]]!
      ..resultat = ResultatInspection.nonConforme
      ..observation = 'Latrines bouchées';
    await inspections.enregistrer(d, utilisateurId: agent.id);
    expect(d.etat, EtatSync.local);
    expect((await client.synchroniser()).acceptes, 0, reason: 'une ébauche n\'est pas transmise');

    // Photo de l'insuffisance, puis transmission refusée tant qu'il manque une réponse et la signature.
    await inspections.enregistrerPhoto(d,
        critereId: criteres[1], jpeg: Uint8List.fromList(List.filled(2000, 7)), auteurId: agent.id);
    await expectLater(inspections.transmettre(d, utilisateurId: agent.id), throwsStateError);
    f.reponses[criteres[2]]!.resultat = ResultatInspection.partiel;
    f.signaturePng = [137, 80, 78, 71];
    await inspections.transmettre(d, utilisateurId: agent.id);
    expect(d.etat, EtatSync.enAttente);

    final r = await client.synchroniser();
    expect(r.acceptes, 5, reason: 'inspection, 3 réponses, 1 photo');
    expect(r.fichiers, 1);
    final poste = serveur.lireDirect('inspection', f.id!)!;
    // (1 + 0,5) / 3 = 50 % : moyen
    expect((poste.donnees['taux_conformite'], poste.donnees['niveau'], poste.donnees['statut']), (50.0, 'moyen', 'enregistre'));
    expect(stockagePoste.fichiers.values.single, List.filled(2000, 7));

    final relue = await inspections.charger(f.id!);
    expect(relue.formulaire.modifiable, isFalse);
    expect(relue.formulaire.reponses[criteres[1]]!.observation, 'Latrines bouchées');
    expect(relue.formulaire.signaturePng, [137, 80, 78, 71]);
    expect((await inspections.inspections(etab)).single.niveau, NiveauConformite.moyen);
  });

  test('suppression d\'une ébauche avec ses réponses et ses photos', () async {
    final d = await inspections.nouvelle(
        etablissementId: etab, anneeScolaireId: annee, inspecteurId: agent.id, date: DateTime.utc(2026, 11, 10));
    d.formulaire.reponses[criteres[0]]!.resultat = ResultatInspection.nonConforme;
    await inspections.enregistrer(d, utilisateurId: agent.id);
    final p = await inspections.enregistrerPhoto(d, critereId: criteres[0], jpeg: Uint8List(10), auteurId: agent.id);
    final chemin = p.donnees['chemin_chiffre']! as String;
    await inspections.supprimerEbauche(d, utilisateurId: agent.id);
    expect(await inspections.inspections(etab), isEmpty);
    expect(await depot.chercher('inspection_reponse', {}), isEmpty);
    expect(await depot.fichiers!.existe(chemin), isFalse);
  });

  test('statistiques de l\'appareil', () async {
    await depot.creer(
        'visite', {'eleve_id': eleve, 'agent_id': agent.id, 'date_visite': '2026-11-10', 'statut': 'en_attente', 'conclusion': 'suivi'},
        utilisateurId: agent.id, etablissementId: etab);
    final jeu = (await Requetes(db).jeuStatistiques())!;
    final s = calculerStatistiques(jeu);
    expect((s.generale.effectif, s.generale.examines, s.generale.fillesExamines, s.generale.tauxCouverture), (2, 1, 1, 50.0));
    expect(s.conclusions[ConclusionVisite.suivi], 1);
    expect(s.inspections.inspectes, 0);
    expect(jeu.eleves.every((e) => e.nom == null), isTrue, reason: 'aucune donnée nominative');
  });
}
