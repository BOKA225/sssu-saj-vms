import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secrets du téléphone, conservés dans le stockage sécurisé Android
/// (clés protégées par Android Keystore) : clé de la base SQLCipher,
/// graine de la clé d'appareil, adresse et certificat du poste central.
class Coffre {
  final FlutterSecureStorage _stockage;

  Coffre([FlutterSecureStorage? stockage])
      : _stockage = stockage ??
            const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  static const _cleBase = 'cle_base';
  static const _graine = 'graine_appareil';
  static const _appareilId = 'appareil_id';
  static const _url = 'url_serveur';
  static const _empreinte = 'empreinte_certificat';
  static const _dernierUtilisateur = 'dernier_utilisateur';
  static const _cleFichiers = 'cle_fichiers';
  static const _urlInternet = 'url_internet';
  static const _enAttente = 'en_attente_validation';

  /// Clé AES-256 de la base locale, créée au premier lancement.
  Future<String> cleBase() async {
    final existante = await _stockage.read(key: _cleBase);
    if (existante != null) return existante;
    final r = Random.secure();
    final cle = List<int>.generate(32, (_) => r.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _stockage.write(key: _cleBase, value: cle);
    return cle;
  }

  /// Clé AES-256 des fichiers sensibles (photographies, listes importées).
  Future<List<int>> cleFichiers() async {
    final existante = await _stockage.read(key: _cleFichiers);
    if (existante != null) return base64.decode(existante);
    final r = Random.secure();
    final cle = List<int>.generate(32, (_) => r.nextInt(256));
    await _stockage.write(key: _cleFichiers, value: base64.encode(cle));
    return cle;
  }

  Future<void> enregistrerAppairage({
    required String appareilId,
    required List<int> graine,
    required String urlServeur,
    required String? empreinteCertificat,
    String? urlInternet,
  }) async {
    await _stockage.write(key: _graine, value: base64.encode(graine));
    await _stockage.write(key: _url, value: urlServeur);
    await _stockage.write(key: _urlInternet, value: urlInternet);
    await _stockage.write(key: _empreinte, value: empreinteCertificat);
    await _stockage.write(key: _appareilId, value: appareilId);
  }

  Future<String?> appareilId() => _stockage.read(key: _appareilId);

  /// Téléphone enregistré sans QR code, pas encore validé sur le poste central.
  Future<bool> enAttenteValidation() async => await _stockage.read(key: _enAttente) == '1';

  Future<void> definirEnAttenteValidation(bool v) =>
      v ? _stockage.write(key: _enAttente, value: '1') : _stockage.delete(key: _enAttente);

  /// Abandon d'un enregistrement refusé : identité et adresses oubliées, les
  /// clés de la base et des fichiers sont gardées.
  Future<void> annulerAppairage() async {
    for (final k in [_appareilId, _graine, _url, _urlInternet, _empreinte, _enAttente, _dernierUtilisateur]) {
      await _stockage.delete(key: k);
    }
  }

  /// Effacement à distance : toutes les clés et l'identité du téléphone.
  Future<void> effacerTout() => _stockage.deleteAll();

  Future<List<int>?> graine() async {
    final g = await _stockage.read(key: _graine);
    return g == null ? null : base64.decode(g);
  }

  /// Dernière adresse à laquelle le poste central a répondu.
  Future<String?> urlServeur() => _stockage.read(key: _url);

  Future<void> definirUrlServeur(String url) => _stockage.write(key: _url, value: url);

  /// Adresse Internet du poste central (facultative, fournie par le QR code).
  Future<String?> urlInternet() => _stockage.read(key: _urlInternet);

  Future<String?> empreinteCertificat() => _stockage.read(key: _empreinte);

  Future<String?> dernierUtilisateur() => _stockage.read(key: _dernierUtilisateur);

  Future<void> definirDernierUtilisateur(String? id) => _stockage.write(key: _dernierUtilisateur, value: id);
}
