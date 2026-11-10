/// Sauvegarde automatique planifiée et restauration du poste central
/// (section 14) : base PostgreSQL (pg_dump), photographies chiffrées, clé des
/// photos et certificat du poste, dans une archive chiffrée par la phrase de
/// passe de sauvegarde (voir `archive_chiffree.dart`).
///
/// - La phrase de passe est choisie par l'administrateur ; la clé qui en est
///   dérivée est gardée sur le poste, protégée par DPAPI, pour les
///   sauvegardes automatiques. Restaurer exige de ressaisir la phrase.
/// - Sauvegarde quotidienne à l'heure choisie (rattrapée au démarrage si le
///   poste était éteint), conservation des N dernières, dossier réglable
///   (disque externe ou partage réseau recommandé).
/// - Restauration : sauvegarde de sécurité de l'état actuel, arrêt du
///   serveur, remplacement de la base (pg_restore) et des fichiers, nouvelle
///   génération (les téléphones renvoient leurs données plus récentes), puis
///   redémarrage de l'application.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:path/path.dart' as p;
import 'package:sssu_core/sssu_core.dart';

import '../donnees/depot_postgres.dart';
import '../securite/protection_cles.dart';
import 'archive_chiffree.dart';

const versionApplication = '1.0.0';

class ErreurSauvegarde implements Exception {
  final String message;
  const ErreurSauvegarde(this.message);
  @override
  String toString() => message;
}

/// Réglages, enregistrés dans `sauvegarde.json` (dossier de données du poste).
class ReglagesSauvegarde {
  bool active;
  String dossier;
  int heure;
  int minute;
  int conservation;
  Map<String, Object?>? derivation;
  String? controle;
  DateTime? derniereReussie;
  DateTime? derniereTentative;
  String? dernierMessage;
  String? dernierFichier;

  ReglagesSauvegarde({
    this.active = true,
    required this.dossier,
    this.heure = 13,
    this.minute = 0,
    this.conservation = 14,
    this.derivation,
    this.controle,
    this.derniereReussie,
    this.derniereTentative,
    this.dernierMessage,
    this.dernierFichier,
  });

  bool get phraseDefinie => derivation != null && controle != null;

  Map<String, Object?> versJson() => {
        'active': active,
        'dossier': dossier,
        'heure': heure,
        'minute': minute,
        'conservation': conservation,
        'derivation': derivation,
        'controle': controle,
        'derniere_reussie': derniereReussie?.toUtc().toIso8601String(),
        'derniere_tentative': derniereTentative?.toUtc().toIso8601String(),
        'dernier_message': dernierMessage,
        'dernier_fichier': dernierFichier,
      };

  factory ReglagesSauvegarde.depuisJson(Map<String, Object?> j, String dossierParDefaut) => ReglagesSauvegarde(
        active: j['active'] != false,
        dossier: (j['dossier'] as String?) ?? dossierParDefaut,
        heure: (j['heure'] as num?)?.toInt() ?? 13,
        minute: (j['minute'] as num?)?.toInt() ?? 0,
        conservation: (j['conservation'] as num?)?.toInt() ?? 14,
        derivation: (j['derivation'] as Map?)?.cast<String, Object?>(),
        controle: j['controle'] as String?,
        derniereReussie: j['derniere_reussie'] == null ? null : DateTime.parse(j['derniere_reussie']! as String),
        derniereTentative: j['derniere_tentative'] == null ? null : DateTime.parse(j['derniere_tentative']! as String),
        dernierMessage: j['dernier_message'] as String?,
        dernierFichier: j['dernier_fichier'] as String?,
      );
}

/// SHA-256 d'un fichier, lu en flux.
Future<String> empreinteFichier(File f) async {
  final puits = Sha256().newHashSink();
  await for (final m in f.openRead()) {
    puits.add(m);
  }
  puits.close();
  final h = await puits.hash();
  return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class ResultatSauvegarde {
  final File fichier;
  final int taille;
  final int photos;
  final Duration duree;
  const ResultatSauvegarde(this.fichier, this.taille, this.photos, this.duree);
}

class ServiceSauvegarde {
  final ConfigPostgres postgres;
  final String? dossierBin;

  /// Dossier de données du poste (photos, clés, réglages).
  final Directory dossierDonnees;
  final DepotPostgres depot;
  final ProtectionCles protection;
  final Horloge horloge;
  final String nomPoste;

  Timer? _minuterie;
  bool _enCours = false;

  ServiceSauvegarde({
    required this.postgres,
    required this.dossierBin,
    required this.dossierDonnees,
    required this.depot,
    ProtectionCles? protection,
    this.horloge = const HorlogeSysteme(),
    this.nomPoste = 'SSSU-SAJ',
  }) : protection = protection ?? ProtectionCles.systeme();

  File get _fichierReglages => File(p.join(dossierDonnees.path, 'sauvegarde.json'));
  File get _fichierCle => File(p.join(dossierDonnees.path, 'cle_sauvegarde.bin'));
  Directory get _photos => Directory(p.join(dossierDonnees.path, 'photos'));

  bool get enCours => _enCours;

  // ---------------------------------------------------------------- réglages

  Future<ReglagesSauvegarde> reglages() async {
    final defaut = p.join(dossierDonnees.path, 'sauvegardes');
    if (!await _fichierReglages.exists()) return ReglagesSauvegarde(dossier: defaut);
    return ReglagesSauvegarde.depuisJson(
        (jsonDecode(await _fichierReglages.readAsString()) as Map).cast<String, Object?>(), defaut);
  }

  Future<void> _enregistrer(ReglagesSauvegarde r) async {
    await _fichierReglages.parent.create(recursive: true);
    await _fichierReglages.writeAsString(const JsonEncoder.withIndent('  ').convert(r.versJson()), flush: true);
  }

  static void _exiger(Droits a) {
    if (!a.peut(Permission.sauvegardeGerer)) {
      throw const ErreurSauvegarde('Seul l\'administrateur gère les sauvegardes.');
    }
  }

  /// Contrôle d'une phrase de passe de sauvegarde (null si acceptable).
  static String? controlerPhrase(String phrase) {
    if (phrase.trim().length < 12) return 'La phrase de passe doit compter au moins 12 caractères.';
    if (phrase.trim().split(RegExp(r'\s+')).length < 2 && !RegExp(r'\d').hasMatch(phrase)) {
      return 'Utilisez plusieurs mots ou ajoutez des chiffres.';
    }
    return null;
  }

  /// Définit (ou change) la phrase de passe. Les sauvegardes existantes
  /// restent restaurables avec l'ancienne phrase.
  Future<void> definirPhrase(Droits a, String phrase) async {
    _exiger(a);
    final erreur = controlerPhrase(phrase);
    if (erreur != null) throw ErreurSauvegarde(erreur);
    final d = DerivationCle.nouvelle();
    final cle = await d.deriver(phrase);
    final r = await reglages()
      ..derivation = d.versJson()
      ..controle = await controlePhrase(cle);
    await ecrireCle(_fichierCle, cle, protection);
    await _enregistrer(r);
  }

  Future<void> modifierReglages(Droits a,
      {bool? active, String? dossier, int? heure, int? minute, int? conservation}) async {
    _exiger(a);
    final r = await reglages();
    if (dossier != null) {
      final d = Directory(dossier);
      try {
        await d.create(recursive: true);
        final test = File(p.join(d.path, '.essai_ecriture'));
        await test.writeAsString('ok');
        await test.delete();
      } catch (e) {
        throw ErreurSauvegarde('Dossier inaccessible en écriture : $dossier');
      }
      r.dossier = dossier;
    }
    if (heure != null) {
      if (heure < 0 || heure > 23) throw const ErreurSauvegarde('Heure invalide.');
      r.heure = heure;
    }
    if (minute != null) {
      if (minute < 0 || minute > 59) throw const ErreurSauvegarde('Minute invalide.');
      r.minute = minute;
    }
    if (conservation != null) {
      if (conservation < 1 || conservation > 365) throw const ErreurSauvegarde('Conservation : de 1 à 365 sauvegardes.');
      r.conservation = conservation;
    }
    if (active != null) r.active = active;
    await _enregistrer(r);
  }

  // --------------------------------------------------------------- outils PG

  String _outil(String nom) {
    final exe = Platform.isWindows ? '$nom.exe' : nom;
    if (dossierBin != null) {
      final f = File(p.join(dossierBin!, exe));
      if (f.existsSync()) return f.path;
    }
    return exe; // recherche dans le PATH
  }

  Map<String, String> get _env => {'PGPASSWORD': postgres.motDePasse, 'PGCLIENTENCODING': 'UTF8'};

  List<String> get _connexion =>
      ['-h', postgres.hote, '-p', '${postgres.port}', '-U', postgres.utilisateur];

  Future<void> _executer(String outil, List<String> args, String etape) async {
    final ProcessResult r;
    try {
      r = await Process.run(_outil(outil), args, environment: _env, stdoutEncoding: utf8, stderrEncoding: utf8);
    } on ProcessException catch (e) {
      throw ErreurSauvegarde('$etape : $outil introuvable (${e.message}). Vérifiez "bin" dans sssu_config.json.');
    }
    if (r.exitCode != 0) {
      final detail = '${r.stderr}'.trim();
      throw ErreurSauvegarde('$etape : échec ($outil, code ${r.exitCode})${detail.isEmpty ? '' : ' — $detail'}');
    }
  }

  // ---------------------------------------------------------------- sauvegarde

  static String nomFichier(DateTime d, String motif) {
    String z(int n) => n.toString().padLeft(2, '0');
    final l = d.toLocal();
    return 'sssu-saj_${l.year}-${z(l.month)}-${z(l.day)}_${z(l.hour)}h${z(l.minute)}${z(l.second)}_$motif.sssubak';
  }

  /// Sauvegarde complète. [motif] : `manuelle`, `automatique` ou `avant_restauration`.
  Future<ResultatSauvegarde> sauvegarder({String motif = 'manuelle', String? dossier}) async {
    if (_enCours) throw const ErreurSauvegarde('Une sauvegarde est déjà en cours.');
    _enCours = true;
    final debut = DateTime.now();
    final r = await reglages();
    r.derniereTentative = horloge.maintenant();
    File? cible;
    final temp = Directory(p.join(dossierDonnees.path, 'tmp_sauvegarde_${debut.microsecondsSinceEpoch}'));
    try {
      if (!r.phraseDefinie || !await _fichierCle.exists()) {
        throw const ErreurSauvegarde('Définissez d\'abord la phrase de passe des sauvegardes.');
      }
      final cle = await lireCle(_fichierCle, protection);
      final destination = Directory(dossier ?? r.dossier);
      await destination.create(recursive: true);
      await temp.create(recursive: true);

      // 1. Base de données : format « custom » de pg_dump (compressé).
      final dump = File(p.join(temp.path, 'base.dump'));
      await _executer('pg_dump', [..._connexion, '-Fc', '--no-owner', '--no-privileges', '-f', dump.path, postgres.base],
          'Export de la base');

      // 2. Archive chiffrée : manifeste, base, clés, photos.
      final photos = await _photos.exists()
          ? (await _photos.list().where((f) => f is File && f.path.endsWith('.enc')).cast<File>().toList())
          : <File>[];
      final migrations = await depot.requete('SELECT nom FROM schema_migration ORDER BY nom');
      final manifeste = {
        'application': 'SSSU-SAJ VMS',
        'version_application': versionApplication,
        'cree_le': horloge.maintenant().toIso8601String(),
        'poste': nomPoste,
        'motif': motif,
        'base': {'fichier': 'base.dump', 'taille': await dump.length(), 'sha256': await empreinteFichier(dump)},
        'migrations': [for (final m in migrations) m['nom']],
        'photos': photos.length,
      };
      cible = File(p.join(destination.path, nomFichier(debut, motif)));
      final partiel = File('${cible.path}.partiel');
      final ecrivain = await EcrivainArchive.creer(partiel, cle, {
        'format': 1,
        'application': 'SSSU-SAJ VMS',
        'cree_le': manifeste['cree_le'],
        'poste': nomPoste,
        'motif': motif,
        'photos': photos.length,
        'derivation': r.derivation,
        'controle': r.controle,
      });
      try {
        await ecrivain.ajouterOctets('manifeste.json', utf8.encode(jsonEncode(manifeste)));
        await ecrivain.ajouterFichier('base.dump', dump);
        for (final nom in ['cle_photos.bin', 'certificat.pem', 'cle_privee.pem']) {
          final f = File(p.join(dossierDonnees.path, nom));
          if (!await f.exists()) continue;
          // Clés en clair dans l'archive (elle-même chiffrée) : la sauvegarde
          // doit pouvoir être restaurée sur un autre ordinateur.
          await ecrivain.ajouterOctets(nom, nom == 'certificat.pem' ? await f.readAsBytes() : await lireCle(f, protection));
        }
        for (final f in photos) {
          await ecrivain.ajouterFichier('photos/${p.basename(f.path)}', f);
        }
        await ecrivain.fermer();
      } catch (_) {
        await ecrivain.abandonner();
        if (await partiel.exists()) await partiel.delete();
        rethrow;
      }
      await partiel.rename(cible.path);
      final taille = await cible.length();

      await _purger(destination, r.conservation);
      r
        ..derniereReussie = horloge.maintenant()
        ..dernierFichier = cible.path
        ..dernierMessage = 'Sauvegarde réussie (${(taille / 1048576).toStringAsFixed(1)} Mo, ${photos.length} photo(s)).';
      await _enregistrer(r);
      await _noter('export', {'sauvegarde': p.basename(cible.path), 'motif': motif, 'taille': taille});
      return ResultatSauvegarde(cible, taille, photos.length, DateTime.now().difference(debut));
    } catch (e) {
      r.dernierMessage = 'Échec de la sauvegarde : $e';
      await _enregistrer(r);
      rethrow;
    } finally {
      _enCours = false;
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  /// Sauvegardes du dossier, la plus récente d'abord.
  Future<List<File>> sauvegardes({String? dossier}) async {
    final d = Directory(dossier ?? (await reglages()).dossier);
    if (!await d.exists()) return const [];
    final l = await d.list().where((f) => f is File && f.path.endsWith('.sssubak')).cast<File>().toList();
    l.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return l;
  }

  Future<void> _purger(Directory dossier, int conservation) async {
    final l = await sauvegardes(dossier: dossier.path);
    // Les sauvegardes de sécurité prises avant une restauration ne sont pas comptées.
    final ordinaires = l.where((f) => !p.basename(f.path).contains('avant_restauration')).toList();
    for (final f in ordinaires.skip(conservation)) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  // -------------------------------------------------------------- planification

  /// Sauvegarde automatique : vérification chaque minute ; une sauvegarde par
  /// jour à l'heure choisie, rattrapée si le poste était éteint à cette
  /// heure ; nouvel essai une heure après un échec.
  void demarrerPlanification() {
    _minuterie?.cancel();
    _minuterie = Timer.periodic(const Duration(minutes: 1), (_) => verifierEcheance());
    Timer(const Duration(seconds: 30), verifierEcheance);
  }

  void arreterPlanification() {
    _minuterie?.cancel();
    _minuterie = null;
  }

  /// Vrai si une sauvegarde automatique est due à l'instant [maintenant] (heure locale).
  static bool echeance(ReglagesSauvegarde r, DateTime maintenant) {
    if (!r.active || !r.phraseDefinie) return false;
    final l = maintenant.toLocal();
    final heureDuJour = DateTime(l.year, l.month, l.day, r.heure, r.minute);
    final derniere = r.derniereReussie?.toLocal();
    // Créneau à honorer : celui d'aujourd'hui s'il est passé, sinon celui
    // d'hier (rattrapage d'une sauvegarde manquée, poste éteint à l'heure prévue).
    final DateTime creneau;
    if (!l.isBefore(heureDuJour)) {
      creneau = heureDuJour;
    } else {
      if (derniere == null) return false;
      creneau = DateTime(l.year, l.month, l.day - 1, r.heure, r.minute);
    }
    if (derniere != null && !derniere.isBefore(creneau)) return false;
    final tentative = r.derniereTentative?.toLocal();
    if (tentative != null && l.difference(tentative) < const Duration(hours: 1) && tentative.isAfter(creneau)) {
      return false;
    }
    return true;
  }

  Future<void> verifierEcheance() async {
    if (_enCours) return;
    try {
      if (echeance(await reglages(), horloge.maintenant())) await sauvegarder(motif: 'automatique');
    } catch (_) {
      // Message enregistré dans les réglages, affiché sur la page Sauvegardes.
    }
  }

  // --------------------------------------------------------------- restauration

  /// Vérifie la phrase et l'intégrité complète d'une sauvegarde, sans rien
  /// modifier. Retourne son manifeste.
  Future<Map<String, Object?>> verifier(File archive, String phrase) async {
    final temp = Directory(p.join(dossierDonnees.path, 'tmp_verification_${DateTime.now().microsecondsSinceEpoch}'));
    try {
      return await _extraire(archive, phrase, temp);
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  Future<Map<String, Object?>> _extraire(File archive, String phrase, Directory temp) async {
    final entete = await lireEnteteArchive(archive);
    if (entete['format'] != 1) throw const ErreurSauvegarde('Format de sauvegarde non pris en charge.');
    final cle = await DerivationCle.depuisJson((entete['derivation']! as Map).cast<String, Object?>()).deriver(phrase);
    if (!await verifierControle(cle, entete['controle']! as String)) {
      throw const ErreurSauvegarde('Phrase de passe incorrecte pour cette sauvegarde.');
    }
    await temp.create(recursive: true);
    await extraireArchive(archive, cle, temp);
    final manifeste =
        (jsonDecode(await File(p.join(temp.path, 'manifeste.json')).readAsString()) as Map).cast<String, Object?>();
    final base = (manifeste['base']! as Map).cast<String, Object?>();
    final dump = File(p.join(temp.path, 'base.dump'));
    if (!await dump.exists() || await empreinteFichier(dump) != base['sha256']) {
      throw const ErreurSauvegarde('La base contenue dans la sauvegarde est endommagée.');
    }
    final photos = Directory(p.join(temp.path, 'photos'));
    final n = await photos.exists() ? await photos.list().length : 0;
    if (n != manifeste['photos']) throw const ErreurSauvegarde('Photographies manquantes dans la sauvegarde.');
    return manifeste;
  }

  /// Restaure [archive]. [arreterPoste] arrête le serveur de synchronisation
  /// et ferme les connexions à la base ; l'application doit ensuite être
  /// redémarrée. Retourne le chemin de la sauvegarde de sécurité prise avant.
  Future<String?> restaurer(File archive, String phrase, Droits a,
      {required Future<void> Function() arreterPoste, bool sauvegardeDeSecurite = true}) async {
    _exiger(a);
    final ts = DateTime.now().microsecondsSinceEpoch;
    final temp = Directory(p.join(dossierDonnees.path, 'tmp_restauration_$ts'));
    try {
      // 1. Contrôle complet avant toute modification.
      final manifeste = await _extraire(archive, phrase, temp);

      // 2. Sauvegarde de sécurité de l'état actuel.
      String? securite;
      if (sauvegardeDeSecurite && (await reglages()).phraseDefinie) {
        securite = (await sauvegarder(motif: 'avant_restauration')).fichier.path;
      }

      // 3. La sauvegarde est chargée dans une base neuve ; la base actuelle
      //    n'est remplacée (par renommage) qu'une fois ce chargement réussi.
      //    L'ancienne base est gardée sous le nom « sssu_saj_avant_… ».
      final base = postgres.base;
      final neuve = '${base}_restauration_$ts';
      final ancienne = '${base}_avant_$ts';
      final maintenance = await DepotPostgres.ouvrir(ConfigPostgres(
          hote: postgres.hote,
          port: postgres.port,
          base: 'postgres',
          utilisateur: postgres.utilisateur,
          motDePasse: postgres.motDePasse));
      try {
        await maintenance.executerScript('CREATE DATABASE "$neuve" TEMPLATE template0 ENCODING \'UTF8\'');
        try {
          await _executer(
              'pg_restore',
              [
                ..._connexion,
                '-d',
                neuve,
                '--no-owner',
                '--no-privileges',
                '--exit-on-error',
                '--single-transaction',
                p.join(temp.path, 'base.dump'),
              ],
              'Restauration de la base');
        } catch (_) {
          await maintenance.executerScript('DROP DATABASE IF EXISTS "$neuve"');
          rethrow;
        }
        await arreterPoste();
        // Connexions restantes du compte du poste sur la base actuelle.
        await maintenance.requete(
            'SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = @b AND pid <> pg_backend_pid()',
            {'b': base});
        await maintenance.executerScript('ALTER DATABASE "$base" RENAME TO "$ancienne"');
        await maintenance.executerScript('ALTER DATABASE "$neuve" RENAME TO "$base"');
        // Bases gardées lors des restaurations précédentes : seule la dernière est conservée.
        for (final l in await maintenance.requete(
            "SELECT datname FROM pg_database WHERE datname LIKE @motif AND datname <> @garder",
            {'motif': '${base}_avant_%', 'garder': ancienne})) {
          try {
            await maintenance.executerScript('DROP DATABASE "${l['datname']}"');
          } catch (_) {}
        }
      } finally {
        await maintenance.fermer();
      }

      // 4. Fichiers : photos, clé des photos, certificat (les téléphones
      //    gardent ainsi le même certificat épinglé).
      final anciennes = Directory(p.join(dossierDonnees.path, 'photos_avant_restauration_$ts'));
      if (await _photos.exists()) await _photos.rename(anciennes.path);
      final restaurees = Directory(p.join(temp.path, 'photos'));
      if (await restaurees.exists()) {
        await restaurees.rename(_photos.path);
      } else {
        await _photos.create(recursive: true);
      }
      for (final nom in ['cle_photos.bin', 'cle_privee.pem']) {
        final f = File(p.join(temp.path, nom));
        if (await f.exists()) await ecrireCle(File(p.join(dossierDonnees.path, nom)), await f.readAsBytes(), protection);
      }
      final cert = File(p.join(temp.path, 'certificat.pem'));
      if (await cert.exists()) await cert.copy(p.join(dossierDonnees.path, 'certificat.pem'));
      if (await anciennes.exists()) await anciennes.delete(recursive: true);

      // 5. Nouvelle génération et trace, sur une connexion neuve.
      final neuf = await DepotPostgres.ouvrir(postgres);
      try {
        try {
          await neuf.renouvelerGeneration();
        } catch (_) {
          // Sauvegarde antérieure à la phase 6 : la table est créée au
          // redémarrage (migration 020) avec une génération nouvelle.
        }
        await _noter('restauration', {'sauvegarde': p.basename(archive.path), 'cree_le': manifeste['cree_le']},
            depotCible: neuf, acteur: a);
      } finally {
        await neuf.fermer();
      }
      return securite;
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  Future<void> _noter(String action, Map<String, Object?> detail, {DepotPostgres? depotCible, Droits? acteur}) async {
    try {
      final m = horloge.maintenant();
      await (depotCible ?? depot).transaction((tx) => tx.ecrire(Enregistrement(
            table: 'journal_audit',
            id: nouvelId(),
            version: 1,
            versionBase: 1,
            createdAt: m,
            updatedAt: m,
            createdBy: acteur?.utilisateurId,
            updatedBy: acteur?.utilisateurId,
            donnees: {
              'utilisateur_id': acteur?.utilisateurId,
              'action': action,
              'table_cible': 'sauvegarde',
              'apres': detail,
              'survenu_le': formaterHorodatage(m),
            },
          )));
    } catch (_) {
      // La trace ne doit pas faire échouer une sauvegarde réussie.
    }
  }
}
