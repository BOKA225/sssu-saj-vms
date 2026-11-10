import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sssu_core/sssu_core.dart';

import '../securite/protection_cles.dart';

/// Photographies cliniques reçues sur le poste central, chiffrées en
/// AES-256-GCM dans le dossier de l'application (un fichier par photo).
///
/// La clé est conservée dans le dossier de l'application, protégée par
/// Windows DPAPI (voir `protection_cles.dart`). Les fichiers reçus des téléphones sont
/// déposés par le transfert par morceaux (`ServiceFichiers`, méthode [ecrire]).
class StockagePhotosPoste implements StockageFichiersServeur {
  final Directory dossier;
  final ChiffreurFichiers _chiffreur;

  StockagePhotosPoste._(this.dossier, this._chiffreur);

  static Future<StockagePhotosPoste> ouvrir(Directory racine, {ProtectionCles? protection}) async {
    final prot = protection ?? ProtectionCles.systeme();
    final dossier = Directory(p.join(racine.path, 'photos'));
    await dossier.create(recursive: true);
    final fCle = File(p.join(racine.path, 'cle_photos.bin'));
    if (!await fCle.exists()) {
      final r = Random.secure();
      await ecrireCle(fCle, List<int>.generate(32, (_) => r.nextInt(256)), prot);
    }
    return StockagePhotosPoste._(dossier, ChiffreurFichiers(await lireCle(fCle, prot)));
  }

  File _fichier(String photoId) {
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(photoId)) throw ArgumentError('Identifiant de photo invalide.');
    return File(p.join(dossier.path, '$photoId.enc'));
  }

  @override
  Future<bool> disponible(String photoId) => _fichier(photoId).exists();

  Future<Uint8List> lire(String photoId) async => _chiffreur.dechiffrer(await _fichier(photoId).readAsBytes());

  /// Enregistre une photo reçue (JPEG en clair), après contrôle de son empreinte.
  @override
  Future<void> ecrire(String photoId, List<int> jpeg, {required String empreinteAttendue}) async {
    if (sha256Hex(jpeg) != empreinteAttendue) throw StateError('Empreinte de la photo incorrecte.');
    final f = _fichier(photoId);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(await _chiffreur.chiffrer(jpeg), flush: true);
    await tmp.rename(f.path);
  }

  /// Copie déchiffrée vers [destination] (téléchargement autorisé).
  Future<void> exporter(String photoId, String destination) async =>
      File(destination).writeAsBytes(await lire(photoId), flush: true);
}
