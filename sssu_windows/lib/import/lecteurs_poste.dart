/// Lecture des listes nominatives sur le poste central : Excel (.xlsx), CSV,
/// PDF texte, et PDF scannés ou images par Tesseract OCR (hors ligne).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:excel/excel.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:sssu_core/sssu_core.dart';

import 'moteur_ocr.dart';

class ErreurLecture implements Exception {
  final String message;
  const ErreurLecture(this.message);
  @override
  String toString() => message;
}

typedef Progression = void Function(String etape);

const extensionsListes = ['xlsx', 'xls', 'csv', 'txt', 'pdf', 'jpg', 'jpeg', 'png', 'tif', 'tiff'];

class LecteurListes {
  /// Chemin de tesseract.exe (configuration), sinon recherche automatique.
  final String? cheminTesseract;
  LecteurListes({this.cheminTesseract});

  /// Tesseract et son modèle de langue française (voir moteur_ocr.dart).
  Future<MoteurOcr> moteurOcr() async {
    try {
      return await trouverMoteurOcr(cheminConfig: cheminTesseract);
    } on ErreurOcr catch (e) {
      throw ErreurLecture(e.message);
    }
  }

  /// Listes d'élèves d'un fichier : une par feuille utile d'un classeur Excel
  /// (classeur de plusieurs classes), sinon une seule.
  Future<List<TableauBrut>> lireTableaux(String chemin, {Progression? progression}) async {
    if (p.extension(chemin).toLowerCase() != '.xlsx') return [await lire(chemin, progression: progression)];
    final t = tableauxDuClasseur(_feuillesXlsx(await File(chemin).readAsBytes()));
    if (t.isEmpty) throw const ErreurLecture('Le classeur ne contient aucune donnée.');
    return t;
  }

  Future<TableauBrut> lire(String chemin, {Progression? progression}) async {
    final ext = p.extension(chemin).toLowerCase();
    switch (ext) {
      case '.csv':
      case '.txt':
        return tableauDepuisLignes(lireCsv(decoderTexte(await File(chemin).readAsBytes())), format: 'csv');
      case '.xlsx':
        return tableauDepuisLignes(_lireXlsx(await File(chemin).readAsBytes()), format: 'xlsx');
      case '.xls':
        throw const ErreurLecture('Le format .xls (Excel 97-2003) n\'est pas pris en charge : '
            'ouvrez le fichier dans Excel ou LibreOffice et enregistrez-le au format .xlsx.');
      case '.pdf':
        return _lirePdf(chemin, progression);
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.tif':
      case '.tiff':
        final source = img.decodeImage(await File(chemin).readAsBytes());
        if (source == null) throw const ErreurLecture('Image illisible.');
        progression?.call('Reconnaissance du texte (OCR)');
        return grilleDepuisMots(await _ocr(_pretraiter(img.bakeOrientation(source)), 0), format: 'image_ocr');
      default:
        throw ErreurLecture('Format non pris en charge ($ext).');
    }
  }

  /// Lignes brutes de la liste des établissements : Excel (.xlsx), CSV, PDF
  /// (texte ou scanné, lu par OCR) ou image d'une liste papier.
  Future<List<List<String>>> lireLignes(String chemin, {Progression? progression}) async {
    final ext = p.extension(chemin).toLowerCase();
    switch (ext) {
      case '.csv':
      case '.txt':
        return lireCsv(decoderTexte(await File(chemin).readAsBytes()));
      case '.xlsx':
        return _lireXlsx(await File(chemin).readAsBytes());
      case '.xls':
        throw const ErreurLecture('Le format .xls (Excel 97-2003) n\'est pas pris en charge : '
            'enregistrez le fichier au format .xlsx.');
      case '.pdf':
        return lignesEtablissementsDepuisMots((await _motsPdf(chemin, progression)).$1);
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.tif':
      case '.tiff':
        final source = img.decodeImage(await File(chemin).readAsBytes());
        if (source == null) throw const ErreurLecture('Image illisible.');
        progression?.call('Reconnaissance du texte (OCR)');
        return lignesEtablissementsDepuisMots(await _ocr(_pretraiter(img.bakeOrientation(source)), 0));
      default:
        throw ErreurLecture('Format non pris en charge ($ext) : Excel (.xlsx), CSV, PDF ou image.');
    }
  }

  /// Feuille la plus remplie du classeur.
  List<List<String>> _lireXlsx(Uint8List octets) {
    final meilleure = _feuillesXlsx(octets).fold<List<List<String>>>(
        const [], (m, f) => f.lignes.length > m.length ? f.lignes : m);
    if (meilleure.isEmpty) throw const ErreurLecture('Le classeur ne contient aucune donnée.');
    return meilleure;
  }

  /// Toutes les feuilles du classeur, dans l'ordre, sans les lignes vides.
  List<FeuilleBrute> _feuillesXlsx(Uint8List octets) {
    final Excel classeur;
    try {
      classeur = Excel.decodeBytes(octets);
    } catch (_) {
      throw const ErreurLecture('Fichier Excel illisible ou protégé par mot de passe.');
    }
    String texte(Data? d) {
      final v = d?.value;
      if (v == null) return '';
      if (v is DateCellValue) return formaterDate(DateTime.utc(v.year, v.month, v.day));
      if (v is DateTimeCellValue) return formaterDate(DateTime.utc(v.year, v.month, v.day));
      if (v is IntCellValue) return '${v.value}';
      if (v is DoubleCellValue) return v.value == v.value.roundToDouble() ? '${v.value.round()}' : '${v.value}';
      return v.toString().trim();
    }

    return [
      for (final e in classeur.tables.entries)
        FeuilleBrute(e.key, [
          for (final r in e.value.rows)
            if (r.any((c) => texte(c).isNotEmpty)) [for (final c in r) texte(c)]
        ])
    ];
  }

  Future<TableauBrut> _lirePdf(String chemin, Progression? progression) async {
    final (mots, format) = await _motsPdf(chemin, progression);
    return grilleDepuisMots(mots, format: format);
  }

  /// Mots positionnés d'un PDF : couche texte, ou reconnaissance optique
  /// page par page pour un PDF scanné. Renvoie aussi le format (`pdf`, `pdf_ocr`).
  Future<(List<MotPositionne>, String)> _motsPdf(String chemin, Progression? progression) async {
    final PdfDocument doc;
    try {
      doc = await PdfDocument.openFile(chemin);
    } catch (_) {
      throw const ErreurLecture('PDF illisible ou protégé par mot de passe.');
    }
    try {
      progression?.call('Lecture du texte du PDF');
      final mots = <MotPositionne>[];
      for (var i = 0; i < doc.pages.length; i++) {
        final page = doc.pages[i];
        for (final f in (await page.loadText()).fragments) {
          final b = f.bounds;
          mots.addAll(decouperFragment(MotPositionne(f.text,
              gauche: b.left, haut: page.height - b.top, largeur: b.right - b.left, hauteur: (b.top - b.bottom).abs(), page: i)));
        }
      }
      if (mots.length >= 10 * doc.pages.length) return (mots, 'pdf');

      // PDF scanné : reconnaissance optique page par page.
      final ocr = <MotPositionne>[];
      for (var i = 0; i < doc.pages.length; i++) {
        progression?.call('Reconnaissance du texte (OCR), page ${i + 1} sur ${doc.pages.length}');
        final page = doc.pages[i];
        final echelle = (2480 / page.width).clamp(1.0, 4.2);
        final rendu = await page.render(
            fullWidth: page.width * echelle, fullHeight: page.height * echelle, backgroundColor: const Color(0xFFFFFFFF));
        if (rendu == null) continue;
        final image = img.Image.fromBytes(
            width: rendu.width,
            height: rendu.height,
            bytes: Uint8List.fromList(rendu.pixels).buffer,
            numChannels: 4,
            order: img.ChannelOrder.bgra);
        rendu.dispose();
        ocr.addAll(await _ocr(_pretraiter(image), i));
      }
      return (ocr, 'pdf_ocr');
    } finally {
      await doc.dispose();
    }
  }

  Uint8List _pretraiter(img.Image image) => img.encodePng(img.adjustColor(img.grayscale(image), contrast: 1.3));

  Future<List<MotPositionne>> _ocr(Uint8List png, int page) async {
    final moteur = await moteurOcr();
    final dossier = await Directory.systemTemp.createTemp('sssu_ocr');
    try {
      final f = File(p.join(dossier.path, 'page.png'));
      await f.writeAsBytes(png, flush: true);
      final r = await Process.run(moteur.executable, moteur.arguments(f.path), stdoutEncoding: utf8);
      if (r.exitCode != 0) {
        throw ErreurLecture(messageEchecTesseract('${r.stderr}'));
      }
      return [for (final m in motsDepuisTsvTesseract(r.stdout as String, page: page)) m.mot];
    } finally {
      // Image nominative : supprimée aussitôt.
      await dossier.delete(recursive: true);
    }
  }
}
