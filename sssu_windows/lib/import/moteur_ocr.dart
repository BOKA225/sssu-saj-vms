/// Choix du moteur de reconnaissance optique (Tesseract) du poste central :
/// l'exécutable et, séparément, le dossier qui contient le modèle de langue
/// française. Les deux sont cherchés indépendamment, car l'installateur
/// officiel de Tesseract s'installe toujours dans « C:\Program Files\Tesseract-OCR »
/// (en ignorant le dossier demandé) et supprime son dossier tessdata quand il
/// se réinstalle : le modèle français peut donc se trouver ailleurs que
/// l'exécutable. Le dossier retenu est passé à Tesseract par --tessdata-dir.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Erreur de mise en place de l'OCR, avec un message destiné à l'utilisateur.
class ErreurOcr implements Exception {
  final String message;
  const ErreurOcr(this.message);
  @override
  String toString() => message;
}

/// Emplacements usuels de Tesseract sous Windows.
const cheminsUsuelsTesseract = [
  r'C:\Program Files\Tesseract-OCR\tesseract.exe',
  r'C:\Program Files (x86)\Tesseract-OCR\tesseract.exe',
];

/// Langue des listes nominatives.
const langueOcr = 'fra';

/// Moteur retenu : exécutable, dossier des modèles de langue et langue.
class MoteurOcr {
  final String executable;

  /// Dossier contenant `fra.traineddata` (null : dossier par défaut de Tesseract).
  final String? dossierDonnees;
  final String langue;
  const MoteurOcr(this.executable, this.dossierDonnees, {this.langue = langueOcr});

  /// Arguments de Tesseract : sortie TSV (positions des mots) sur la sortie
  /// standard. Le TSV est demandé par une variable plutôt que par le fichier
  /// de configuration « tsv », absent d'un dossier qui ne contient que le
  /// modèle de langue.
  List<String> arguments(String image) => [
        image,
        'stdout',
        if (dossierDonnees != null) ...['--tessdata-dir', dossierDonnees!],
        '-l',
        langue,
        '--psm',
        '6',
        '-c',
        'tessedit_create_tsv=1',
      ];
}

/// Dossier de l'application (celui de sssu_windows.exe).
String dossierApplication() => p.dirname(Platform.resolvedExecutable);

/// Tesseract accessible par le PATH, sinon null.
Future<String?> tesseractDansPath() async {
  try {
    final r = await Process.run('tesseract', ['--version']);
    if (r.exitCode == 0) return 'tesseract';
  } catch (_) {}
  return null;
}

/// Cherche l'exécutable de Tesseract puis le dossier du modèle de langue :
/// - exécutable : chemin de la configuration, celui livré avec l'application
///   (`<application>\tesseract\tesseract.exe`), les emplacements usuels, le PATH ;
/// - modèle : dossier `tessdata` de l'exécutable retenu, celui de
///   l'application, TESSDATA_PREFIX, ceux des emplacements usuels.
/// Lève [ErreurOcr] si Tesseract ou le modèle français est introuvable.
Future<MoteurOcr> trouverMoteurOcr({
  String? cheminConfig,
  String? application,
  Map<String, String>? environnement,
  List<String> emplacementsUsuels = cheminsUsuelsTesseract,
  Future<String?> Function() chercherDansPath = tesseractDansPath,
}) async {
  final dossierApp = application ?? dossierApplication();
  final env = environnement ?? Platform.environment;
  final livre = p.join(dossierApp, 'tesseract', 'tesseract.exe');

  String? executable;
  for (final c in [if (cheminConfig != null && cheminConfig.trim().isNotEmpty) cheminConfig.trim(), livre, ...emplacementsUsuels]) {
    if (await File(c).exists()) {
      executable = c;
      break;
    }
  }
  executable ??= await chercherDansPath();
  if (executable == null) {
    throw const ErreurOcr('Tesseract OCR n\'est pas installé sur ce poste : impossible de lire un document scanné '
        'ou une photo. Réinstallez le poste central (l\'installateur fournit Tesseract) ou importez la liste '
        'depuis un téléphone.');
  }

  final dossiers = <String>[
    if (p.isAbsolute(executable)) p.join(p.dirname(executable), 'tessdata'),
    p.join(dossierApp, 'tesseract', 'tessdata'),
    if ((env['TESSDATA_PREFIX'] ?? '').trim().isNotEmpty) ...[
      env['TESSDATA_PREFIX']!.trim(),
      p.join(env['TESSDATA_PREFIX']!.trim(), 'tessdata'),
    ],
    for (final c in emplacementsUsuels) p.join(p.dirname(c), 'tessdata'),
  ];
  for (final d in dossiers) {
    if (await File(p.join(d, '$langueOcr.traineddata')).exists()) return MoteurOcr(executable, d);
  }
  // Tesseract trouvé par le PATH : il peut connaître son propre dossier de modèles.
  if (!p.isAbsolute(executable)) return MoteurOcr(executable, null);
  throw ErreurOcr('Le modèle de langue française de Tesseract ($langueOcr.traineddata) est introuvable sur ce poste : '
      'impossible de lire un document scanné ou une photo. Mettez à jour le poste central avec l\'installateur '
      '1.2.3 ou plus récent, qui le fournit.');
}

/// Message clair pour un échec de Tesseract (sortie d'erreur brute en complément).
String messageEchecTesseract(String sortieErreur) {
  final brut = sortieErreur.trim();
  if (brut.contains('Failed loading language') || brut.contains('traineddata') || brut.contains('load any languages')) {
    return 'Tesseract ne trouve pas le modèle de langue française ($langueOcr.traineddata). Mettez à jour le poste '
        'central avec l\'installateur 1.2.3 ou plus récent.\nDétail : $brut';
  }
  return 'Échec de Tesseract : $brut'.trim();
}
