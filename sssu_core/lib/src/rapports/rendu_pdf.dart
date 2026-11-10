/// Rendu PDF d'un [DocumentRapport] (paquet `pdf`).
///
/// Les polices sont fournies par l'application (DejaVu Sans, livrée dans
/// `sssu_windows/assets/polices/`) : les polices standard du PDF ne couvrent
/// pas tous les caractères français (tiret demi-cadratin, apostrophe…).
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../commun/commun.dart';
import 'document.dart';

class PolicesRapport {
  final List<int> normale;
  final List<int> grasse;
  final List<int>? italique;
  const PolicesRapport({required this.normale, required this.grasse, this.italique});
}

pw.Font _police(List<int> octets) => pw.Font.ttf(ByteData.sublistView(Uint8List.fromList(octets)));

const _bleu = PdfColor.fromInt(0xFF1F4E79);
const _gris = PdfColor.fromInt(0xFFE8EEF4);

String _dateHeure(DateTime d) {
  final l = d.toLocal();
  String z(int n) => n.toString().padLeft(2, '0');
  return '${z(l.day)}/${z(l.month)}/${l.year} à ${z(l.hour)} h ${z(l.minute)}';
}

Future<List<int>> rendrePdf(DocumentRapport d, PolicesRapport polices) async {
  final normale = _police(polices.normale);
  final grasse = _police(polices.grasse);
  final italique = polices.italique == null ? normale : _police(polices.italique!);
  final doc = pw.Document(
    title: d.titre,
    author: 'SSSU-SAJ VMS',
    theme: pw.ThemeData.withFont(base: normale, bold: grasse, italic: italique, boldItalic: grasse),
  );
  final format = d.paysage ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

  pw.Widget entete() {
    final lignes = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        for (final l in d.entete.lignes)
          pw.Text(l, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
      ],
    );
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      pw.SizedBox(
        width: 60,
        height: 60,
        child: d.entete.logoPng == null
            ? pw.Container(
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5)),
                alignment: pw.Alignment.center,
                child: pw.Text('Logo', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500)))
            : pw.Image(pw.MemoryImage(Uint8List.fromList(d.entete.logoPng!)), fit: pw.BoxFit.contain),
      ),
      pw.SizedBox(width: 12),
      pw.Expanded(child: lignes),
      pw.SizedBox(width: 72),
    ]);
  }

  List<pw.Widget> bloc(BlocRapport b) {
    switch (b) {
      case BlocTitre(:final texte):
        return [pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
          child: pw.Text(texte, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _bleu)),
        )];
      case BlocParagraphe(:final texte, :final italique):
        return [pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Text(texte,
              style: pw.TextStyle(fontSize: 9.5, fontStyle: italique ? pw.FontStyle.italic : pw.FontStyle.normal)),
        )];
      case BlocChamps(:final champs):
        return [pw.Table(
          columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(5)},
          children: [
            for (final (l, v) in champs)
              pw.TableRow(children: [
                pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                    child: pw.Text(l, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                    child: pw.Text(v.isEmpty ? '—' : v, style: const pw.TextStyle(fontSize: 9))),
              ]),
          ],
        )];
      case BlocTableau(:final titre, :final entetes, :final lignes, :final totaux, :final largeurs):
        final donnees = [
          for (final l in lignes) [for (final c in l) texteCellule(c)],
          if (totaux != null) [for (final c in totaux) texteCellule(c)],
        ];
        final numeriques = <int, pw.Alignment>{
          for (var i = 0; i < entetes.length; i++)
            if (lignes.isNotEmpty && lignes.every((l) => i < l.length && (l[i] is num || l[i] == null)))
              i: pw.Alignment.centerRight
        };
        final table = pw.TableHelper.fromTextArray(
          headers: entetes,
          data: donnees,
          headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: _bleu),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          cellAlignments: numeriques,
          headerAlignment: pw.Alignment.centerLeft,
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          oddRowDecoration: const pw.BoxDecoration(color: _gris),
          columnWidths: largeurs == null
              ? null
              : {for (var i = 0; i < largeurs.length; i++) i: pw.FlexColumnWidth(largeurs[i])},
        );
        // Éléments séparés (et non une colonne) : un long tableau se poursuit
        // sur les pages suivantes, avec ses en-têtes répétés.
        return [
          if (titre != null)
            pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6, bottom: 3),
                child: pw.Text(titre, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
          if (lignes.isEmpty && totaux == null)
            pw.Text('Aucune donnée.', style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic))
          else
            table,
          pw.SizedBox(height: 6),
        ];
      case BlocImage(:final png, :final legende, :final largeurMax):
        return [pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.ConstrainedBox(
                constraints: pw.BoxConstraints(maxWidth: largeurMax, maxHeight: largeurMax),
                child: pw.Image(pw.MemoryImage(Uint8List.fromList(png)), fit: pw.BoxFit.contain)),
            if (legende != null) pw.Text(legende, style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
          ]),
        )];
      case BlocSignature(:final fonction, :final nom, :final image, :final cachet):
        return [pw.Padding(
          padding: const pw.EdgeInsets.only(top: 18),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
            pw.SizedBox(
              width: 220,
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                pw.Text(fonction, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Container(
                  height: 70,
                  width: 200,
                  alignment: pw.Alignment.center,
                  decoration: image == null
                      ? pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5))
                      : null,
                  child: image == null
                      ? pw.Text(cachet ? 'Signature et cachet' : 'Signature',
                          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey500))
                      : pw.Image(pw.MemoryImage(Uint8List.fromList(image)), fit: pw.BoxFit.contain),
                ),
                pw.SizedBox(height: 4),
                pw.Text(nom ?? '', style: const pw.TextStyle(fontSize: 9)),
              ]),
            ),
          ]),
        )];
      case BlocSautDePage():
        return [pw.NewPage()];
    }
  }

  doc.addPage(pw.MultiPage(
    pageFormat: format,
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 36),
    header: (ctx) => ctx.pageNumber == 1
        ? pw.Column(children: [
            entete(),
            pw.Divider(color: _bleu, thickness: 1),
            pw.SizedBox(height: 4),
            pw.Text(d.titre,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _bleu)),
            if (d.sousTitre != null)
              pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Text(d.sousTitre!, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
            pw.SizedBox(height: 8),
          ])
        : pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Text(d.titre, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600))),
    footer: (ctx) => pw.Row(children: [
      pw.Expanded(
        child: pw.Text(
          'SSSU-SAJ VMS · édité le ${_dateHeure(d.genereLe)}${d.confidentiel ? ' · Document confidentiel (secret médical)' : ''}',
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        ),
      ),
      pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
    ]),
    build: (ctx) => [for (final b in d.blocs) ...bloc(b)],
  ));
  return doc.save();
}

/// Nom de fichier proposé : titre sans accents ni caractères spéciaux, et date.
String nomFichierRapport(DocumentRapport d, String extension) {
  const accents = {'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i',
    'ô': 'o', 'ö': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', 'œ': 'oe', 'æ': 'ae'};
  final base = d.titre.toLowerCase().split('').map((c) => accents[c] ?? c).join();
  final propre = base.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return '${propre.length > 60 ? propre.substring(0, 60) : propre}_${formaterDate(d.genereLe)}.$extension';
}
