/// Chiffrement des fichiers sensibles (photographies cliniques, listes
/// importées) avec AES-256-GCM : confidentialité et détection de toute
/// altération. Format : « SSV1 » + nonce (12 octets) + texte chiffré + étiquette (16 octets).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

const List<int> _entete = [0x53, 0x53, 0x56, 0x31]; // « SSV1 »

class ErreurDechiffrement implements Exception {
  final String message;
  const ErreurDechiffrement(this.message);
  @override
  String toString() => message;
}

class ChiffreurFichiers {
  final SecretKey _cle;
  final AesGcm _algo = AesGcm.with256bits();

  ChiffreurFichiers(List<int> cle32Octets) : _cle = SecretKey(cle32Octets) {
    if (cle32Octets.length != 32) throw ArgumentError('Clé AES-256 : 32 octets attendus.');
  }

  Future<Uint8List> chiffrer(List<int> clair) async {
    final boite = await _algo.encrypt(clair, secretKey: _cle, nonce: _algo.newNonce());
    return Uint8List.fromList([..._entete, ...boite.concatenation()]);
  }

  Future<Uint8List> dechiffrer(List<int> chiffre) async {
    if (chiffre.length < 4 + 12 + 16 || !_debutePar(chiffre, _entete)) {
      throw const ErreurDechiffrement('Fichier chiffré invalide.');
    }
    try {
      final boite = SecretBox.fromConcatenation(chiffre.sublist(4), nonceLength: 12, macLength: 16);
      return Uint8List.fromList(await _algo.decrypt(boite, secretKey: _cle));
    } on SecretBoxAuthenticationError {
      throw const ErreurDechiffrement('Fichier altéré ou clé incorrecte.');
    }
  }

  static bool _debutePar(List<int> a, List<int> b) {
    for (var i = 0; i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Empreinte SHA-256 en hexadécimal.
String sha256Hex(List<int> octets) =>
    const DartSha256().hashSync(octets).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Empreinte d'un texte (UTF-8).
String sha256HexTexte(String s) => sha256Hex(utf8.encode(s));
