/// Photographies cliniques : consentement, prise de vue ou import depuis la
/// galerie, compression, suppression des métadonnées (position GPS…),
/// chiffrement et rattachement au dossier.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:sssu_core/sssu_core.dart';

import '../data/depot_local_drift.dart';
import '../fichiers/stockage_chiffre.dart';

class PhotoPreparee {
  final Uint8List jpeg;
  final int largeur;
  final int hauteur;
  const PhotoPreparee(this.jpeg, this.largeur, this.hauteur);
}

/// Redresse l'image, la réduit à 1600 px au plus, retire toutes les
/// métadonnées EXIF et la réencode en JPEG (qualité 80). Exécuté hors du fil
/// d'affichage (`compute`).
PhotoPreparee preparerPhoto(Uint8List octets) {
  final source = img.decodeImage(octets);
  if (source == null) throw const FormatException('Image illisible.');
  var image = img.bakeOrientation(source);
  const cote = 1600;
  if (image.width > cote || image.height > cote) {
    image = image.width >= image.height ? img.copyResize(image, width: cote) : img.copyResize(image, height: cote);
  }
  image.exif = img.ExifData();
  return PhotoPreparee(img.encodeJpg(image, quality: 80), image.width, image.height);
}

class ServicePhoto {
  final DepotLocalDrift depot;
  final StockageChiffre fichiers;
  final ImagePicker _picker;

  ServicePhoto(this.depot, this.fichiers, {ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  /// Consentement valable pour la visite (obtenu), s'il existe.
  Future<Enregistrement?> consentement(String visiteId) async {
    final c = await depot.chercher('consentement', {'visite_id': visiteId, 'obtenu': true});
    return c.isEmpty ? null : c.last;
  }

  Future<Enregistrement> enregistrerConsentement({
    required String visiteId,
    required String eleveId,
    required String? etablissementId,
    required bool obtenu,
    required String forme,
    required String nomRepondant,
    String? lienParente,
    required String utilisateurId,
    required bool aTransmettre,
  }) =>
      depot.creer(
        'consentement',
        {
          'eleve_id': eleveId,
          'visite_id': visiteId,
          'type': 'photo',
          'obtenu': obtenu,
          'forme': obtenu ? forme : null,
          'nom_repondant': obtenu ? nomRepondant.trim() : (nomRepondant.trim().isEmpty ? null : nomRepondant.trim()),
          'lien_parente': lienParente,
          'date_consentement': formaterDate(DateTime.now()),
        },
        utilisateurId: utilisateurId,
        etablissementId: etablissementId,
        aTransmettre: aTransmettre,
      );

  Future<List<Enregistrement>> photos(String visiteId) => depot.chercher('photo', {'visite_id': visiteId});

  /// Prend une photo (appareil photo) ou en importe une (galerie), puis
  /// l'enregistre chiffrée. Retourne `null` si l'utilisateur annule.
  Future<Enregistrement?> ajouter({
    required ImageSource source,
    required String visiteId,
    required String eleveId,
    required String? etablissementId,
    required String consentementId,
    required String auteurId,
    required bool aTransmettre,
    String? visitePathologieId,
    String? commentaire,
  }) async {
    final x = await _picker.pickImage(source: source, requestFullMetadata: false, imageQuality: 95);
    if (x == null) return null;
    final brut = await x.readAsBytes();
    final preparee = await compute(preparerPhoto, brut);
    // L'original de l'appareil photo est un fichier temporaire de l'application :
    // il est effacé. Celui de la galerie appartient à l'utilisateur et n'est pas touché.
    if (source == ImageSource.camera) {
      try {
        await File(x.path).delete();
      } catch (_) {}
    }
    final id = nouvelId();
    final chemin = await fichiers.ecrire('photos', id, preparee.jpeg);
    try {
      return await depot.creer(
        'photo',
        {
          'visite_id': visiteId,
          'eleve_id': eleveId,
          'visite_pathologie_id': visitePathologieId,
          'auteur_id': auteurId,
          'consentement_id': consentementId,
          'chemin_chiffre': chemin,
          'empreinte_sha256': sha256Hex(preparee.jpeg),
          'taille_octets': preparee.jpeg.length,
          'largeur': preparee.largeur,
          'hauteur': preparee.hauteur,
          'commentaire': commentaire,
          'pris_le': formaterHorodatage(DateTime.now()),
          'statut_transfert': 'en_attente',
        },
        utilisateurId: auteurId,
        etablissementId: etablissementId,
        aTransmettre: aTransmettre,
        id: id,
      );
    } catch (_) {
      await fichiers.supprimer(chemin);
      rethrow;
    }
  }

  Future<Uint8List> lire(Enregistrement photo) async =>
      Uint8List.fromList(await fichiers.lire(photo.donnees['chemin_chiffre']! as String));

  Future<void> modifier(Enregistrement photo,
          {String? commentaire, String? visitePathologieId, required String utilisateurId, required bool aTransmettre}) =>
      depot.modifier(
        'photo',
        photo.id,
        {'commentaire': commentaire, 'visite_pathologie_id': visitePathologieId},
        utilisateurId: utilisateurId,
        aTransmettre: aTransmettre,
      );

  /// Supprime une photo. Si elle n'a jamais été transmise, le fichier est
  /// effacé ; sinon la suppression est transmise et le fichier est effacé
  /// après confirmation du poste central (phase 4).
  Future<void> supprimer(Enregistrement photo, {required String utilisateurId}) async {
    final jamaisTransmise = photo.versionBase == 0;
    await depot.supprimer('photo', photo.id, utilisateurId: utilisateurId);
    if (jamaisTransmise) await fichiers.supprimer(photo.donnees['chemin_chiffre']! as String);
  }
}
