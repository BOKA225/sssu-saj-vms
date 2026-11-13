// Choix de Tesseract et de son modèle de langue française sur le poste central.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sssu_core/sssu_core.dart';
import 'package:sssu_windows/import/moteur_ocr.dart';

void main() {
  late Directory racine;
  setUp(() async => racine = await Directory.systemTemp.createTemp('sssu_ocr_test'));
  tearDown(() async => racine.delete(recursive: true));

  Future<String> fichier(List<String> parties) async {
    final f = File(p.joinAll([racine.path, ...parties]));
    await f.create(recursive: true);
    return f.path;
  }

  Future<String?> aucun() async => null;

  test('Tesseract livré avec l\'application, avec son modèle français', () async {
    final app = p.join(racine.path, 'app');
    final exe = await fichier(['app', 'tesseract', 'tesseract.exe']);
    await fichier(['app', 'tesseract', 'tessdata', 'fra.traineddata']);
    final m = await trouverMoteurOcr(
        application: app, environnement: const {}, emplacementsUsuels: const [], chercherDansPath: aucun);
    final donnees = p.join(app, 'tesseract', 'tessdata');
    expect(m.executable, exe);
    expect(m.dossierDonnees, donnees);
    expect(m.arguments('page.png'),
        ['page.png', 'stdout', '--tessdata-dir', donnees, '-l', 'fra', '--psm', '6', '-c', 'tessedit_create_tsv=1']);
  });

  test('poste installé en 1.0 à 1.2.2 : Tesseract dans Program Files sans le français, '
      'modèle resté dans le dossier de l\'application', () async {
    final app = p.join(racine.path, 'app');
    await fichier(['app', 'tesseract', 'tessdata', 'fra.traineddata']);
    final usuel = await fichier(['Tesseract-OCR', 'tesseract.exe']);
    await fichier(['Tesseract-OCR', 'tessdata', 'eng.traineddata']);
    final m = await trouverMoteurOcr(
        cheminConfig: p.join(app, 'tesseract', 'tesseract.exe'), // absent : l'installateur l'a mis ailleurs
        application: app,
        environnement: const {},
        emplacementsUsuels: [usuel],
        chercherDansPath: aucun);
    expect(m.executable, usuel);
    expect(m.dossierDonnees, p.join(app, 'tesseract', 'tessdata'));
  });

  test('modèle trouvé par TESSDATA_PREFIX', () async {
    final usuel = await fichier(['Tesseract-OCR', 'tesseract.exe']);
    await fichier(['donnees', 'tessdata', 'fra.traineddata']);
    final m = await trouverMoteurOcr(
        application: p.join(racine.path, 'app'),
        environnement: {'TESSDATA_PREFIX': p.join(racine.path, 'donnees')},
        emplacementsUsuels: [usuel],
        chercherDansPath: aucun);
    expect(m.dossierDonnees, p.join(racine.path, 'donnees', 'tessdata'));
  });

  test('modèle français introuvable : message clair', () async {
    final usuel = await fichier(['Tesseract-OCR', 'tesseract.exe']);
    await fichier(['Tesseract-OCR', 'tessdata', 'eng.traineddata']);
    expect(
        () => trouverMoteurOcr(
            application: p.join(racine.path, 'app'),
            environnement: const {},
            emplacementsUsuels: [usuel],
            chercherDansPath: aucun),
        throwsA(isA<ErreurOcr>().having((e) => e.message, 'message', contains('fra.traineddata'))));
  });

  test('Tesseract absent', () async {
    expect(
        () => trouverMoteurOcr(
            application: p.join(racine.path, 'app'),
            environnement: const {},
            emplacementsUsuels: const [],
            chercherDansPath: aucun),
        throwsA(isA<ErreurOcr>().having((e) => e.message, 'message', contains('n\'est pas installé'))));
  });

  test('Tesseract du PATH sans modèle repéré : dossier par défaut de Tesseract', () async {
    final m = await trouverMoteurOcr(
        application: p.join(racine.path, 'app'),
        environnement: const {},
        emplacementsUsuels: const [],
        chercherDansPath: () async => 'tesseract');
    expect(m.executable, 'tesseract');
    expect(m.dossierDonnees, isNull);
    expect(m.arguments('x.png'), isNot(contains('--tessdata-dir')));
  });

  test('message d\'échec de Tesseract', () {
    final m = messageEchecTesseract('Error opening data file C:\\Program Files\\Tesseract-OCR/tessdata/fra.traineddata\n'
        'Failed loading language \'fra\'\nTesseract couldn\'t load any languages!');
    expect(m, contains('modèle de langue française'));
    expect(m, contains('1.2.3'));
    expect(messageEchecTesseract('autre problème\n'), 'Échec de Tesseract : autre problème');
  });

  // Vérifie les arguments avec un vrai Tesseract (installé dans l'intégration
  // continue) et un dossier qui ne contient QUE le modèle français.
  final systeme = ['/usr/share/tesseract-ocr/5/tessdata', '/usr/share/tesseract-ocr/4.00/tessdata']
      .map((d) => File(p.join(d, 'fra.traineddata')))
      .where((f) => f.existsSync())
      .firstOrNull;
  test('Tesseract lit une image avec un dossier ne contenant que fra.traineddata', () async {
    final donnees = Directory(p.join(racine.path, 'seul'))..createSync();
    systeme!.copySync(p.join(donnees.path, 'fra.traineddata'));
    final image = img.Image(width: 900, height: 160, numChannels: 3)..clear(img.ColorRgb8(255, 255, 255));
    img.drawString(image, 'KOUASSI Marie', font: img.arial48, x: 30, y: 50, color: img.ColorRgb8(0, 0, 0));
    final png = File(p.join(racine.path, 'page.png'))..writeAsBytesSync(img.encodePng(image));
    final moteur = MoteurOcr('tesseract', donnees.path);
    final r = await Process.run(moteur.executable, moteur.arguments(png.path));
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final mots = motsDepuisTsvTesseract(r.stdout as String).map((m) => m.mot.texte.toUpperCase()).toList();
    expect(mots, contains('KOUASSI'));
  }, skip: systeme == null ? 'Tesseract (français) non installé' : false);
}
