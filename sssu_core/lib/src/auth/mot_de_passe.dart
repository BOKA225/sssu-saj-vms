/// Hachage des mots de passe et codes PIN avec Argon2id.
///
/// Format de stockage (PHC) : `$argon2id$v=19$m=19456,t=2,p=1$<sel>$<empreinte>`
/// (sel et empreinte en base64 sans remplissage). Les paramètres sont lus dans
/// la chaîne stockée : ils peuvent être renforcés plus tard sans invalider les
/// comptes existants.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class ParametresArgon2 {
  /// Mémoire en kibioctets.
  final int memoireKio;
  final int iterations;
  final int parallelisme;

  const ParametresArgon2({required this.memoireKio, required this.iterations, required this.parallelisme});

  /// Recommandation OWASP minimale pour Argon2id (19 Mio, 2 passes, 1 fil).
  static const production = ParametresArgon2(memoireKio: 19456, iterations: 2, parallelisme: 1);

  /// Paramètres allégés, réservés aux tests automatiques.
  static const tests = ParametresArgon2(memoireKio: 1024, iterations: 1, parallelisme: 1);
}

class HacheurMotDePasse {
  final ParametresArgon2 parametres;
  final Random _aleatoire;

  HacheurMotDePasse({this.parametres = ParametresArgon2.production, Random? aleatoire})
      : _aleatoire = aleatoire ?? Random.secure();

  Future<String> hacher(String secret) async {
    final sel = Uint8List.fromList(List<int>.generate(16, (_) => _aleatoire.nextInt(256)));
    final empreinte = await _deriver(secret, sel, parametres);
    final p = parametres;
    return '\$argon2id\$v=19\$m=${p.memoireKio},t=${p.iterations},p=${p.parallelisme}'
        '\$${_b64(sel)}\$${_b64(empreinte)}';
  }

  Future<bool> verifier(String secret, String? stocke) async {
    if (stocke == null) return false;
    final parties = stocke.split('\$');
    // ['', 'argon2id', 'v=19', 'm=…,t=…,p=…', sel, empreinte]
    if (parties.length != 6 || parties[1] != 'argon2id' || parties[2] != 'v=19') return false;
    final params = <String, int>{};
    for (final kv in parties[3].split(',')) {
      final x = kv.split('=');
      if (x.length != 2) return false;
      final v = int.tryParse(x[1]);
      if (v == null) return false;
      params[x[0]] = v;
    }
    final m = params['m'], t = params['t'], p = params['p'];
    if (m == null || t == null || p == null) return false;
    final List<int> sel;
    final List<int> attendu;
    try {
      sel = _deb64(parties[4]);
      attendu = _deb64(parties[5]);
    } on FormatException {
      return false;
    }
    final calcule = await _deriver(
        secret, sel, ParametresArgon2(memoireKio: m, iterations: t, parallelisme: p),
        longueur: attendu.length);
    return _egalTempsConstant(calcule, attendu);
  }

  static Future<List<int>> _deriver(String secret, List<int> sel, ParametresArgon2 p, {int longueur = 32}) async {
    final algo = Argon2id(
      parallelism: p.parallelisme,
      memory: p.memoireKio,
      iterations: p.iterations,
      hashLength: longueur,
    );
    final cle = await algo.deriveKeyFromPassword(password: secret, nonce: sel);
    return cle.extractBytes();
  }

  static String _b64(List<int> octets) => base64.encode(octets).replaceAll('=', '');

  static List<int> _deb64(String s) => base64.decode(base64.normalize(s));

  static bool _egalTempsConstant(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Règle de mot de passe : au moins 8 caractères, dont une lettre et un chiffre.
/// Retourne le message d'erreur, ou `null` si le mot de passe est accepté.
String? controlerMotDePasse(String mdp) {
  if (mdp.length < 8) return 'Le mot de passe doit contenir au moins 8 caractères.';
  if (!RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(mdp)) return 'Le mot de passe doit contenir au moins une lettre.';
  if (!RegExp(r'\d').hasMatch(mdp)) return 'Le mot de passe doit contenir au moins un chiffre.';
  return null;
}

/// Règle du code PIN : 6 chiffres, ni tous identiques, ni suite simple.
String? controlerPin(String pin) {
  if (!RegExp(r'^\d{6}$').hasMatch(pin)) return 'Le code PIN doit comporter exactement 6 chiffres.';
  if (RegExp(r'^(\d)\1{5}$').hasMatch(pin)) return 'Le code PIN ne doit pas répéter le même chiffre.';
  const suites = '0123456789';
  const inverses = '9876543210';
  if (suites.contains(pin) || inverses.contains(pin)) return 'Le code PIN ne doit pas être une suite.';
  return null;
}
