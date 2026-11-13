/// Rendu Word (.docx, Office Open XML) d'un [DocumentRapport] : même contenu
/// que le PDF (en-tête institutionnel et logo, titres, tableaux, images,
/// signatures, pied de page avec numéros de page), modifiable dans Word ou
/// LibreOffice avant impression.
library;

import 'dart:convert';

import 'package:archive/archive.dart';

import 'document.dart';

const _bleu = '1F4E79';
const _gris = 'E8EEF4';

String _x(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

String _dateHeure(DateTime d) {
  final l = d.toLocal();
  String z(int n) => n.toString().padLeft(2, '0');
  return '${z(l.day)}/${z(l.month)}/${l.year} à ${z(l.hour)} h ${z(l.minute)}';
}

/// Dimensions (pixels) d'une image PNG ou JPEG, `null` si inconnues.
(int, int)? dimensionsImage(List<int> o) {
  if (o.length > 24 && o[0] == 0x89 && o[1] == 0x50 && o[2] == 0x4E && o[3] == 0x47) {
    int be(int i) => (o[i] << 24) | (o[i + 1] << 16) | (o[i + 2] << 8) | o[i + 3];
    return (be(16), be(20));
  }
  if (o.length > 4 && o[0] == 0xFF && o[1] == 0xD8) {
    var i = 2;
    while (i + 9 < o.length) {
      if (o[i] != 0xFF) {
        i++;
        continue;
      }
      final m = o[i + 1];
      final longueur = (o[i + 2] << 8) | o[i + 3];
      // Marqueurs SOF (dimensions), sauf DHT (C4), JPG (C8), DAC (CC).
      if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
        return ((o[i + 7] << 8) | o[i + 8], (o[i + 5] << 8) | o[i + 6]);
      }
      i += 2 + longueur;
    }
  }
  return null;
}

class _Media {
  final String nom;
  final String rid;
  final List<int> octets;
  const _Media(this.nom, this.rid, this.octets);
}

class _Redacteur {
  final DocumentRapport d;
  final medias = <_Media>[];
  final corps = StringBuffer();
  var _idDessin = 1;
  _Redacteur(this.d);

  // A4, marges 1,5 cm (850 twips) : largeur utile en twips.
  int get largeurUtile => d.paysage ? 16838 - 2 * 850 : 11906 - 2 * 850;

  String _run(String texte, {bool gras = false, bool italique = false, double taille = 10, String? couleur}) {
    final props = StringBuffer('<w:rPr>');
    if (gras) props.write('<w:b/>');
    if (italique) props.write('<w:i/>');
    if (couleur != null) props.write('<w:color w:val="$couleur"/>');
    props.write('<w:sz w:val="${(taille * 2).round()}"/><w:szCs w:val="${(taille * 2).round()}"/></w:rPr>');
    final lignes = texte.split('\n');
    final b = StringBuffer('<w:r>$props');
    for (var i = 0; i < lignes.length; i++) {
      if (i > 0) b.write('<w:br/>');
      b.write('<w:t xml:space="preserve">${_x(lignes[i])}</w:t>');
    }
    b.write('</w:r>');
    return b.toString();
  }

  String _para(String runs, {String align = 'left', int avant = 0, int apres = 60, bool garderAvecSuivant = false}) =>
      '<w:p><w:pPr>${garderAvecSuivant ? '<w:keepNext/>' : ''}<w:spacing w:before="$avant" w:after="$apres"/>'
      '<w:jc w:val="${align == 'left' ? 'left' : align}"/></w:pPr>$runs</w:p>';

  String _image(List<int> octets, double largeurMaxPt, {double? hauteurMaxPt}) {
    final dims = dimensionsImage(octets);
    final png = octets.length > 3 && octets[0] == 0x89;
    final n = medias.length + 1;
    final media = _Media('image$n.${png ? 'png' : 'jpeg'}', 'rIdImg$n', octets);
    medias.add(media);
    var l = largeurMaxPt;
    var h = largeurMaxPt * 0.75;
    if (dims != null && dims.$1 > 0 && dims.$2 > 0) {
      final ratio = dims.$2 / dims.$1;
      h = l * ratio;
      final hMax = hauteurMaxPt ?? largeurMaxPt;
      if (h > hMax) {
        h = hMax;
        l = h / ratio;
      }
    }
    final cx = (l * 12700).round();
    final cy = (h * 12700).round();
    final id = _idDessin++;
    return '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$id" name="Image $id"/>'
        '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:nvPicPr><pic:cNvPr id="$id" name="${media.nom}"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="${media.rid}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
        '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';
  }

  String _cellule(String contenu, int largeur, {String? fond, bool bordures = true}) =>
      '<w:tc><w:tcPr><w:tcW w:w="$largeur" w:type="dxa"/>'
      '${fond == null ? '' : '<w:shd w:val="clear" w:color="auto" w:fill="$fond"/>'}'
      '${bordures ? '' : '<w:tcBorders><w:top w:val="nil"/><w:left w:val="nil"/><w:bottom w:val="nil"/><w:right w:val="nil"/></w:tcBorders>'}'
      '<w:tcMar><w:top w:w="30" w:type="dxa"/><w:bottom w:w="30" w:type="dxa"/></w:tcMar></w:tcPr>$contenu</w:tc>';

  String _tableau(List<int> largeurs, List<String> lignes, {bool bordures = true}) {
    final b = StringBuffer('<w:tbl><w:tblPr><w:tblW w:w="${largeurs.fold(0, (a, x) => a + x)}" w:type="dxa"/>'
        '<w:tblLayout w:type="fixed"/>');
    if (bordures) {
      b.write('<w:tblBorders>');
      for (final c in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) {
        b.write('<w:$c w:val="single" w:sz="4" w:space="0" w:color="A6A6A6"/>');
      }
      b.write('</w:tblBorders>');
    }
    b.write('<w:tblCellMar><w:left w:w="70" w:type="dxa"/><w:right w:w="70" w:type="dxa"/></w:tblCellMar>'
        '</w:tblPr><w:tblGrid>');
    for (final l in largeurs) {
      b.write('<w:gridCol w:w="$l"/>');
    }
    b.write('</w:tblGrid>');
    for (final l in lignes) {
      b.write(l);
    }
    b.write('</w:tbl>');
    return b.toString();
  }

  List<int> _largeurs(int n, List<double>? relatives) {
    final r = relatives != null && relatives.length == n ? relatives : List<double>.filled(n, 1);
    final total = r.fold(0.0, (a, x) => a + x);
    return [for (final x in r) (largeurUtile * x / total).floor()];
  }

  void entete() {
    final lignes = [
      for (final l in d.entete.lignes) _para(_run(l, gras: true, taille: 8.5), align: 'center', apres: 0),
    ].join();
    final logo = d.entete.logoPng == null
        ? _para('')
        : _para(_image(d.entete.logoPng!, 55), align: 'center', apres: 0);
    final l1 = (largeurUtile * 0.16).floor();
    final l2 = largeurUtile - 2 * l1;
    corps.write(_tableau([l1, l2, l1], [
      '<w:tr>${_cellule(logo, l1, bordures: false)}${_cellule(lignes, l2, bordures: false)}${_cellule(_para(''), l1, bordures: false)}</w:tr>'
    ], bordures: false));
    corps.write('<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="8" w:space="1" w:color="$_bleu"/></w:pBdr>'
        '<w:spacing w:after="80"/></w:pPr></w:p>');
    corps.write(_para(_run(d.titre, gras: true, taille: 14, couleur: _bleu), align: 'center', apres: 40));
    if (d.sousTitre != null) corps.write(_para(_run(d.sousTitre!, taille: 10), align: 'center', apres: 160));
  }

  String _blocSignature(BlocSignature s) {
    final b = StringBuffer(_para(_run(s.fonction, gras: true, taille: 9.5), align: 'center', apres: 40));
    if (s.image != null) {
      b.write(_para(_image(s.image!, 150, hauteurMaxPt: 60), align: 'center', apres: 40));
    } else {
      b.write(_para(_run(s.cachet ? 'Signature et cachet' : 'Signature', italique: true, taille: 7.5, couleur: '999999'),
          align: 'center', avant: 500, apres: 500));
    }
    b.write(_para(_run(s.nom ?? '', taille: 9), align: 'center'));
    return b.toString();
  }

  void bloc(BlocRapport b) {
    switch (b) {
      case BlocTitre(:final texte):
        corps.write(_para(_run(texte, gras: true, taille: 12, couleur: _bleu), avant: 200, apres: 80, garderAvecSuivant: true));
      case BlocParagraphe(:final texte, :final italique):
        corps.write(_para(_run(texte, italique: italique, taille: 9.5)));
      case BlocChamps(:final champs):
        final l = _largeurs(2, const [2, 5]);
        corps.write(_tableau(l, [
          for (final (libelle, valeur) in champs)
            '<w:tr>${_cellule(_para(_run(libelle, gras: true, taille: 9), apres: 0), l[0], bordures: false)}'
                '${_cellule(_para(_run(valeur.isEmpty ? '—' : valeur, taille: 9), apres: 0), l[1], bordures: false)}</w:tr>'
        ], bordures: false));
        corps.write(_para('', apres: 60));
      case BlocTableau(:final titre, :final entetes, :final lignes, :final totaux, :final largeurs):
        if (titre != null) corps.write(_para(_run(titre, gras: true, taille: 10), avant: 100, apres: 40, garderAvecSuivant: true));
        if (lignes.isEmpty && totaux == null) {
          corps.write(_para(_run('Aucune donnée.', italique: true, taille: 9)));
          return;
        }
        final l = _largeurs(entetes.length, largeurs);
        final numerique = [
          for (var i = 0; i < entetes.length; i++)
            lignes.isNotEmpty && lignes.every((x) => i < x.length && (x[i] is num || x[i] == null))
        ];
        String ligne(List<Object?> cellules, {bool entete = false, bool total = false, bool paire = false}) {
          final b = StringBuffer('<w:tr>');
          if (entete) b.write('<w:trPr><w:tblHeader/><w:cantSplit/></w:trPr>');
          for (var i = 0; i < entetes.length; i++) {
            final v = i < cellules.length ? cellules[i] : null;
            final texte = entete ? '$v' : texteCellule(v);
            b.write(_cellule(
                _para(_run(texte, gras: entete || total, taille: 8.5, couleur: entete ? 'FFFFFF' : null),
                    align: !entete && numerique[i] ? 'right' : 'left', apres: 0),
                l[i],
                fond: entete ? _bleu : (total ? 'D9E2F3' : (paire ? _gris : null))));
          }
          b.write('</w:tr>');
          return b.toString();
        }

        corps.write(_tableau(l, [
          ligne(entetes, entete: true),
          for (final (i, x) in lignes.indexed) ligne(x, paire: i.isOdd),
          if (totaux != null) ligne(totaux, total: true),
        ]));
        corps.write(_para('', apres: 80));
      case BlocImage(:final png, :final legende, :final largeurMax):
        corps.write(_para(_image(png, largeurMax), apres: 20));
        if (legende != null) corps.write(_para(_run(legende, italique: true, taille: 8)));
      case BlocSignature():
        final l = _largeurs(2, const [1, 1]);
        corps.write(_tableau(l, [
          '<w:tr>${_cellule(_para(''), l[0], bordures: false)}${_cellule(_blocSignature(b), l[1], bordures: false)}</w:tr>'
        ], bordures: false));
      case BlocSignatures(:final signatures):
        final l = _largeurs(signatures.length, null);
        corps.write(_tableau(l, [
          '<w:tr>${[for (final (i, s) in signatures.indexed) _cellule(_blocSignature(s), l[i], bordures: false)].join()}</w:tr>'
        ], bordures: false));
      case BlocSautDePage():
        corps.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
    }
  }

  String documentXml() {
    final pg = d.paysage
        ? '<w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/>'
        : '<w:pgSz w:w="11906" w:h="16838"/>';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>$corps<w:sectPr><w:footerReference w:type="default" r:id="rIdPied"/>$pg'
        '<w:pgMar w:top="850" w:right="850" w:bottom="850" w:left="850" w:header="400" w:footer="400" w:gutter="0"/>'
        '</w:sectPr></w:body></w:document>';
  }

  String piedXml() {
    String champ(String instr) =>
        '<w:r><w:rPr><w:sz w:val="14"/></w:rPr><w:fldChar w:fldCharType="begin"/></w:r>'
        '<w:r><w:rPr><w:sz w:val="14"/></w:rPr><w:instrText xml:space="preserve"> $instr </w:instrText></w:r>'
        '<w:r><w:rPr><w:sz w:val="14"/></w:rPr><w:fldChar w:fldCharType="separate"/></w:r>'
        '<w:r><w:rPr><w:sz w:val="14"/></w:rPr><w:t>1</w:t></w:r>'
        '<w:r><w:rPr><w:sz w:val="14"/></w:rPr><w:fldChar w:fldCharType="end"/></w:r>';
    final texte = 'SSSU-SAJ VMS · édité le ${_dateHeure(d.genereLe)}'
        '${d.confidentiel ? ' · Document confidentiel (secret médical)' : ''}';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<w:p><w:pPr><w:tabs><w:tab w:val="right" w:pos="$largeurUtile"/></w:tabs></w:pPr>'
        '${_run(texte, taille: 7, couleur: '7F7F7F')}<w:r><w:tab/></w:r>'
        '${_run('Page ', taille: 7, couleur: '7F7F7F')}${champ('PAGE')}${_run(' / ', taille: 7, couleur: '7F7F7F')}'
        '${champ('NUMPAGES')}</w:p></w:ftr>';
  }
}

const _styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/>'
    '<w:sz w:val="20"/><w:szCs w:val="20"/><w:lang w:val="fr-FR"/></w:rPr></w:rPrDefault>'
    '<w:pPrDefault><w:pPr><w:spacing w:after="60" w:line="252" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
    '<w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/>'
    '<w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/>'
    '<w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/>'
    '</w:tblCellMar></w:tblPr></w:style></w:styles>';

/// Document Word (.docx) du rapport.
List<int> rendreWord(DocumentRapport d) {
  final r = _Redacteur(d)..entete();
  for (final b in d.blocs) {
    r.bloc(b);
  }
  final types = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="png" ContentType="image/png"/>'
      '<Default Extension="jpeg" ContentType="image/jpeg"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '<Override PartName="/word/footer1.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
      '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
      '</Types>');
  const rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="word/document.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" '
      'Target="docProps/core.xml"/></Relationships>';
  final docRels = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
      'Target="styles.xml"/>'
      '<Relationship Id="rIdPied" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" '
      'Target="footer1.xml"/>');
  for (final m in r.medias) {
    docRels.write('<Relationship Id="${m.rid}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/${m.nom}"/>');
  }
  docRels.write('</Relationships>');
  final date = d.genereLe.toUtc().toIso8601String().split('.').first;
  final core = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:title>${_x(d.titre)}</dc:title><dc:creator>SSSU-SAJ VMS</dc:creator>'
      '<dcterms:created xsi:type="dcterms:W3CDTF">${date}Z</dcterms:created></cp:coreProperties>';

  final a = Archive();
  void ajouter(String nom, List<int> octets) => a.addFile(ArchiveFile(nom, octets.length, octets));
  ajouter('[Content_Types].xml', utf8.encode(types.toString()));
  ajouter('_rels/.rels', utf8.encode(rels));
  ajouter('docProps/core.xml', utf8.encode(core));
  ajouter('word/document.xml', utf8.encode(r.documentXml()));
  ajouter('word/styles.xml', utf8.encode(_styles));
  ajouter('word/footer1.xml', utf8.encode(r.piedXml()));
  ajouter('word/_rels/document.xml.rels', utf8.encode(docRels.toString()));
  for (final m in r.medias) {
    ajouter('word/media/${m.nom}', m.octets);
  }
  // `encode` rend une liste nullable dans les versions 3 du paquet archive.
  final zip = ZipEncoder().encode(a);
  return zip ?? const <int>[];
}
