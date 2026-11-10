import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sssu_core/sssu_core.dart';
import 'package:sssu_windows/donnees/depot_postgres.dart';
import 'package:sssu_windows/donnees/migrations.dart';
import 'package:sssu_windows/donnees/requetes_poste.dart';
import 'package:sssu_windows/donnees/source_statistiques.dart';
import 'package:sssu_windows/donnees/stockage_photos.dart';
import 'package:sssu_windows/rapports/service_rapports.dart';

/// Phase 5 sur PostgreSQL (base de test chargée avec le schéma, le jeu de
/// test et 010_initialiser_journal_sync.sql) : données des statistiques,
/// rapports enregistrés et tracés, grille et paramètres.
void main() {
  final url = Platform.environment['SSSU_PG_TEST_URL'];
  final ignorer = url == null ? 'SSSU_PG_TEST_URL non définie' : null;
  late DepotPostgres depot;
  late SourceStatistiquesPoste source;
  late ServiceGestion gestion;
  late Annee annee;
  final chef = Droits(
      utilisateurId: '01a1c478-0000-7000-8000-00000000c0ef',
      role: RoleCode.medecinChef,
      permissions: matriceParDefaut[RoleCode.medecinChef]!);

  setUpAll(() async {
    if (url == null) return;
    depot = await DepotPostgres.ouvrir(ConfigPostgres.depuisUrl(url));
      await MigrationsPoste(depot, Directory('../sql/postgres')).appliquer();
    source = SourceStatistiquesPoste(depot);
    gestion = ServiceGestion(depot: depot);
    annee = (await RequetesPoste(depot).anneeCourante())!;
  });
  tearDownAll(() async {
    if (url != null) await depot.fermer();
  });

  test('indicateurs calculés depuis PostgreSQL, identiques aux comptages SQL', () async {
    final jeu = await source.charger(annee);
    final s = calculerStatistiques(jeu);
    final r = (await depot.requete(
            "SELECT COUNT(DISTINCT i.eleve_id) AS effectif, COUNT(DISTINCT i.eleve_id) FILTER (WHERE el.sexe = 'F') AS filles "
            'FROM inscription i JOIN classe c ON c.id = i.classe_id JOIN eleve el ON el.id = i.eleve_id '
            "WHERE i.annee_scolaire_id = CAST(@a AS uuid) AND i.statut = 'inscrit' AND i.deleted_at IS NULL "
            'AND c.deleted_at IS NULL AND el.deleted_at IS NULL',
            {'a': annee.id}))
        .single;
    expect(s.generale.effectif, (r['effectif'] as num).toInt());
    expect(s.generale.filles, (r['filles'] as num).toInt());
    expect(s.parEtablissement.map((e) => e.effectif).fold<int>(0, (a, b) => a + b), s.generale.effectif);
    expect(jeu.eleves.every((e) => e.nom == null), isTrue);
    final nominatif = await source.charger(annee, identite: true);
    expect(nominatif.eleves.every((e) => e.nom != null), isTrue);
    expect(await source.repere(), greaterThan(0));
  }, skip: ignorer);

  test('rapport annuel enregistré en PDF et en Excel, export tracé', () async {
    final dossier = await Directory.systemTemp.createTemp('sssu_p5w');
    final rapports = ServiceRapports(
      source: source,
      photos: await StockagePhotosPoste.ouvrir(dossier),
      gestion: gestion,
      polices: PolicesRapport(
        normale: File('assets/polices/DejaVuSans.ttf').readAsBytesSync(),
        grasse: File('assets/polices/DejaVuSans-Bold.ttf').readAsBytesSync(),
      ),
    );
    final entete = await rapports.entete();
    expect(entete.lignes.first, 'MINISTÈRE EN CHARGE DE LA SANTÉ');
    final d = rapportStatistique(await source.charger(annee), const FiltreStatistiques(),
        portee: PorteeRapport.annuel, entete: entete, acteur: chef, genereLe: DateTime.now().toUtc());
    for (final f in FormatRapport.values) {
      final chemin = '${dossier.path}/rapport.${f.extension}';
      await rapports.enregistrer(d, f, chemin, acteur: chef, table: 'annee_scolaire', id: annee.id);
      expect(File(chemin).lengthSync(), greaterThan(1000));
    }
    final audit = await depot.requete("SELECT apres FROM journal_audit WHERE action = 'export' "
        'AND utilisateur_id = CAST(@u AS uuid) ORDER BY survenu_le DESC LIMIT 2', {'u': chef.utilisateurId});
    expect(audit, hasLength(2));
    await dossier.delete(recursive: true);
  }, skip: ignorer);

  test('grille et paramètres enregistrés dans PostgreSQL', () async {
    final libelle = 'Critère de test ${DateTime.now().microsecondsSinceEpoch}';
    final c = await gestion.creerCritere(chef, rubrique: RubriqueInspection.securite, libelle: libelle);
    expect((await source.grille()).any((x) => x.id == c.id && x.actif), isTrue);
    await gestion.activerCritere(chef, c.id, actif: false);
    expect((await source.grille()).firstWhere((x) => x.id == c.id).actif, isFalse);
    await gestion.definirParametres(chef, {'nom_medecin_chef': 'Dr TEST'});
    expect((await source.parametres())['nom_medecin_chef'], 'Dr TEST');
    await gestion.definirParametres(chef, {'nom_medecin_chef': ''});
  }, skip: ignorer);
}
