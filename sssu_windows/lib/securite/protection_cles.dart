/// Protection des clés du poste central sur le disque (clé des photos, clé
/// privée du certificat, clé des sauvegardes) par Windows DPAPI, portée
/// « ordinateur » : un fichier de clé copié sur une autre machine est
/// inutilisable. Hors Windows (tests automatiques), les clés restent en clair.
///
/// Format d'un fichier protégé : `DPAPI1` suivi du bloc DPAPI. Un ancien
/// fichier en clair (phases 1 à 5) est lu puis réécrit protégé.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

abstract class ProtectionCles {
  bool get active;
  List<int> proteger(List<int> clair);
  List<int> deproteger(List<int> protege);

  static ProtectionCles systeme() => Platform.isWindows ? const ProtectionDpapi() : const SansProtection();
}

class SansProtection implements ProtectionCles {
  const SansProtection();
  @override
  bool get active => false;
  @override
  List<int> proteger(List<int> clair) => clair;
  @override
  List<int> deproteger(List<int> protege) => protege;
}

class ProtectionDpapi implements ProtectionCles {
  const ProtectionDpapi();

  // Indicateurs de CryptProtectData (wincrypt.h).
  static const _interfaceInterdite = 0x1; // CRYPTPROTECT_UI_FORBIDDEN
  static const _porteeOrdinateur = 0x4; // CRYPTPROTECT_LOCAL_MACHINE

  /// Entropie complémentaire propre à l'application.
  static final _entropie = utf8.encode('SSSU-SAJ-VMS/cles/v1');

  @override
  bool get active => true;

  @override
  List<int> proteger(List<int> clair) => _appel(clair, chiffrer: true);

  @override
  List<int> deproteger(List<int> protege) => _appel(protege, chiffrer: false);

  static List<int> _appel(List<int> entree, {required bool chiffrer}) => using((arena) {
        Pointer<CRYPT_INTEGER_BLOB> bloc(List<int> octets) {
          final b = arena<CRYPT_INTEGER_BLOB>();
          final d = arena<Uint8>(octets.isEmpty ? 1 : octets.length);
          d.asTypedList(octets.length).setAll(0, octets);
          b.ref
            ..cbData = octets.length
            ..pbData = d;
          return b;
        }

        final pEntree = bloc(entree);
        final pEntropie = bloc(_entropie);
        final pSortie = arena<CRYPT_INTEGER_BLOB>();
        final ok = chiffrer
            ? CryptProtectData(pEntree, nullptr, pEntropie, nullptr, nullptr,
                _interfaceInterdite | _porteeOrdinateur, pSortie)
            : CryptUnprotectData(pEntree, nullptr, pEntropie, nullptr, nullptr, _interfaceInterdite, pSortie);
        if (ok == 0) {
          throw StateError('Protection Windows (DPAPI) : échec ${chiffrer ? 'du chiffrement' : 'du déchiffrement'} '
              '(code ${GetLastError()}). Le fichier de clé vient-il d\'un autre ordinateur ?');
        }
        final r = Uint8List.fromList(pSortie.ref.pbData.asTypedList(pSortie.ref.cbData));
        LocalFree(pSortie.ref.pbData);
        return r;
      });
}

const _magie = [0x44, 0x50, 0x41, 0x50, 0x49, 0x31]; // « DPAPI1 »

bool _protege(List<int> o) {
  if (o.length < _magie.length) return false;
  for (var i = 0; i < _magie.length; i++) {
    if (o[i] != _magie[i]) return false;
  }
  return true;
}

/// Écrit [clair] dans [fichier], protégé si la protection est active.
Future<void> ecrireCle(File fichier, List<int> clair, ProtectionCles protection) async {
  final contenu = protection.active ? [..._magie, ...protection.proteger(clair)] : clair;
  await fichier.parent.create(recursive: true);
  await fichier.writeAsBytes(contenu, flush: true);
}

/// Lit la clé de [fichier] ; un fichier ancien en clair est réécrit protégé.
Future<List<int>> lireCle(File fichier, ProtectionCles protection) async {
  final o = await fichier.readAsBytes();
  if (_protege(o)) return protection.deproteger(o.sublist(_magie.length));
  if (protection.active) await ecrireCle(fichier, o, protection);
  return o;
}
