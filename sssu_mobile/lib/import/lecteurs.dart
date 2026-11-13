/// Lecture des listes nominatives : Excel (.xlsx), CSV, PDF (texte) et PDF
/// scannés ou photographies de listes (reconnaissance optique hors ligne,
/// Google ML Kit). Chaque lecteur produit un `TableauBrut` analysé ensuite
/// par le paquet commun.
library;

import 'dart:io';
import 'dart:ui' show Color;

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sssu_core/sssu_core.dart';

class ErreurImport implements Exception {
  final String message;
  const ErreurImport(this.message);
  @override
  String toString() => message;
}

/// Avancement d'une lecture longue (OCR page par page).
typedef Progression = void Function(String etape, double? avancement);

const extensionsAcceptees = ['xlsx', 'xls', 'csv', 'txt', 'pdf', 'jpg', 'jpeg', 'png'];

Future<TableauBrut> lireListe(String chemin, {Progression? progression}) async {
  final ext = p.extension(chemin).toLowerCase();
  switch (ext) {
    case '.csv':
    case '.txt':
      return tableauDepuisLignes(lireCsv(decoderTexte(await File(chemin).readAsBytes())), format: 'csv');
    case '.xlsx':
      return tableauDepuisLignes(await compute(lireXlsx, await File(chemin).readAsBytes()), format: 'xlsx');
    case '.xls':
      throw const ErreurImport('Le format .xls (Excel 97-2003) ne peut pas être lu sur le téléphone. '
          'Ouvrez le fichier dans Excel ou LibreOffice et enregistrez-le au format .xlsx, puis recommencez.');
    case '.pdf':
      return lirePdf(chemin, progression: progression);
    case '.jpg':
    case '.jpeg':
    case '.png':
      return lireImage(chemin, progression: progression);
    default:
      throw ErreurImport('Format non pris en charge ($ext). Formats acceptés : Excel (.xlsx), CSV, PDF, photo.');
  }
}

// -------------------------------------------------------------------- Excel

String _texteCellule(Data? d) {
  final v = d?.value;
  if (v == null) return '';
  if (v is DateCellValue) return formaterDate(DateTime.utc(v.year, v.month, v.day));
  if (v is DateTimeCellValue) return formaterDate(DateTime.utc(v.year, v.month, v.day));
  if (v is IntCellValue) return '${v.value}';
  if (v is DoubleCellValue) {
    final x = v.value;
    return x == x.roundToDouble() ? '${x.round()}' : '$x';
  }
  return v.toString().trim();
}

/// Feuille la plus remplie du classeur, en lignes de texte.
List<List<String>> lireXlsx(Uint8List octets) {
  final meilleure = lireFeuillesXlsx(octets)
      .fold<List<List<String>>>(const [], (m, f) => f.lignes.length > m.length ? f.lignes : m);
  if (meilleure.isEmpty) throw const ErreurImport('Le classeur ne contient aucune donnée.');
  return meilleure;
}

/// Toutes les feuilles du classeur, dans l'ordre, sans les lignes vides.
List<FeuilleBrute> lireFeuillesXlsx(Uint8List octets) {
  final Excel classeur;
  try {
    classeur = Excel.decodeBytes(octets);
  } catch (_) {
    throw const ErreurImport('Fichier Excel illisible ou protégé par mot de passe.');
  }
  return [
    for (final e in classeur.tables.entries)
      FeuilleBrute(e.key, [
        for (final r in e.value.rows)
          if (r.any((c) => _texteCellule(c).isNotEmpty)) [for (final c in r) _texteCellule(c)]
      ])
  ];
}

/// Listes d'élèves d'un fichier : une par feuille utile d'un classeur Excel
/// (une classe par feuille), sinon une seule.
Future<List<TableauBrut>> lireListes(String chemin, {Progression? progression}) async {
  if (p.extension(chemin).toLowerCase() != '.xlsx') return [await lireListe(chemin, progression: progression)];
  final t = tableauxDuClasseur(await compute(lireFeuillesXlsx, await File(chemin).readAsBytes()));
  if (t.isEmpty) throw const ErreurImport('Le classeur ne contient aucune donnée.');
  return t;
}

// ---------------------------------------------------------------------- PDF

/// Lit le texte du PDF ; s'il n'en contient presque pas (document scanné),
/// passe à la reconnaissance optique page par page.
Future<TableauBrut> lirePdf(String chemin, {Progression? progression}) async {
  final PdfDocument doc;
  try {
    doc = await PdfDocument.openFile(chemin);
  } catch (_) {
    throw const ErreurImport('PDF illisible ou protégé par mot de passe.');
  }
  try {
    progression?.call('Lecture du texte du PDF', null);
    final mots = <MotPositionne>[];
    for (var i = 0; i < doc.pages.length; i++) {
      final page = doc.pages[i];
      final texte = await page.loadText();
      for (final f in texte.fragments) {
        final b = f.bounds;
        // Coordonnées PDF (origine en bas à gauche) → origine en haut à gauche.
        mots.addAll(decouperFragment(MotPositionne(
          f.text,
          gauche: b.left,
          haut: page.height - b.top,
          largeur: b.right - b.left,
          hauteur: (b.top - b.bottom).abs(),
          page: i,
        )));
      }
    }
    if (mots.length >= 10 * doc.pages.length) return grilleDepuisMots(mots, format: 'pdf');
    return await _ocrPdf(doc, progression);
  } finally {
    await doc.dispose();
  }
}

Future<TableauBrut> _ocrPdf(PdfDocument doc, Progression? progression) async {
  final reconnaissance = TextRecognizer(script: TextRecognitionScript.latin);
  final mots = <MotPositionne>[];
  try {
    final n = doc.pages.length;
    for (var i = 0; i < n; i++) {
      progression?.call('Reconnaissance du texte (OCR), page ${i + 1} sur $n', i / n);
      final page = doc.pages[i];
      // Environ 300 points par pouce pour une page A4.
      final echelle = (2480 / page.width).clamp(1.0, 4.2);
      final rendu = await page.render(
        fullWidth: page.width * echelle,
        fullHeight: page.height * echelle,
        backgroundColor: const Color(0xFFFFFFFF),
      );
      if (rendu == null) continue;
      final png = await compute(pretraiterPixels, (Uint8List.fromList(rendu.pixels), rendu.width, rendu.height));
      rendu.dispose();
      mots.addAll(await _reconnaitre(reconnaissance, png, page: i));
    }
  } finally {
    await reconnaissance.close();
  }
  progression?.call('Reconstruction du tableau', 1);
  return grilleDepuisMots(mots, format: 'pdf_ocr');
}

/// Photo ou image d'une liste.
Future<TableauBrut> lireImage(String chemin, {Progression? progression}) async {
  progression?.call('Préparation de l\'image', null);
  final png = await compute(pretraiterImage, await File(chemin).readAsBytes());
  final reconnaissance = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    progression?.call('Reconnaissance du texte (OCR)', 0.5);
    return grilleDepuisMots(await _reconnaitre(reconnaissance, png, page: 0), format: 'image_ocr');
  } finally {
    await reconnaissance.close();
  }
}

/// Niveaux de gris et contraste renforcé : améliore la lecture des listes
/// photocopiées. Exécuté hors du fil d'affichage.
Uint8List pretraiterPixels((Uint8List, int, int) a) {
  final (pixels, largeur, hauteur) = a;
  final image = img.Image.fromBytes(
      width: largeur, height: hauteur, bytes: pixels.buffer, numChannels: 4, order: img.ChannelOrder.bgra);
  return img.encodePng(img.adjustColor(img.grayscale(image), contrast: 1.3));
}

Uint8List pretraiterImage(Uint8List octets) {
  final source = img.decodeImage(octets);
  if (source == null) throw const ErreurImport('Image illisible.');
  var image = img.bakeOrientation(source);
  if (image.width > 3000) image = img.copyResize(image, width: 3000);
  return img.encodePng(img.adjustColor(img.grayscale(image), contrast: 1.3));
}

Future<List<MotPositionne>> _reconnaitre(TextRecognizer r, Uint8List png, {required int page}) async {
  final dossier = await getTemporaryDirectory();
  final f = File(p.join(dossier.path, 'ocr_${DateTime.now().microsecondsSinceEpoch}.png'));
  await f.writeAsBytes(png, flush: true);
  try {
    final resultat = await r.processImage(InputImage.fromFilePath(f.path));
    return [
      for (final bloc in resultat.blocks)
        for (final ligne in bloc.lines)
          for (final el in ligne.elements)
            MotPositionne(
              el.text,
              gauche: el.boundingBox.left,
              haut: el.boundingBox.top,
              largeur: el.boundingBox.width,
              hauteur: el.boundingBox.height,
              page: page,
            ),
    ];
  } finally {
    // L'image de la liste contient des données nominatives : effacée aussitôt.
    await f.delete();
  }
}
