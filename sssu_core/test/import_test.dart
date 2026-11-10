import 'dart:convert';

import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

MotPositionne _m(String t, double x, double y, {double w = 0, double h = 10, int page = 0}) =>
    MotPositionne(t, gauche: x, haut: y, largeur: w == 0 ? t.length * 6.0 : w, hauteur: h, page: page);

/// En-tête d'une liste de classe telle que la restitue un OCR.
List<MotPositionne> _entete(double y, {int page = 0}) => [
      _m('N°', 20, y, w: 15, page: page),
      _m('MATRICULE', 50, y, w: 60, page: page),
      _m('NOM', 130, y, w: 25, page: page),
      _m('ET', 158, y, w: 12, page: page),
      _m('PRENOMS', 173, y, w: 50, page: page),
      _m('Date', 300, y, w: 28, page: page),
      _m('de', 331, y, w: 12, page: page),
      _m('naissance', 346, y, w: 60, page: page),
      _m('Sexe', 430, y, w: 30, page: page),
    ];

void main() {
  group('Intitulés de colonnes', () {
    test('variantes reconnues', () {
      expect(reconnaitreEntete('Nom et Prénoms'), ChampListe.nomPrenoms);
      expect(reconnaitreEntete('NOMS & PRENOMS'), ChampListe.nomPrenoms);
      expect(reconnaitreEntete('Né(e) le'), ChampListe.dateNaissance);
      expect(reconnaitreEntete('Date de naissance (JJ/MM/AAAA)'), ChampListe.dateNaissance);
      expect(reconnaitreEntete('N° Matricule'), ChampListe.matricule);
      expect(reconnaitreEntete('Prénom(s)'), ChampListe.prenoms);
      expect(reconnaitreEntete('N°'), ChampListe.numero);
      expect(reconnaitreEntete('Contact parent'), ChampListe.telephone);
      expect(reconnaitreEntete('Observations'), isNull);
    });

    test('un nom d\'élève n\'est pas pris pour un intitulé en mode strict', () {
      expect(reconnaitreEntete('NOMEL'), ChampListe.nom);
      expect(reconnaitreEnteteExact('NOMEL'), isNull);
      expect(estEnteteRepete(['1', 'NOMEL Aya', 'TELLA']), isFalse);
      expect(estEnteteRepete(['N°', 'Nom', 'Prénoms', 'Sexe']), isTrue);
    });
  });

  group('CSV', () {
    test('Windows-1252, point-virgule, guillemets', () {
      final octets = [...latin1.encode('Matricule;Nom;Prénoms;Sexe\r\n'), ...latin1.encode('1;"KOUAMÉ; dit ""Jo""";Aya;F\r\n')];
      octets[latin1.encode('Matricule;Nom;Pr').length] = 0xE9; // « é » en Windows-1252
      final texte = decoderTexte(octets);
      expect(texte, contains('Prénoms'));
      final l = lireCsv(texte);
      expect(l.length, 2);
      expect(l[1], ['1', 'KOUAMÉ; dit "Jo"', 'Aya', 'F']);
    });

    test('UTF-8 avec BOM, virgule, ligne vide ignorée', () {
      final t = decoderTexte([0xEF, 0xBB, 0xBF, ...utf8.encode('Nom,Prénoms\n\nYAO,Koffi\n')]);
      expect(lireCsv(t), [
        ['Nom', 'Prénoms'],
        ['YAO', 'Koffi'],
      ]);
      expect(detecterSeparateur('a\tb\tc\n1\t2\t3'), '\t');
    });

    test('en-tête détecté sous les lignes de titre', () {
      final t = tableauDepuisLignes([
        ['LYCÉE TEST', '', ''],
        ['Liste de la classe de 6e 1', '', ''],
        ['N°', 'Nom et prénoms', 'Sexe', 'Né(e) le'],
        ['1', 'YAO Koffi', 'M', '02/01/2014'],
      ], format: 'csv');
      expect(t.ligneEntete, 2);
      expect(t.correspondance, {0: ChampListe.numero, 1: ChampListe.nomPrenoms, 2: ChampListe.sexe, 3: ChampListe.dateNaissance});
    });
  });

  group('PDF et OCR : reconstruction du tableau', () {
    test('colonnes décalées, intitulés de plusieurs mots, plusieurs pages, en-tête répété, nom sur deux lignes', () {
      final mots = <MotPositionne>[
        _m('ÉCOLE', 150, 20, page: 0), _m('TEST', 190, 20, page: 0), // titre
        ..._entete(100),
        // ligne 1 : nom décalé à gauche par rapport à son intitulé
        _m('1', 24, 120), _m('12345O78A', 52, 120, w: 58), _m('KOUASSI', 118, 120, w: 45), _m('Aya', 166, 120, w: 20),
        _m('Marie', 189, 120, w: 30), _m('12/O4/2015', 305, 120, w: 55), _m('F', 440, 120, w: 6),
        // ligne 2 : prénoms renvoyés à la ligne suivante
        _m('2', 24, 140), _m('87654321B', 52, 140, w: 58), _m('KONAN', 130, 140, w: 35), _m('Ahou', 168, 140, w: 26),
        _m('03-11-2014', 302, 140, w: 58), _m('F', 441, 140, w: 6),
        _m('Grâce', 168, 152, w: 30),
        // page 2 : en-tête répété puis une ligne
        ..._entete(30, page: 1),
        _m('3', 24, 50, page: 1), _m('11112222C', 52, 50, w: 58, page: 1), _m('YAO', 130, 50, w: 20, page: 1),
        _m('Koffi', 153, 50, w: 30, page: 1), _m('2014-01-02', 303, 50, w: 58, page: 1), _m('M', 438, 50, w: 8, page: 1),
      ];
      final t = grilleDepuisMots(mots, format: 'pdf_ocr');
      expect(t.ligneEntete, 0);
      expect(t.correspondance.values,
          [ChampListe.numero, ChampListe.matricule, ChampListe.nomPrenoms, ChampListe.dateNaissance, ChampListe.sexe]);

      final lignes = analyserTableau(t);
      expect(lignes.length, 3);
      expect(lignes[0].matricule, '12345078A');
      expect(lignes[0].notes.any((n) => n.startsWith('Matricule corrigé')), isTrue);
      expect(lignes[0].nom, 'KOUASSI');
      expect(lignes[0].prenoms, 'Aya Marie');
      expect(lignes[0].dateNaissance, DateTime.utc(2015, 4, 12));
      expect(lignes[0].sexe, Sexe.feminin);
      expect(lignes[1].prenoms, 'Ahou Grâce');
      expect(lignes[1].dateNaissance, DateTime.utc(2014, 11, 3));
      expect(lignes[2].nom, 'YAO');
      expect(lignes[2].sexe, Sexe.masculin);
    });

    test('fragment PDF découpé en mots', () {
      final m = decouperFragment(_m('KOUASSI Aya', 100, 0, w: 110));
      expect(m.map((x) => x.texte), ['KOUASSI', 'Aya']);
      expect(m[1].gauche, closeTo(180, 0.01));
    });

    test('sans en-tête reconnaissable : découpage aux grands espaces, colonnes à affecter', () {
      final t = grilleDepuisMots([
        _m('YAO', 10, 10), _m('Koffi', 40, 10), _m('M', 200, 10),
        _m('AKA', 10, 30), _m('Awa', 40, 30), _m('F', 200, 30),
      ], format: 'pdf');
      expect(t.ligneEntete, isNull);
      expect(t.lignes, [
        ['YAO Koffi', 'M'],
        ['AKA Awa', 'F'],
      ]);
      final lignes = analyserTableau(t.avecCorrespondance({0: ChampListe.nomPrenoms, 1: ChampListe.sexe}));
      expect(lignes.map((l) => l.nom), ['YAO', 'AKA']);
    });
  });

  group('Lecture des valeurs', () {
    test('matricule avec format', () {
      final f = RegExp(r'^\d{8}[A-Z]$');
      expect(lireMatricule('1234567BA', format: f).valeur, '12345678A');
      expect(lireMatricule('1234567BA', format: f).corrige, isTrue);
      expect(lireMatricule('12345678A', format: f).corrige, isFalse);
      expect(lireMatricule(' ', format: f).valeur, isNull);
    });

    test('dates : formats, OCR, numéro de série Excel, date suivie du lieu', () {
      expect(lireDateListe('12/04/2015'), DateTime.utc(2015, 4, 12));
      expect(lireDateListe('I2/O4/2Ol5'), DateTime.utc(2015, 4, 12));
      expect(lireDateListe('42106'), DateTime.utc(2015, 4, 12));
      expect(lireDateListe('12/04/2015 à Bouaké'), DateTime.utc(2015, 4, 12));
      expect(lireDateListe('inconnue'), isNull);
    });

    test('nom et prénoms', () {
      expect(separerNomPrenoms('KOUASSI Aya Marie'), ('KOUASSI', 'Aya Marie'));
      expect(separerNomPrenoms("N'GUESSAN KOUAME Akissi"), ("N'GUESSAN KOUAME", 'Akissi'));
      expect(separerNomPrenoms('YAO KOFFI JEAN'), ('YAO', 'KOFFI JEAN'));
      expect(separerNomPrenoms('Bamba'), ('Bamba', ''));
    });

    test('téléphone', () {
      expect(lireTelephone('07 01 02 03 04'), '0701020304');
      expect(lireTelephone('n/a'), isNull);
    });
  });

  group('Contrôle avant importation', () {
    final ref = DateTime.utc(2026, 11, 10);
    LigneImport ligne(int n, Map<ChampListe, String> brut) {
      final t = TableauBrut(
        lignes: [
          [for (final c in brut.keys) c.libelle],
          [for (final v in brut.values) v],
        ],
        ligneEntete: 0,
        correspondance: {for (var i = 0; i < brut.length; i++) i: brut.keys.elementAt(i)},
        format: 'csv',
      );
      final l = analyserTableau(t).single;
      return LigneImport(
          numeroSource: n,
          brut: l.brut,
          matricule: l.matricule,
          nom: l.nom,
          prenoms: l.prenoms,
          dateNaissance: l.dateNaissance,
          sexe: l.sexe,
          telephone: l.telephone,
          ageDeclare: l.ageDeclare);
    }

    test('anomalies bloquantes et avertissements', () {
      final lignes = [
        ligne(2, {ChampListe.nom: 'YAO', ChampListe.prenoms: 'Koffi', ChampListe.sexe: 'M', ChampListe.dateNaissance: '02/01/2014'}),
        ligne(3, {ChampListe.nom: 'AKA', ChampListe.prenoms: 'Awa', ChampListe.sexe: '?', ChampListe.dateNaissance: '02/01/2030'}),
        ligne(4, {ChampListe.nom: 'BROU', ChampListe.prenoms: 'Ehui', ChampListe.sexe: 'G', ChampListe.age: '9', ChampListe.dateNaissance: '02/01/2014'}),
      ];
      controlerLignes(lignes, dateReference: ref);
      expect(lignes[0].bloquee, isFalse);
      expect(lignes[0].anomalies.single.message, 'Matricule manquant.');
      expect(lignes[1].bloquee, isTrue);
      expect(lignes[1].anomalies.map((a) => a.champ), containsAll([ChampListe.sexe, ChampListe.dateNaissance]));
      expect(lignes[2].anomalies.map((a) => a.champ), contains(ChampListe.age));
      final b = bilan(lignes);
      expect(b.bloquees, 1);
      expect(b.validable, isFalse);

      // Correction par l'utilisateur, puis nouveau contrôle.
      lignes[1]
        ..sexe = Sexe.feminin
        ..dateNaissance = DateTime.utc(2015, 1, 2);
      controlerLignes(lignes, dateReference: ref);
      expect(bilan(lignes).validable, isTrue);
    });

    test('doublons : élève déjà connu rattaché, doublon du fichier ignoré, choix de l\'utilisateur conservé', () {
      final lignes = [
        ligne(2, {ChampListe.matricule: '12345678A', ChampListe.nomPrenoms: 'KOUASSI Aya', ChampListe.sexe: 'F'}),
        ligne(3, {ChampListe.matricule: '99999999Z', ChampListe.nomPrenoms: 'YAO Koffi', ChampListe.sexe: 'M'}),
        ligne(4, {ChampListe.matricule: '99999999Z', ChampListe.nomPrenoms: 'YAO Koffi', ChampListe.sexe: 'M'}),
      ];
      final existants = [const IdentiteEleve(id: 'e-1', matricule: '12345678A', nom: 'KOUASSI', prenoms: 'Aya')];
      controlerLignes(lignes, existants: existants, dateReference: ref);
      expect(lignes[0].action, ActionImport.rattacher);
      expect(lignes[0].eleveExistantId, 'e-1');
      expect(lignes[1].action, ActionImport.creer);
      expect(lignes[2].action, ActionImport.ignorer);
      expect(lignes[2].anomalies.any((a) => a.message.startsWith('Doublon de la ligne 3')), isTrue);

      lignes[2].imposerAction(ActionImport.creer);
      controlerLignes(lignes, existants: existants, dateReference: ref);
      expect(lignes[2].action, ActionImport.creer);
      final b = bilan(lignes);
      expect((b.aCreer, b.aRattacher, b.ignorees), (2, 1, 0));
      expect(donneesEleve(lignes[0])['sexe'], 'F');
    });
  });
}
