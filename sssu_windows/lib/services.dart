import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sssu_core/sssu_core.dart';

import 'config.dart';
import 'donnees/depot_postgres.dart';
import 'donnees/migrations.dart';
import 'donnees/requetes_poste.dart';
import 'donnees/source_statistiques.dart';
import 'donnees/stockage_photos.dart';
import 'import/lecteurs_poste.dart';
import 'rapports/service_rapports.dart';
import 'sauvegarde/service_sauvegarde.dart';
import 'serveur/certificat.dart';

/// Services du poste central : base PostgreSQL, authentification et serveur
/// de synchronisation HTTPS (port 8443 par défaut).
class ServicesPoste {
  final ConfigPoste config;
  final DepotPostgres depot;
  final DepotUtilisateursServeur depotUtilisateurs;
  final ServiceAuthentification auth;
  final ServiceSynchronisation sync;
  final ServiceAppairage appairage;
  final ServiceJetons jetons;
  final ServiceConflits conflits;
  final CertificatPoste certificat;
  final ServiceGestion gestion;
  final RequetesPoste requetes;
  final StockagePhotosPoste photos;
  final LecteurListes lecteur;
  late final ServiceFichiers fichiers = ServiceFichiers(depot: depot, stockage: photos);
  late final SourceStatistiquesPoste statistiques = SourceStatistiquesPoste(depot);
  late final ServiceRapports rapports = ServiceRapports(source: statistiques, photos: photos, gestion: gestion);
  late final ServiceSauvegarde sauvegardes = ServiceSauvegarde(
    postgres: config.postgres,
    dossierBin: config.dossierPostgresBin,
    dossierDonnees: config.dossier,
    depot: depot,
    nomPoste: config.nomPoste,
  );

  /// Fichiers de mise à jour du schéma appliqués au démarrage.
  List<MigrationAppliquee> migrations = const [];
  HttpServer? _serveur;
  RepondeurDecouverte? _decouverte;

  ServicesPoste._(this.config, this.depot, this.depotUtilisateurs, this.auth, this.sync, this.appairage, this.jetons,
      this.conflits, this.certificat, this.gestion, this.requetes, this.photos, this.lecteur);

  static Future<ServicesPoste> demarrer() async {
    final config = await ConfigPoste.charger();
    final depot = await DepotPostgres.ouvrir(config.postgres);
    // Mise à jour automatique du schéma (installation ou nouvelle version).
    final migrations = await MigrationsPoste(depot, MigrationsPoste.trouverDossier(configure: config.dossierSql)).appliquer();
    await initialiserRoles(depot);
    final depotUtilisateurs = DepotUtilisateursServeur(depot);
    final s = ServicesPoste._(
      config,
      depot,
      depotUtilisateurs,
      ServiceAuthentification(depot: depotUtilisateurs, politique: const PolitiqueConnexion()),
      ServiceSynchronisation(depot: depot),
      ServiceAppairage(depot: depot),
      ServiceJetons(depot: depot),
      ServiceConflits(depot: depot),
      await CertificatPoste.chargerOuCreer(config.dossier),
      ServiceGestion(depot: depot),
      RequetesPoste(depot),
      await StockagePhotosPoste.ouvrir(config.dossier),
      LecteurListes(cheminTesseract: config.cheminTesseract),
    );
    s.migrations = migrations;
    await s.demarrerServeur();
    s.sauvegardes.demarrerPlanification();
    return s;
  }

  bool get serveurActif => _serveur != null;
  int get port => config.portApi;

  Future<void> demarrerServeur() async {
    final api = construireApi(
      sync: sync,
      appairage: appairage,
      jetons: jetons,
      fichiers: fichiers,
      journalErreurs: (e, pile) => debugPrint('Erreur API : $e\n$pile'),
    );
    _serveur = await shelf_io.serve(api, InternetAddress.anyIPv4, config.portApi,
        securityContext: certificat.contexte());
    // Réponse aux téléphones qui cherchent le poste sur le Wi-Fi (port UDP 8444).
    try {
      _decouverte = await RepondeurDecouverte.demarrer(
          portHttps: config.portApi, empreinteCertificat: certificat.empreinte, nom: config.nomPoste);
    } on SocketException catch (e) {
      // Port occupé : les téléphones utiliseront la dernière adresse connue.
      debugPrint('Découverte sur le Wi-Fi indisponible : $e');
    }
  }

  /// Le poste répond aux recherches des téléphones sur le Wi-Fi.
  bool get decouverteActive => _decouverte != null;

  /// Adresses IPv4 du poste sur le réseau local (pour le QR code d'appairage).
  static Future<List<String>> adressesLocales() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    return [for (final i in interfaces) for (final a in i.addresses) a.address];
  }

  Future<int> compter(String table, [Map<String, Object?> egalites = const {}]) =>
      depot.transaction((tx) async => (await tx.chercher(table, egalites)).length);

  Future<void> arreter() async {
    sauvegardes.arreterPlanification();
    _decouverte?.arreter();
    _decouverte = null;
    await _serveur?.close(force: true);
    _serveur = null;
    await depot.fermer();
  }
}

final servicesProvider = Provider<ServicesPoste>((ref) => throw UnimplementedError('Fourni au démarrage'));
final sessionProvider = StateProvider<Session?>((ref) => null);
