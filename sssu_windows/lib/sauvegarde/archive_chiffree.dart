/// Archive de sauvegarde chiffrée (`.sssubak`), écrite et lue en flux : sa
/// taille n'est pas limitée par la mémoire (base et photographies).
///
/// Format :
/// - en-tête en clair : `SSSUBAK1`, longueur (4 octets), JSON (date, poste,
///   paramètres de dérivation de la clé, contrôle de la phrase de passe) ;
/// - corps : blocs AES-256-GCM d'au plus 1 Mio de clair. Chaque bloc :
///   indicateur « dernier » (1 octet), longueur du chiffré (4 octets),
///   nonce (12), chiffré, code d'authentification (16). Le numéro du bloc et
///   l'indicateur sont authentifiés : un bloc modifié, déplacé, supprimé ou
///   une archive tronquée sont détectés ;
/// - contenu clair : suite d'entrées (longueur du nom sur 2 octets, nom,
///   taille sur 8 octets, données), terminée par une entrée de nom vide.
///
/// La clé est dérivée de la phrase de passe de sauvegarde (Argon2id) : une
/// archive se restaure sur n'importe quel poste avec cette phrase.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

const _magie = 'SSSUBAK1';
const tailleBloc = 1 << 20;
const _controle = 'SSSU-SAJ VMS / contrôle de la phrase de passe';

class ArchiveInvalide implements Exception {
  final String message;
  const ArchiveInvalide(this.message);
  @override
  String toString() => message;
}

/// Paramètres Argon2id de la clé de sauvegarde.
class DerivationCle {
  final List<int> sel;
  final int memoireKio;
  final int iterations;
  final int parallelisme;
  const DerivationCle({required this.sel, this.memoireKio = 65536, this.iterations = 3, this.parallelisme = 1});

  factory DerivationCle.nouvelle() {
    final r = Random.secure();
    return DerivationCle(sel: List<int>.generate(16, (_) => r.nextInt(256)));
  }

  Map<String, Object?> versJson() => {
        'algo': 'argon2id',
        'sel': base64.encode(sel),
        'memoire_kio': memoireKio,
        'iterations': iterations,
        'parallelisme': parallelisme,
      };

  factory DerivationCle.depuisJson(Map<String, Object?> j) {
    if (j['algo'] != 'argon2id') throw const ArchiveInvalide('Dérivation de clé inconnue.');
    return DerivationCle(
      sel: base64.decode(j['sel']! as String),
      memoireKio: (j['memoire_kio']! as num).toInt(),
      iterations: (j['iterations']! as num).toInt(),
      parallelisme: (j['parallelisme']! as num).toInt(),
    );
  }

  Future<List<int>> deriver(String phrase) async {
    final k = await Argon2id(memory: memoireKio, iterations: iterations, parallelism: parallelisme, hashLength: 32)
        .deriveKey(secretKey: SecretKey(utf8.encode(phrase)), nonce: sel);
    return k.extractBytes();
  }
}

final _aes = AesGcm.with256bits();

List<int> _aad(int index, bool dernier) {
  final b = ByteData(9)
    ..setUint64(0, index)
    ..setUint8(8, dernier ? 1 : 0);
  return b.buffer.asUint8List();
}

/// Valeur de contrôle : permet de vérifier la phrase de passe sans tout déchiffrer.
Future<String> controlePhrase(List<int> cle) async {
  final nonce = _aes.newNonce();
  final b = await _aes.encrypt(utf8.encode(_controle), secretKey: SecretKey(cle), nonce: nonce);
  return base64.encode(b.concatenation());
}

Future<bool> verifierControle(List<int> cle, String controle) async {
  try {
    final box = SecretBox.fromConcatenation(base64.decode(controle), nonceLength: 12, macLength: 16);
    return utf8.decode(await _aes.decrypt(box, secretKey: SecretKey(cle))) == _controle;
  } on SecretBoxAuthenticationError {
    return false;
  }
}

class EcrivainArchive {
  final RandomAccessFile _sortie;
  final SecretKey _cle;
  final BytesBuilder _tampon = BytesBuilder(copy: false);
  int _index = 0;
  bool _ferme = false;

  EcrivainArchive._(this._sortie, this._cle);

  static Future<EcrivainArchive> creer(File fichier, List<int> cle, Map<String, Object?> entete) async {
    final raf = await fichier.open(mode: FileMode.write);
    final j = utf8.encode(jsonEncode(entete));
    await raf.writeFrom(ascii.encode(_magie));
    await raf.writeFrom((ByteData(4)..setUint32(0, j.length)).buffer.asUint8List());
    await raf.writeFrom(j);
    return EcrivainArchive._(raf, SecretKey(cle));
  }

  Future<void> _ecrireBloc(List<int> clair, {required bool dernier}) async {
    final box = await _aes.encrypt(clair, secretKey: _cle, nonce: _aes.newNonce(), aad: _aad(_index, dernier));
    final entete = ByteData(5)
      ..setUint8(0, dernier ? 1 : 0)
      ..setUint32(1, box.cipherText.length);
    await _sortie.writeFrom(entete.buffer.asUint8List());
    await _sortie.writeFrom(box.nonce);
    await _sortie.writeFrom(box.cipherText);
    await _sortie.writeFrom(box.mac.bytes);
    _index++;
  }

  Future<void> _ajouter(List<int> octets) async {
    var debut = 0;
    while (debut < octets.length) {
      final place = tailleBloc - _tampon.length;
      final n = min(place, octets.length - debut);
      _tampon.add(octets is Uint8List ? Uint8List.sublistView(octets, debut, debut + n) : octets.sublist(debut, debut + n));
      debut += n;
      if (_tampon.length >= tailleBloc) await _ecrireBloc(_tampon.takeBytes(), dernier: false);
    }
  }

  Future<void> _enteteEntree(String nom, int taille) async {
    final n = utf8.encode(nom);
    if (n.length > 0xFFFF) throw ArgumentError('Nom trop long : $nom');
    await _ajouter((ByteData(2)..setUint16(0, n.length)).buffer.asUint8List());
    await _ajouter(n);
    await _ajouter((ByteData(8)..setUint64(0, taille)).buffer.asUint8List());
  }

  Future<void> ajouterOctets(String nom, List<int> octets) async {
    await _enteteEntree(nom, octets.length);
    await _ajouter(octets);
  }

  Future<void> ajouterFichier(String nom, File source) async {
    final taille = await source.length();
    await _enteteEntree(nom, taille);
    var lus = 0;
    await for (final morceau in source.openRead()) {
      lus += morceau.length;
      await _ajouter(morceau);
    }
    if (lus != taille) throw StateError('Fichier modifié pendant la sauvegarde : $nom');
  }

  Future<void> fermer() async {
    if (_ferme) return;
    await _enteteEntree('', 0); // fin des entrées
    await _ecrireBloc(_tampon.takeBytes(), dernier: true);
    await _sortie.flush();
    await _sortie.close();
    _ferme = true;
  }

  /// Abandon (erreur) : le fichier incomplet est fermé ; à supprimer par l'appelant.
  Future<void> abandonner() async {
    if (_ferme) return;
    _ferme = true;
    await _sortie.close();
  }
}

/// En-tête d'une archive (sans la déchiffrer).
Future<Map<String, Object?>> lireEnteteArchive(File fichier) async {
  final raf = await fichier.open();
  try {
    final m = await raf.read(_magie.length);
    if (ascii.decode(m, allowInvalid: true) != _magie) {
      throw const ArchiveInvalide('Ce fichier n\'est pas une sauvegarde SSSU-SAJ VMS.');
    }
    final l = ByteData.sublistView(await raf.read(4)).getUint32(0);
    if (l > 1 << 20) throw const ArchiveInvalide('En-tête de sauvegarde invalide.');
    return (jsonDecode(utf8.decode(await raf.read(l))) as Map).cast<String, Object?>();
  } finally {
    await raf.close();
  }
}

String _nomSur(String nom) {
  final n = nom.replaceAll('\\', '/');
  if (n.isEmpty ||
      n.startsWith('/') ||
      n.split('/').any((s) => s == '..' || s.isEmpty) ||
      !RegExp(r'^[A-Za-z0-9._/-]+$').hasMatch(n)) {
    throw ArchiveInvalide('Nom de fichier refusé dans l\'archive : $nom');
  }
  return n;
}

/// Déchiffre l'archive et écrit ses entrées dans [destination]. Retourne les
/// noms extraits. Lève [ArchiveInvalide] si la clé est fausse ou si
/// l'archive a été modifiée ou tronquée.
Future<List<String>> extraireArchive(File fichier, List<int> cle, Directory destination) async {
  final raf = await fichier.open();
  final noms = <String>[];
  final secret = SecretKey(cle);
  try {
    await raf.setPosition(_magie.length);
    final l = ByteData.sublistView(await raf.read(4)).getUint32(0);
    await raf.setPosition(_magie.length + 4 + l);

    // Analyse en flux du contenu clair.
    final tampon = BytesBuilder(copy: false);
    IOSink? courant;
    var restant = 0;
    var fini = false;

    Future<void> consommer(Uint8List donnees) async {
      var o = 0;
      while (o < donnees.length && !fini) {
        if (courant != null) {
          final n = min(restant, donnees.length - o);
          courant!.add(Uint8List.sublistView(donnees, o, o + n));
          // Écriture au fil de l'eau : la mémoire utilisée reste d'un bloc.
          await courant!.flush();
          o += n;
          restant -= n;
          if (restant == 0) {
            await courant!.close();
            courant = null;
          }
          continue;
        }
        // En-tête d'entrée : accumuler jusqu'à disposer de 2 + nom + 8 octets.
        tampon.add(Uint8List.sublistView(donnees, o, o + 1));
        o++;
        final t = tampon.toBytes();
        if (t.length < 2) continue;
        final ln = ByteData.sublistView(t).getUint16(0);
        if (t.length < 2 + ln + 8) continue;
        tampon.clear();
        final nom = utf8.decode(t.sublist(2, 2 + ln));
        final taille = ByteData.sublistView(t, 2 + ln).getUint64(0);
        if (nom.isEmpty) {
          fini = true;
          break;
        }
        final f = File(p.join(destination.path, _nomSur(nom)));
        await f.parent.create(recursive: true);
        noms.add(nom);
        if (taille == 0) {
          await f.writeAsBytes(const []);
        } else {
          courant = f.openWrite();
          restant = taille;
        }
      }
    }

    var index = 0;
    var dernier = false;
    while (!dernier) {
      final e = await raf.read(5);
      if (e.length < 5) throw const ArchiveInvalide('Sauvegarde tronquée (fin inattendue).');
      final ed = ByteData.sublistView(e);
      dernier = ed.getUint8(0) == 1;
      final n = ed.getUint32(1);
      if (n > tailleBloc + 64) throw const ArchiveInvalide('Bloc de sauvegarde invalide.');
      final nonce = await raf.read(12);
      final chiffre = await raf.read(n);
      final mac = await raf.read(16);
      if (nonce.length < 12 || chiffre.length < n || mac.length < 16) {
        throw const ArchiveInvalide('Sauvegarde tronquée (fin inattendue).');
      }
      final List<int> clair;
      try {
        clair = await _aes.decrypt(SecretBox(chiffre, nonce: nonce, mac: Mac(mac)),
            secretKey: secret, aad: _aad(index, dernier));
      } on SecretBoxAuthenticationError {
        throw ArchiveInvalide(index == 0
            ? 'Phrase de passe incorrecte, ou sauvegarde endommagée.'
            : 'Sauvegarde endommagée ou modifiée (bloc ${index + 1}).');
      }
      await consommer(clair is Uint8List ? clair : Uint8List.fromList(clair));
      index++;
    }
    if (courant != null || !fini) throw const ArchiveInvalide('Sauvegarde incomplète.');
    if (await raf.position() != await raf.length()) {
      throw const ArchiveInvalide('Données inattendues après la fin de la sauvegarde.');
    }
    return noms;
  } finally {
    await raf.close();
  }
}
