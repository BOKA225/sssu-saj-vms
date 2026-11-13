/// Rendu Excel (.xlsx) d'un [DocumentRapport] (paquet `excel`) : une feuille
/// avec l'en-tête institutionnel, le titre, puis chaque bloc à la suite.
/// Les nombres restent des nombres (exploitables dans Excel).
library;

import 'package:excel/excel.dart';

import 'document.dart';

List<int> rendreExcel(DocumentRapport d, {String nomFeuille = 'Rapport'}) {
  final excel = Excel.createExcel();
  final defaut = excel.getDefaultSheet() ?? 'Sheet1';
  excel.rename(defaut, nomFeuille);
  final f = excel[nomFeuille];
  var ligne = 0;
  var colonnesMax = 2;

  final gras = CellStyle(bold: true);
  final titre = CellStyle(bold: true, fontSize: 14);
  final entete = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.fromHexString('#FFFFFFFF'),
    backgroundColorHex: ExcelColor.fromHexString('#FF1F4E79'),
  );
  final total = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#FFE8EEF4'));

  CellValue? valeur(Object? v) {
    if (v == null) return null;
    if (v is int) return IntCellValue(v);
    if (v is double) return DoubleCellValue(v);
    if (v is bool) return TextCellValue(v ? 'oui' : 'non');
    return TextCellValue(v.toString());
  }

  void ecrire(List<Object?> cellules, {CellStyle? style}) {
    for (var c = 0; c < cellules.length; c++) {
      final cell = f.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: ligne));
      cell.value = valeur(cellules[c]);
      if (style != null) cell.cellStyle = style;
    }
    if (cellules.length > colonnesMax) colonnesMax = cellules.length;
    ligne++;
  }

  for (final l in d.entete.lignes) {
    ecrire([l], style: gras);
  }
  ligne++;
  ecrire([d.titre], style: titre);
  if (d.sousTitre != null) ecrire([d.sousTitre]);
  ecrire(['Édité le ${d.genereLe.toLocal().toString().substring(0, 16)}']);
  if (d.confidentiel) ecrire(['Document confidentiel (secret médical)'], style: gras);
  ligne++;

  for (final b in d.blocs) {
    switch (b) {
      case BlocTitre(:final texte):
        ligne++;
        ecrire([texte], style: titre);
      case BlocParagraphe(:final texte):
        ecrire([texte]);
      case BlocChamps(:final champs):
        for (final (l, v) in champs) {
          ecrire([l, v]);
          f.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: ligne - 1)).cellStyle = gras;
        }
        ligne++;
      case BlocTableau(:final titre, :final entetes, :final lignes, :final totaux):
        if (titre != null) ecrire([titre], style: gras);
        ecrire(entetes, style: entete);
        for (final l in lignes) {
          ecrire(l);
        }
        if (totaux != null) ecrire(totaux, style: total);
        ligne++;
      case BlocSignature(:final fonction, :final nom):
        ligne++;
        ecrire([fonction, nom ?? ''], style: gras);
      case BlocSignatures(:final signatures):
        ligne++;
        for (final x in signatures) {
          ecrire([x.fonction, x.nom ?? ''], style: gras);
        }
      case BlocImage(:final legende):
        if (legende != null) ecrire(['[Image] $legende']);
      case BlocSautDePage():
        ligne++;
    }
  }
  f.setColumnWidth(0, 38);
  for (var c = 1; c < colonnesMax; c++) {
    f.setColumnWidth(c, 16);
  }
  return excel.encode()!;
}

/// Modèle Excel de la liste des établissements à importer (intitulés
/// reconnus et une ligne d'exemple).
List<int> modeleListeEtablissements() {
  final excel = Excel.createExcel();
  final defaut = excel.getDefaultSheet() ?? 'Sheet1';
  excel.rename(defaut, 'Etablissements');
  final f = excel['Etablissements'];
  const entetes = [
    'Code', 'Nom', 'Type', 'Statut', 'Région', 'District sanitaire', 'Localité', 'Responsable', 'Téléphone'
  ];
  const exemple = [
    'KKR001', 'EPP Kouassikro 1', 'Primaire', 'Public', 'N\'Zi', 'Kouassi-Kouassikro', 'Kouassikro', 'M. KOFFI Jean',
    '0102030405'
  ];
  final gras = CellStyle(bold: true);
  for (var c = 0; c < entetes.length; c++) {
    f.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
      ..value = TextCellValue(entetes[c])
      ..cellStyle = gras;
    f.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1)).value = TextCellValue(exemple[c]);
    f.setColumnWidth(c, c == 1 ? 32 : 18);
  }
  return excel.encode()!;
}
