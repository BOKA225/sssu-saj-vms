/// Identité cryptographique du téléphone (paire de clés Ed25519).
/// La clé privée ne quitte jamais le téléphone : elle est conservée dans le
/// stockage sécurisé (Android Keystore) sous forme de graine de 32 octets.
library;

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../commun/commun.dart';
import 'protocole.dart';

class IdentiteAppareil {
  final String appareilId;
  final SimpleKeyPair _paire;

  IdentiteAppareil._(this.appareilId, this._paire);

  /// Nouvelle paire de clés (au moment de l'appairage).
  static Future<IdentiteAppareil> generer(String appareilId) async =>
      IdentiteAppareil._(appareilId, await Ed25519().newKeyPair());

  /// Restauration depuis la graine conservée dans le stockage sécurisé.
  static Future<IdentiteAppareil> depuisGraine(String appareilId, List<int> graine) async =>
      IdentiteAppareil._(appareilId, await Ed25519().newKeyPairFromSeed(graine));

  Future<List<int>> graine() => _paire.extractPrivateKeyBytes();

  Future<String> clePubliqueBase64() async => base64.encode((await _paire.extractPublicKey()).bytes);

  Future<DemandeJeton> demandeJeton(Horloge horloge, {Random? aleatoire}) async {
    final a = aleatoire ?? Random.secure();
    final horodatage = horloge.maintenant();
    final nonce = base64Url.encode(List<int>.generate(16, (_) => a.nextInt(256))).replaceAll('=', '');
    final signature = await Ed25519().sign(
      utf8.encode(DemandeJeton.messageASigner(appareilId, horodatage, nonce)),
      keyPair: _paire,
    );
    return DemandeJeton(
      appareilId: appareilId,
      horodatage: horodatage,
      nonce: nonce,
      signature: base64.encode(signature.bytes),
    );
  }
}
