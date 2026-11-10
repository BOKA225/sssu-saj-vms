import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sssu_core/sssu_core.dart';

/// Fichiers sensibles (photographies cliniques, listes importées), chiffrés
/// en AES-256-GCM dans l'espace privé de l'application : ils n'apparaissent
/// jamais dans la galerie ni dans les dossiers partagés du téléphone.
class StockageChiffre {
  final Directory racine;
  final ChiffreurFichiers chiffreur;

  StockageChiffre(this.racine, this.chiffreur);

  /// Enregistre [clair] et retourne le chemin relatif (colonne `chemin_chiffre`).
  Future<String> ecrire(String sousDossier, String id, List<int> clair) async {
    final relatif = p.join(sousDossier, '$id.enc');
    final f = File(p.join(racine.path, relatif));
    await f.parent.create(recursive: true);
    // Écriture dans un fichier temporaire puis renommage : jamais de fichier à moitié écrit.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(await chiffreur.chiffrer(clair), flush: true);
    await tmp.rename(f.path);
    return relatif;
  }

  Future<List<int>> lire(String relatif) async =>
      chiffreur.dechiffrer(await File(p.join(racine.path, relatif)).readAsBytes());

  Future<void> supprimer(String relatif) async {
    final f = File(p.join(racine.path, relatif));
    if (await f.exists()) await f.delete();
  }

  Future<bool> existe(String relatif) => File(p.join(racine.path, relatif)).exists();
}
