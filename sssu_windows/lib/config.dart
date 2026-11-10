import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'donnees/depot_postgres.dart';

/// Configuration du poste central, lue dans `sssu_config.json` (dossier de
/// l'application). Un fichier modèle est créé au premier lancement.
class ConfigPoste {
  final ConfigPostgres postgres;
  final int portApi;
  final Directory dossier;

  /// Chemin de tesseract.exe (facultatif ; sinon recherche automatique).
  final String? cheminTesseract;

  /// Adresse Internet du poste (ex. `https://sssu-saj.ddns.net:8443`), si le
  /// routeur redirige le port HTTPS vers ce poste. Facultative : sans elle,
  /// les téléphones se synchronisent sur le Wi-Fi du bureau uniquement.
  final String? adresseInternet;

  /// Nom annoncé aux téléphones sur le Wi-Fi.
  final String nomPoste;

  /// Dossier des outils PostgreSQL (pg_dump, pg_restore), renseigné par
  /// l'installateur ; sinon recherche dans le PATH.
  final String? dossierPostgresBin;

  /// Dossier des fichiers de mise à jour du schéma (sinon `sql` à côté de l'exécutable).
  final String? dossierSql;

  ConfigPoste({
    required this.postgres,
    required this.portApi,
    required this.dossier,
    this.cheminTesseract,
    this.adresseInternet,
    this.nomPoste = 'SSSU-SAJ Kouassi-Kouassikro',
    this.dossierPostgresBin,
    this.dossierSql,
  });

  /// Dossier de données de l'installation (Windows) : `%PROGRAMDATA%\SSSU-SAJ VMS`,
  /// créé par l'installateur avec la configuration. À défaut (développement),
  /// dossier de l'application de l'utilisateur.
  static Future<Directory> dossierDonnees() async {
    final programData = Platform.environment['PROGRAMDATA'];
    if (Platform.isWindows && programData != null) {
      final d = Directory(p.join(programData, 'SSSU-SAJ VMS'));
      if (File(p.join(d.path, 'sssu_config.json')).existsSync()) return d;
    }
    return getApplicationSupportDirectory();
  }

  static Future<ConfigPoste> charger() async {
    final dossier = await dossierDonnees();
    final fichier = File(p.join(dossier.path, 'sssu_config.json'));
    if (!fichier.existsSync()) {
      fichier.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        'postgres': {
          'hote': 'localhost',
          'port': 5432,
          'base': 'sssu_saj',
          'utilisateur': 'sssu',
          'mot_de_passe': '',
          'bin': null,
        },
        'dossier_sql': null,
        'port_api': 8443,
        'tesseract': null,
        'adresse_internet': null,
        'nom_poste': 'SSSU-SAJ Kouassi-Kouassikro',
      }));
    }
    final j = jsonDecode(fichier.readAsStringSync()) as Map<String, dynamic>;
    final pg = j['postgres'] as Map<String, dynamic>;
    return ConfigPoste(
      postgres: ConfigPostgres(
        hote: pg['hote'] as String? ?? 'localhost',
        port: pg['port'] as int? ?? 5432,
        base: pg['base'] as String? ?? 'sssu_saj',
        utilisateur: pg['utilisateur'] as String? ?? 'sssu',
        motDePasse: pg['mot_de_passe'] as String? ?? '',
      ),
      portApi: j['port_api'] as int? ?? 8443,
      dossier: dossier,
      cheminTesseract: j['tesseract'] as String?,
      adresseInternet: _adresse(j['adresse_internet'] as String?),
      nomPoste: j['nom_poste'] as String? ?? 'SSSU-SAJ Kouassi-Kouassikro',
      dossierPostgresBin: pg['bin'] as String?,
      dossierSql: j['dossier_sql'] as String?,
    );
  }

  /// Adresse Internet valide (HTTPS, avec hôte) ou `null`.
  static String? _adresse(String? brut) {
    final t = brut?.trim();
    if (t == null || t.isEmpty) return null;
    final u = Uri.tryParse(t);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) {
      throw FormatException('adresse_internet invalide dans sssu_config.json : « $t » (attendu : https://hote:port).');
    }
    return u.toString();
  }

  String get cheminFichier => p.join(dossier.path, 'sssu_config.json');
}
