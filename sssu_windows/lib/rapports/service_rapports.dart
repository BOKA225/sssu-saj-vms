/// Édition des rapports sur le poste central : en-tête institutionnel lu
/// dans les paramètres, polices, rendu PDF ou Excel, enregistrement du
/// fichier choisi par l'utilisateur et trace dans le journal d'audit.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sssu_core/sssu_core.dart';

import '../donnees/source_statistiques.dart';
import '../donnees/stockage_photos.dart';

enum FormatRapport {
  pdf('pdf', 'PDF'),
  excel('xlsx', 'Excel');

  final String extension;
  final String libelle;
  const FormatRapport(this.extension, this.libelle);
}

class ServiceRapports {
  final SourceStatistiquesPoste source;
  final StockagePhotosPoste photos;
  final ServiceGestion gestion;

  /// Polices du PDF ; chargées depuis les ressources de l'application, ou
  /// fournies directement (tests).
  PolicesRapport? _polices;

  ServiceRapports({required this.source, required this.photos, required this.gestion, PolicesRapport? polices})
      : _polices = polices;

  Future<PolicesRapport> polices() async {
    if (_polices != null) return _polices!;
    Future<List<int>> lire(String nom) async => (await rootBundle.load('assets/polices/$nom')).buffer.asUint8List();
    return _polices = PolicesRapport(
      normale: await lire('DejaVuSans.ttf'),
      grasse: await lire('DejaVuSans-Bold.ttf'),
      italique: await lire('DejaVuSans-Oblique.ttf'),
    );
  }

  Future<EnteteRapport> entete() async {
    final p = await source.parametres();
    List<int>? logo;
    final b64 = p['logo_png'];
    if (b64 != null && b64.isNotEmpty) {
      try {
        logo = base64.decode(b64);
      } on FormatException {
        logo = null;
      }
    }
    return EnteteRapport.depuisParametres(p, logoPng: logo);
  }

  Future<List<int>> rendre(DocumentRapport d, FormatRapport format) async => switch (format) {
        FormatRapport.pdf => await rendrePdf(d, await polices()),
        FormatRapport.excel => rendreExcel(d),
      };

  /// Rend le document, l'écrit dans [chemin] et trace l'export.
  Future<void> enregistrer(DocumentRapport d, FormatRapport format, String chemin,
      {required Droits acteur, String? table, String? id}) async {
    final octets = await rendre(d, format);
    await File(chemin).writeAsBytes(octets, flush: true);
    await gestion.noterExport(acteur, d.titre,
        table: table, id: id, detail: {'format': format.extension, 'perimetre': d.sousTitre});
  }

  /// Photos d'une visite disponibles sur le poste (fichier reçu).
  Future<List<PhotoRapport>> photosVisite(FicheVisite fv, Map<String, String?> commentaires) async => [
        for (final id in fv.photos)
          if (await photos.disponible(id)) PhotoRapport(await photos.lire(id), commentaires[id] ?? 'Photographie')
      ];

  Future<Map<String, List<int>>> photosInspection(FicheInspection fi) async => {
        for (final r in fi.reponses)
          for (final id in r.photos)
            if (await photos.disponible(id)) id: await photos.lire(id)
      };
}
