import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:sssu_mobile/data/base_locale.dart' hide Utilisateur, Eleve;
import 'package:sssu_mobile/data/depot_local_drift.dart';
import 'package:sssu_mobile/data/requetes.dart';
import 'package:sssu_mobile/fichiers/stockage_chiffre.dart';
import 'package:sssu_mobile/import/lecteurs.dart';
import 'package:sssu_mobile/import/service_import.dart';
import 'package:sssu_mobile/visite/depot_visite.dart';

void main() {
  late BaseLocale db;
  late DepotLocalDrift depot;
  late Requetes requetes;
  late StockageChiffre fichiers;
  late Directory dossier;
  late AnneeCourante annee;
  late ResumeClasse classe;
  late Utilisateur agent;
  final horloge = HorlogeFixe(DateTime.utc(2026, 11, 10, 8));

  setUp(() async {
    db = BaseLocale(NativeDatabase.memory(setup: (d) => d.execute('PRAGMA foreign_keys = ON;')));
    await db.customStatement(File('../sql/seed/donnees_test.sql').readAsStringSync());
    depot = DepotLocalDrift(db, horloge: horloge, appareilId: 'tel-test');
    requetes = Requetes(db);
    dossier = await Directory.systemTemp.createTemp('sssu_test');
    fichiers = StockageChiffre(dossier, ChiffreurFichiers(List<int>.generate(32, (i) => i)));
    annee = (await requetes.anneeCourante())!;
    final etab = (await requetes.etablissements(annee)).first;
    classe = (await requetes.classes(etab.id, annee)).first;
    final role = await db.customSelect("SELECT id FROM role WHERE code = 'agent'").getSingle();
    final u = await depot.creer('utilisateur', {'identifiant': 'agent1', 'nom': 'AGENT', 'role_id': role.read<String>('id')},
        utilisateurId: 'x');
    agent = Utilisateur.depuisDonnees(u.id, u.donnees);
  });

  tearDown(() async {
    await db.close();
    await dossier.delete(recursive: true);
  });

  test('consultation : établissements, classes et effectifs du jeu de test', () async {
    final etabs = await requetes.etablissements(annee);
    expect(etabs.length, 2);
    expect(etabs.map((e) => e.effectif), everyElement(60));
    expect(etabs.map((e) => e.examines), everyElement(0));
    expect(classe.effectif, 30);
    expect(classe.garcons + classe.filles, 30);
    final eleves = await requetes.elevesDeClasse(classe.id, annee);
    expect(eleves.length, 30);
    final r = await requetes.rechercher(eleves.first.eleve.nom.substring(0, 3), annee);
    expect(r.map((l) => l.eleve.id), contains(eleves.first.eleve.id));
    expect((await requetes.pathologies()).length, 17);
  });

  test('importation CSV : nouveaux élèves, élève déjà connu rattaché, fichier source chiffré', () async {
    final connu = (await requetes.elevesDeClasse(classe.id, annee)).firstWhere((l) => l.eleve.matricule != null);
    final csv = File('${dossier.path}/liste.csv')
      ..writeAsStringSync('LISTE TEST\n'
          'N°;Matricule;Nom et prénoms;Sexe;Date de naissance\n'
          '1;${connu.eleve.matricule};${connu.eleve.nom} ${connu.eleve.prenoms};${connu.eleve.sexe.code};\n'
          '2;55555555E;BAMBA Awa;F;05/06/2016\n'
          '3;66666666F;TOURE Moussa;G;31/02/2016\n'
          '4;;KONE;F;01/01/2016\n');
    final t = await lireListe(csv.path);
    expect(t.correspondance.values, contains(ChampListe.nomPrenoms));
    final lignes = analyserTableau(t);
    controlerLignes(lignes, existants: await requetes.identitesEleves(), dateReference: horloge.maintenant());
    expect(lignes[0].action, ActionImport.rattacher);
    expect(lignes[2].anomalies.any((a) => a.message.startsWith('Date de naissance illisible')), isTrue);
    expect(lignes[3].bloquee, isTrue, reason: 'prénoms manquants');
    expect(bilan(lignes).validable, isFalse);

    // L'utilisateur écarte la ligne incomplète.
    lignes[3].imposerAction(ActionImport.ignorer);
    controlerLignes(lignes, existants: await requetes.identitesEleves(), dateReference: horloge.maintenant());
    final r = await ServiceImport(db, depot, fichiers).enregistrer(
      lignes: lignes,
      classe: ClasseCible(classe.id, classe.etablissementId, classe.anneeScolaireId),
      tableau: t,
      nomFichier: 'liste.csv',
      octetsSource: csv.readAsBytesSync(),
      utilisateurId: agent.id,
    );
    expect((r.crees, r.rattaches, r.ignores), (2, 1, 1));
    final apres = await requetes.elevesDeClasse(classe.id, annee);
    expect(apres.length, 32);
    expect(apres.where((l) => l.eleve.matricule == '55555555E').single.eleve.dateNaissance, DateTime.utc(2016, 6, 5));
    // Nouveaux élèves et inscriptions à transmettre ; journal d'importation local.
    final attente = await depot.enAttente(limite: 100);
    expect(attente.where((e) => e.table == 'eleve').length, 2);
    expect(attente.where((e) => e.table == 'inscription').length, 2);
    expect(attente.every((e) => e.etablissementId == classe.etablissementId), isTrue);
    expect((await depot.chercher('import_ligne', {'import_lot_id': r.lotId})).length, 4);
    expect(await fichiers.lire('imports/${r.lotId}.enc'), csv.readAsBytesSync());
    expect(File('${dossier.path}/imports/${r.lotId}.enc').readAsBytesSync(), isNot(csv.readAsBytesSync()));
  });

  test('lecture d\'un classeur Excel', () async {
    final x = Excel.createExcel();
    final f = x['Classe'];
    f.appendRow([TextCellValue('Liste')]);
    f.appendRow([TextCellValue('Matricule'), TextCellValue('Nom'), TextCellValue('Prénoms'), TextCellValue('Sexe'), TextCellValue('Né(e) le')]);
    f.appendRow([TextCellValue('12121212A'), TextCellValue('YAO'), TextCellValue('Koffi'), TextCellValue('M'),
      DateCellValue(year: 2014, month: 1, day: 2)]);
    final lignes = lireXlsx(Uint8List.fromList(x.save()!));
    final t = tableauDepuisLignes(lignes, format: 'xlsx');
    expect(t.ligneEntete, 1);
    final l = analyserTableau(t).single;
    expect((l.nom, l.prenoms, l.sexe, l.dateNaissance), ('YAO', 'Koffi', Sexe.masculin, DateTime.utc(2014, 1, 2)));
    await expectLater(lireListe('${dossier.path}/ancien.xls'), throwsA(isA<ErreurImport>()));
  });

  test('dossier de visite : ébauche locale, rechargement, transmission de tous les éléments', () async {
    final eleve = (await requetes.elevesDeClasse(classe.id, annee)).first;
    final dv = DepotVisite(db, depot);
    final d = await dv.nouvelle(
        eleveId: eleve.eleve.id,
        inscriptionId: eleve.inscriptionId,
        etablissementId: eleve.etablissementId,
        agent: agent,
        date: DateTime.utc(2026, 11, 10));
    final patho = (await requetes.pathologies()).firstWhere((p) => p.code == 'caries');
    d.formulaire
      ..poidsKg = 30
      ..tailleCm = 135
      ..conclusion = ConclusionVisite.suivi
      ..diagnostic = 'Caries'
      ..pathologies[patho.id] = '2 dents';
    d.formulaire.antecedents[TypeAntecedent.allergique]!
      ..coche = true
      ..commentaire = 'Pénicilline';
    d.formulaire.examens[AppareilExamen.buccoDentaire]!
      ..resultat = ResultatExamen.anormal
      ..observation = 'Caries molaires';
    await dv.enregistrer(d, utilisateurId: agent.id);

    expect(d.etat, EtatSync.local);
    expect(await depot.enAttente(limite: 100), isEmpty, reason: 'une ébauche n\'est pas transmise');

    final relu = await dv.charger(d.formulaire.id!);
    expect(relu.formulaire.donneesVisite(), d.formulaire.donneesVisite());
    expect(relu.formulaire.antecedents[TypeAntecedent.allergique]!.commentaire, 'Pénicilline');
    expect(relu.formulaire.examens[AppareilExamen.buccoDentaire]!.resultat, ResultatExamen.anormal);
    expect(relu.formulaire.pathologies, {patho.id: '2 dents'});

    // Pathologie retirée : la ligne jamais transmise disparaît.
    relu.formulaire.pathologies.clear();
    await dv.enregistrer(relu, utilisateurId: agent.id);
    expect(await depot.chercher('visite_pathologie', {'visite_id': d.formulaire.id}), isEmpty);

    await dv.transmettre(relu, utilisateurId: agent.id);
    final attente = await depot.enAttente(limite: 100);
    expect(attente.map((e) => e.table).toSet(), {'visite', 'antecedent', 'examen_appareil'});
    expect(attente.firstWhere((e) => e.table == 'visite').donnees['statut'], 'en_attente');
    expect(attente.every((e) => e.etablissementId == eleve.etablissementId), isTrue);

    // L'élève compte désormais comme examiné.
    final c = (await requetes.classes(classe.etablissementId, annee)).firstWhere((x) => x.id == classe.id);
    expect(c.examines, 1);

    // Nouvelle visite : antécédents repris de la précédente.
    final suivante = await dv.nouvelle(
        eleveId: eleve.eleve.id,
        inscriptionId: eleve.inscriptionId,
        etablissementId: eleve.etablissementId,
        agent: agent,
        date: DateTime.utc(2027, 3, 1));
    expect(suivante.formulaire.antecedents[TypeAntecedent.allergique]!.coche, isTrue);
  });

  test('suppression d\'une ébauche jamais transmise', () async {
    final eleve = (await requetes.elevesDeClasse(classe.id, annee)).first;
    final dv = DepotVisite(db, depot);
    final d = await dv.nouvelle(
        eleveId: eleve.eleve.id,
        inscriptionId: eleve.inscriptionId,
        etablissementId: eleve.etablissementId,
        agent: agent,
        date: DateTime.utc(2026, 11, 10));
    d.formulaire.antecedents[TypeAntecedent.personnel]!.coche = true;
    await dv.enregistrer(d, utilisateurId: agent.id);
    expect((await requetes.ebauches()).length, 1);
    await dv.supprimerEbauche(d, utilisateurId: agent.id);
    expect(await requetes.ebauches(), isEmpty);
    expect(await depot.chercher('antecedent', {'visite_id': d.formulaire.id}), isEmpty);
  });
}
