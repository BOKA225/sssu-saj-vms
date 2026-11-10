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

class ErreurLecture implements Exception {
  final String message;
  const ErreurLecture(this.message);
  @override
  String toString() => message;
}

typedef Progression = void Function(String etape);

const extensionsListes = ['xlsx', 'xls', 'csv', 'txt', 'pdf', 'jpg', 'jpeg', 'png', 'tif', 'tiff'];

/// Emplacements usuels de Tesseract sous Windows.
const _cheminsTesseract = [
  r'C:\Program Files\Tesseract-OCR\tesseract.exe',
  r'C:\Program Files (x86)\Tesseract-OCR\tesseract.exe',
];

class LecteurListes {
  /// Chemin de tesseract.exe (configuration), sinon recherche automatique.
  final String? cheminTesseract;
  LecteurListes({this.cheminTesseract});

  Future<String?> tesseract() async {
    for (final c in [if (cheminTesseract != null) cheminTesseract!, ..._cheminsTesseract]) {
      if (await File(c).exists()) return c;
    }
    try {
      final r = await Process.run('tesseract', ['--version']);
      if (r.exitCode == 0) return 'tesseract';
    } catch (_) {}
    return null;
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

  List<List<String>> _lireXlsx(Uint8List octets) {
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

    List<List<String>> meilleure = const [];
    for (final f in classeur.tables.values) {
      final lignes = [
        for (final r in f.rows)
          if (r.any((c) => texte(c).isNotEmpty)) [for (final c in r) texte(c)]
      ];
      if (lignes.length > meilleure.length) meilleure = lignes;
    }
    if (meilleure.isEmpty) throw const ErreurLecture('Le classeur ne contient aucune donnée.');
    return meilleure;
  }

  Future<TableauBrut> _lirePdf(String chemin, Progression? progression) async {
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
      if (mots.length >= 10 * doc.pages.length) return grilleDepuisMots(mots, format: 'pdf');

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
      return grilleDepuisMots(ocr, format: 'pdf_ocr');
    } finally {
      await doc.dispose();
    }
  }

  Uint8List _pretraiter(img.Image image) => img.encodePng(img.adjustColor(img.grayscale(image), contrast: 1.3));

  Future<List<MotPositionne>> _ocr(Uint8List png, int page) async {
    final exe = await tesseract();
    if (exe == null) {
      throw const ErreurLecture('Tesseract OCR n\'est pas installé sur ce poste : impossible de lire un document '
          'scanné. Installez Tesseract (avec la langue française) ou importez la liste depuis un téléphone.');
    }
    final dossier = await Directory.systemTemp.createTemp('sssu_ocr');
    try {
      final f = File(p.join(dossier.path, 'page.png'));
      await f.writeAsBytes(png, flush: true);
      final r = await Process.run(exe, [f.path, 'stdout', '-l', 'fra', '--psm', '6', 'tsv'], stdoutEncoding: utf8);
      if (r.exitCode != 0) {
        throw ErreurLecture('Échec de Tesseract : ${r.stderr}'.trim());
      }
      return [for (final m in motsDepuisTsvTesseract(r.stdout as String, page: page)) m.mot];
    } finally {
      // Image nominative : supprimée aussitôt.
      await dossier.delete(recursive: true);
    }
  }
}
