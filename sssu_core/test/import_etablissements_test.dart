import 'package:excel/excel.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

import 'outils/environnement.dart';

/// Importation de la liste des établissements.
void main() {
  late Environnement env;
  late ServiceGestion gestion;
  setUp(() async {
    env = await Environnement.creer();
    gestion = ServiceGestion(depot: env.depot, horloge: env.horloge, hacheur: HacheurMotDePasse(parametres: ParametresArgon2.tests));
  });

  Future<List<EtablissementExistant>> existants() async => [
        for (final e in await env.depot.transaction((tx) => tx.chercher('etablissement', const {})))
          EtablissementExistant(e.id, e.donnees['code']! as String, e.donnees['nom']! as String)
      ];

  test('en-tête reconnu, types et statuts lus, code proposé, doublon ignoré', () async {
    final lignes = [
      ['DISTRICT SANITAIRE DE KOUASSI-KOUASSIKRO'],
      ['N°', 'Nom de l\'établissement', 'Statut', 'Ordre d\'enseignement', 'Localité', 'Nom du directeur', 'Contact'],
      ['1', 'EPP Agbo 2', 'Public', 'Primaire', 'Agbo', 'M. YAO', '0707070707'],
      ['2', 'Collège Saint-Joseph', 'Privé confessionnel', '', 'Kouassikro', 'Sœur MARIE', ''],
      ['3', 'Jardin d\'enfants Les Colombes', '', '', 'Kouassikro', '', ''],
      ['4', 'EPP Agbo 2', 'Public', 'Primaire', 'Agbo', 'M. YAO', ''],
      ['', '', '', '', '', '', ''],
      ['', 'TOTAL', '', '', '', '', ''],
    ];
    final e = detecterEnteteEtablissements(lignes)!;
    expect(e.$1, 1);
    expect(e.$2.values, containsAll([ChampEtablissement.nom, ChampEtablissement.statut, ChampEtablissement.type,
      ChampEtablissement.localite, ChampEtablissement.responsable, ChampEtablissement.telephone]));
    final l = analyserEtablissements(lignes, ligneEntete: e.$1, correspondance: e.$2, existants: await existants());
    expect(l.map((x) => x.nom), ['EPP Agbo 2', 'Collège Saint-Joseph', 'Jardin d\'enfants Les Colombes', 'EPP Agbo 2', 'TOTAL']);
    expect(l[0].type, TypeEtablissement.primaire);
    expect(l[0].statut, StatutEtablissement.public);
    expect(l[0].code, 'EPPAGB2');
    expect(l[1].type, TypeEtablissement.secondaire);
    expect(l[1].statut, StatutEtablissement.prive);
    expect(l[2].type, TypeEtablissement.prescolaire);
    expect(l[2].avertissements.join(), contains('Statut non précisé'));
    expect(l[3].action, ActionEtablissement.ignorer, reason: 'doublon');
    l[4].action = ActionEtablissement.ignorer; // ligne de total écartée par l'utilisateur
    final b = bilanEtablissements(l);
    expect((b.aCreer, b.aMettreAJour, b.ignorees, b.bloquees), (3, 0, 2, 0));

    final r = await gestion.importerEtablissements(await env.droits(env.admin), l);
    expect((r.crees, r.misAJour, r.ignores), (3, 0, 2));
    final tous = await existants();
    expect(tous.map((x) => x.nom), containsAll(['EPP Agbo 2', 'Collège Saint-Joseph']));
  });

  test('établissement connu (même code ou même nom) : mis à jour sans effacer ses autres champs', () async {
    final connus = await existants();
    final a = connus.first;
    final lignes = [
      ['Code', 'Nom', 'Responsable'],
      [a.code.toLowerCase(), a.nom, 'Mme KONAN'],
    ];
    final e = detecterEnteteEtablissements(lignes)!;
    final l = analyserEtablissements(lignes, ligneEntete: e.$1, correspondance: e.$2, existants: connus);
    expect(l.single.action, ActionEtablissement.mettreAJour);
    expect(l.single.existantId, a.id);
    final avant = (await env.depot.transaction((tx) => tx.lire('etablissement', a.id)))!.donnees;
    final r = await gestion.importerEtablissements(await env.droits(env.admin), l);
    expect(r.misAJour, 1);
    final apres = (await env.depot.transaction((tx) => tx.lire('etablissement', a.id)))!.donnees;
    expect(apres['responsable'], 'Mme KONAN');
    expect([apres['type'], apres['statut'], apres['code']], [avant['type'], avant['statut'], avant['code']]);
    // Même liste une seconde fois : rien à changer.
    final l2 = analyserEtablissements(lignes, ligneEntete: e.$1, correspondance: e.$2, existants: await existants());
    expect((await gestion.importerEtablissements(await env.droits(env.admin), l2)).misAJour, 0);
  });

  test('ligne sans nom bloquante ; droit de gérer les établissements exigé', () async {
    final lignes = [
      ['Code', 'Nom', 'Type'],
      ['X1', '', 'Primaire'],
    ];
    final l = analyserEtablissements(lignes, ligneEntete: 0,
        correspondance: {0: ChampEtablissement.code, 1: ChampEtablissement.nom, 2: ChampEtablissement.type},
        existants: const []);
    expect(l.single.bloquee, isTrue);
    expect(bilanEtablissements(l).validable, isFalse);
    l.single.action = ActionEtablissement.ignorer;
    expect(bilanEtablissements(l).validable, isFalse, reason: 'rien à importer');
    final ok = analyserEtablissements([['Nom'], ['EPP Test']], ligneEntete: 0,
        correspondance: {0: ChampEtablissement.nom}, existants: const []);
    await expectLater(gestion.importerEtablissements(await env.droits(env.agent1), ok), throwsA(anything));
  });

  test('modèle Excel lisible et reconnu', () {
    final x = Excel.decodeBytes(modeleListeEtablissements());
    final rows = x.tables['Etablissements']!.rows;
    final lignes = [for (final r in rows) [for (final c in r) c?.value?.toString() ?? '']];
    final e = detecterEnteteEtablissements(lignes)!;
    expect(e.$2.length, 9);
    expect(lireTypeEtablissement(lignes[1][2]), TypeEtablissement.primaire);
  });
}
