/// Enregistrement des inspections sanitaires dans la base du téléphone :
/// inspection, réponses par critère et photos des insuffisances constatées.
/// Même cycle qu'une visite : l'ébauche reste sur le téléphone ;
/// « Enregistrer et transmettre » la met en attente de synchronisation, avec
/// ses réponses et ses photos.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show variable;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sssu_core/sssu_core.dart';

import '../data/base_locale.dart';
import '../data/depot_local_drift.dart';
import '../fichiers/stockage_chiffre.dart';
import '../photo/service_photo.dart';

class DossierInspection {
  final FormulaireInspection formulaire;

  /// Critère → identifiant de la ligne `inspection_reponse`.
  final Map<String, String> idsReponses = {};
  EtatSync etat = EtatSync.local;

  DossierInspection(this.formulaire);

  String get etablissementId => formulaire.etablissementId;
}

class ResumeInspection {
  final String id;
  final DateTime date;
  final StatutInspection statut;
  final EtatSync etat;
  final double? taux;
  final NiveauConformite? niveau;
  final String? inspecteur;
  const ResumeInspection(this.id, this.date, this.statut, this.etat, this.taux, this.niveau, this.inspecteur);
}

class DepotInspection {
  final BaseLocale db;
  final DepotLocalDrift depot;
  final StockageChiffre fichiers;
  final ImagePicker _picker;
  DepotInspection(this.db, this.depot, this.fichiers, {ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  /// Grille actuelle : critères actifs reçus du poste central.
  Future<List<CritereGrille>> criteresActifs() async => [
        for (final c in await depot.chercher('critere_inspection', {'actif': true}))
          CritereGrille.depuisDonnees(c.id, c.donnees)
      ];

  Future<SeuilsConformite> seuils() async {
    final p = await depot.chercher('parametre', {});
    return SeuilsConformite.depuisParametres({for (final x in p) x.donnees['cle']! as String: x.donnees['valeur'] as String?});
  }

  Future<DossierInspection> nouvelle({
    required String etablissementId,
    required String anneeScolaireId,
    required String inspecteurId,
    required DateTime date,
  }) async {
    final criteres = await criteresActifs();
    if (criteres.isEmpty) {
      throw StateError('La grille d\'inspection n\'a pas encore été reçue : synchronisez avec le poste central.');
    }
    return DossierInspection(FormulaireInspection(
      etablissementId: etablissementId,
      anneeScolaireId: anneeScolaireId,
      inspecteurId: inspecteurId,
      dateInspection: date,
      criteres: criteres,
    ));
  }

  Future<DossierInspection> charger(String inspectionId) async {
    final i = await depot.lire('inspection', inspectionId);
    if (i == null || i.supprime) throw StateError('Inspection introuvable.');
    final f = FormulaireInspection(
      id: i.id,
      etablissementId: i.donnees['etablissement_id']! as String,
      anneeScolaireId: i.donnees['annee_scolaire_id']! as String,
      inspecteurId: i.donnees['inspecteur_id']! as String,
      dateInspection: lireDate(i.donnees['date_inspection']! as String),
      // Une inspection transmise garde la grille à laquelle elle a répondu.
      criteres: (i.donnees['statut'] ?? 'ebauche') == 'ebauche' ? await criteresActifs() : const [],
    )..chargerInspection(i.donnees);
    final d = DossierInspection(f)..etat = (await depot.etat('inspection', inspectionId))!;
    for (final r in await depot.chercher('inspection_reponse', {'inspection_id': inspectionId})) {
      final cid = r.donnees['critere_id']! as String;
      final c = await depot.lire('critere_inspection', cid);
      f.chargerReponse(r.donnees, critere: c == null ? null : CritereGrille.depuisDonnees(c.id, c.donnees));
      d.idsReponses[cid] = r.id;
    }
    return d;
  }

  /// Enregistre l'inspection et ses réponses. Tant qu'elle est une ébauche,
  /// rien n'est transmis.
  Future<void> enregistrer(DossierInspection d, {required String utilisateurId}) async {
    final f = d.formulaire;
    final aTransmettre = !f.modifiable;
    final donnees = f.donneesInspection(await seuils());
    await db.transaction(() async {
      if (f.id == null) {
        final e = await depot.creer('inspection', donnees,
            utilisateurId: utilisateurId, etablissementId: d.etablissementId, aTransmettre: aTransmettre);
        f.id = e.id;
      } else {
        await depot.modifier('inspection', f.id!, donnees,
            utilisateurId: utilisateurId, etablissementId: d.etablissementId, aTransmettre: aTransmettre);
      }
      for (final c in f.criteres) {
        final donneesReponse = f.donneesReponse(c.id);
        final id = d.idsReponses[c.id];
        if (donneesReponse == null) {
          if (id != null) {
            await _supprimerPhotos(id, utilisateurId);
            await depot.supprimer('inspection_reponse', id, utilisateurId: utilisateurId);
            d.idsReponses.remove(c.id);
          }
        } else if (id == null) {
          final e = await depot.creer('inspection_reponse', donneesReponse,
              utilisateurId: utilisateurId, etablissementId: d.etablissementId, aTransmettre: aTransmettre);
          d.idsReponses[c.id] = e.id;
        } else {
          await depot.modifier('inspection_reponse', id, donneesReponse,
              utilisateurId: utilisateurId, etablissementId: d.etablissementId, aTransmettre: aTransmettre);
        }
      }
    });
    d.etat = (await depot.etat('inspection', f.id!))!;
  }

  /// « Enregistrer et transmettre » : l'inspection n'est plus modifiable et
  /// part à la prochaine synchronisation avec ses réponses et ses photos.
  Future<void> transmettre(DossierInspection d, {required String utilisateurId}) async {
    final c = controlerInspection(d.formulaire);
    if (!c.transmissible) throw StateError(c.erreurs.join('\n'));
    d.formulaire.statut = StatutInspection.enregistre;
    await enregistrer(d, utilisateurId: utilisateurId);
    await db.transaction(() async {
      await depot.rendreTransmissible('inspection', d.formulaire.id!);
      for (final id in d.idsReponses.values) {
        await depot.rendreTransmissible('inspection_reponse', id);
        for (final p in await depot.chercher('inspection_photo', {'inspection_reponse_id': id})) {
          await depot.rendreTransmissible('inspection_photo', p.id);
        }
      }
    });
    d.etat = (await depot.etat('inspection', d.formulaire.id!))!;
  }

  /// Supprime une ébauche jamais transmise, ses réponses et ses photos.
  Future<void> supprimerEbauche(DossierInspection d, {required String utilisateurId}) async {
    final id = d.formulaire.id;
    if (id == null) return;
    if (!d.formulaire.modifiable) throw StateError('Une inspection transmise ne peut pas être supprimée.');
    await db.transaction(() async {
      for (final r in d.idsReponses.values) {
        await _supprimerPhotos(r, utilisateurId);
        await depot.supprimer('inspection_reponse', r, utilisateurId: utilisateurId);
      }
      await depot.supprimer('inspection', id, utilisateurId: utilisateurId);
    });
  }

  Future<void> _supprimerPhotos(String reponseId, String utilisateurId) async {
    for (final p in await depot.chercher('inspection_photo', {'inspection_reponse_id': reponseId})) {
      await depot.supprimer('inspection_photo', p.id, utilisateurId: utilisateurId);
      await fichiers.supprimer(p.donnees['chemin_chiffre']! as String);
    }
  }

  /// Inspections enregistrées sur ce téléphone pour l'établissement, la plus récente d'abord.
  Future<List<ResumeInspection>> inspections(String etablissementId) async {
    final r = await db.customSelect(
      'SELECT i.id, i.date_inspection, i.statut, i.sync_status, i.taux_conformite, i.niveau, u.nom, u.prenoms '
      'FROM inspection i LEFT JOIN utilisateur u ON u.id = i.inspecteur_id '
      'WHERE i.etablissement_id = ? AND i.deleted_at IS NULL ORDER BY i.date_inspection DESC, i.updated_at DESC',
      variables: [variable(etablissementId)],
    ).get();
    return [
      for (final l in r)
        ResumeInspection(
          l.read<String>('id'),
          lireDate(l.read<String>('date_inspection')),
          StatutInspection.depuisCode(l.read<String>('statut')),
          EtatSync.depuisCode(l.read<String>('sync_status')),
          l.readNullable<double>('taux_conformite'),
          l.readNullable<String>('niveau') == null ? null : NiveauConformite.depuisCode(l.read<String>('niveau')),
          [l.readNullable<String>('nom'), l.readNullable<String>('prenoms')].whereType<String>().join(' '),
        )
    ];
  }

  // ------------------------------------------------------------------ photos

  Future<List<Enregistrement>> photos(String reponseId) =>
      depot.chercher('inspection_photo', {'inspection_reponse_id': reponseId});

  /// Photo d'une insuffisance constatée (aucune personne ne doit y figurer).
  /// La réponse doit avoir été enregistrée. Retourne `null` si l'utilisateur annule.
  Future<Enregistrement?> ajouterPhoto({
    required ImageSource source,
    required DossierInspection d,
    required String critereId,
    required String auteurId,
    String? commentaire,
  }) async {
    final reponseId = d.idsReponses[critereId];
    if (reponseId == null) throw StateError('Enregistrez d\'abord la réponse à ce critère.');
    final x = await _picker.pickImage(source: source, requestFullMetadata: false, imageQuality: 95);
    if (x == null) return null;
    final preparee = await compute(preparerPhoto, await x.readAsBytes());
    if (source == ImageSource.camera) {
      try {
        await File(x.path).delete();
      } catch (_) {}
    }
    return enregistrerPhoto(d, critereId: critereId, jpeg: preparee.jpeg, largeur: preparee.largeur,
        hauteur: preparee.hauteur, auteurId: auteurId, commentaire: commentaire);
  }

  /// Chiffre et rattache une photo déjà préparée (JPEG sans métadonnées).
  Future<Enregistrement> enregistrerPhoto(DossierInspection d,
      {required String critereId,
      required Uint8List jpeg,
      int? largeur,
      int? hauteur,
      required String auteurId,
      String? commentaire}) async {
    final reponseId = d.idsReponses[critereId];
    if (reponseId == null) throw StateError('Enregistrez d\'abord la réponse à ce critère.');
    final id = nouvelId();
    final chemin = await fichiers.ecrire('inspections', id, jpeg);
    try {
      return await depot.creer(
        'inspection_photo',
        {
          'inspection_reponse_id': reponseId,
          'auteur_id': auteurId,
          'chemin_chiffre': chemin,
          'empreinte_sha256': sha256Hex(jpeg),
          'taille_octets': jpeg.length,
          'largeur': largeur,
          'hauteur': hauteur,
          'commentaire': commentaire,
          'pris_le': formaterHorodatage(DateTime.now()),
          'statut_transfert': 'en_attente',
        },
        utilisateurId: auteurId,
        etablissementId: d.etablissementId,
        aTransmettre: !d.formulaire.modifiable,
        id: id,
      );
    } catch (_) {
      await fichiers.supprimer(chemin);
      rethrow;
    }
  }

  Future<Uint8List?> lirePhoto(Enregistrement photo) async {
    final chemin = photo.donnees['chemin_chiffre']! as String;
    if (!await fichiers.existe(chemin)) return null;
    return Uint8List.fromList(await fichiers.lire(chemin));
  }

  Future<void> supprimerPhoto(Enregistrement photo, {required String utilisateurId}) async {
    await depot.supprimer('inspection_photo', photo.id, utilisateurId: utilisateurId);
    if (photo.versionBase == 0) await fichiers.supprimer(photo.donnees['chemin_chiffre']! as String);
  }
}
