/// Reconnaissance automatique de l'établissement et de la classe d'une liste
/// d'élèves importée, d'après ses titres (« EPP KOUASSIKRO 1 – CLASSE DE
/// CM2 A ») et le nom du fichier (`Liste_CM2A_EPP_Kouassikro1.xlsx`).
///
/// La proposition est soumise à l'administrateur, qui la confirme ou la
/// corrige : rien n'est importé sans sa validation.
library;

import '../regles/identite.dart';

class EtablissementConnu {
  final String id;
  final String nom;
  final String code;
  final String? localite;
  const EtablissementConnu({required this.id, required this.nom, required this.code, this.localite});
}

class ClasseConnue {
  final String id;
  final String etablissementId;
  final String libelle;
  final String? niveau;
  const ClasseConnue({required this.id, required this.etablissementId, required this.libelle, this.niveau});
}

/// Classe lue dans les titres, à créer si elle n'existe pas.
class ClasseLue {
  /// Libellé proposé (« CM2 A »).
  final String libelle;

  /// Niveau normalisé (« CM2 », « 6EME »…).
  final String niveau;
  const ClasseLue(this.libelle, this.niveau);
}

class ReconnaissanceListe {
  final EtablissementConnu? etablissement;

  /// Confiance de 0 à 1 dans l'établissement proposé.
  final double confianceEtablissement;

  /// Classe existante de l'établissement proposé.
  final ClasseConnue? classe;

  /// Classe lue dans les titres (existante ou à créer).
  final ClasseLue? classeLue;

  /// Explication affichée (« nom lu dans le titre », « code dans le nom du fichier »…).
  final List<String> raisons;
  const ReconnaissanceListe({
    this.etablissement,
    this.confianceEtablissement = 0,
    this.classe,
    this.classeLue,
    this.raisons = const [],
  });

  bool get classeACreer => classe == null && classeLue != null && etablissement != null;
}

/// Mots trop courants pour distinguer un établissement.
const _motsCommuns = {
  'EPP', 'EP', 'EPV', 'EPC', 'ECOLE', 'PRIMAIRE', 'PUBLIQUE', 'PRIVEE', 'PRIVE', 'CONFESSIONNELLE', 'CATHOLIQUE',
  'PROTESTANTE', 'ISLAMIQUE', 'METHODISTE', 'COLLEGE', 'LYCEE', 'MODERNE', 'MUNICIPAL', 'MUNICIPALE', 'GROUPE',
  'SCOLAIRE', 'PRESCOLAIRE', 'MATERNELLE', 'CEG', 'CEPE', 'CENTRE', 'INSTITUT', 'COMPLEXE', 'DE', 'DU', 'DES', 'LA',
  'LE', 'LES', 'L', 'D', 'ET', 'A', 'AU', 'AUX', 'EN', 'SAINT', 'STE', 'ST', 'LISTE', 'ELEVES', 'ELEVE', 'CLASSE',
  'ANNEE', 'NOMINATIVE', 'EFFECTIF', 'IEPP', 'DRENA', 'DREN', 'COTE', 'IVOIRE', 'REPUBLIQUE', 'MINISTERE', 'EDUCATION',
  'NATIONALE', 'ALPHABETISATION', 'XLSX', 'XLS', 'CSV', 'PDF', 'JPG', 'JPEG', 'PNG', 'SCAN', 'PHOTO', 'IMG',
};

List<String> _mots(String s) => normaliserTexte(s)
    .replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ')
    // « KOUASSIKRO1 » → « KOUASSIKRO 1 »
    .replaceAllMapped(RegExp(r'([A-Z]{3,})(\d+)\b'), (m) => '${m[1]} ${m[2]}')
    .split(' ')
    .where((m) => m.isNotEmpty)
    .toList();

String _compact(String s) => normaliserTexte(s).replaceAll(RegExp(r'[^A-Z0-9]'), '');

// ------------------------------------------------------------------ classes

/// Niveaux reconnus (préscolaire, primaire, secondaire), avec leurs écritures.
const _niveaux = <String, List<String>>{
  // « PS », « MS », « GS » seuls ne sont pas retenus dans les titres : « GS »
  // désigne aussi un groupe scolaire.
  'PS': ['PETITESECTION'],
  'MS': ['MOYENNESECTION'],
  'GS': ['GRANDESECTION'],
  'CP1': ['CP1'],
  'CP2': ['CP2'],
  'CE1': ['CE1'],
  'CE2': ['CE2'],
  'CM1': ['CM1'],
  'CM2': ['CM2'],
  '6EME': ['6EME', '6E', '6IEME', 'SIXIEME'],
  '5EME': ['5EME', '5E', '5IEME', 'CINQUIEME'],
  '4EME': ['4EME', '4E', '4IEME', 'QUATRIEME'],
  '3EME': ['3EME', '3E', '3IEME', 'TROISIEME'],
  '2NDE': ['2NDE', '2ND', 'SECONDE', '2DE'],
  '1ERE': ['1ERE', '1RE', 'PREMIERE'],
  'TLE': ['TLE', 'TERMINALE', 'TERM', 'TALE'],
  // Enseignement technique et professionnel (les séries B, E, F1 à F7, G1,
  // G2 sont des sections de 2nde, 1ère et Tle : « 2nde G1 », « Tle F2 »).
  'BTS': ['BTS'],
  'BT': ['BT'],
  'BEP': ['BEP'],
  'CAP': ['CAP'],
};

final _ecritures = [
  for (final e in _niveaux.entries)
    for (final x in e.value) (x, e.key)
]..sort((a, b) => b.$1.length.compareTo(a.$1.length));

/// Libellé de classe normalisé pour comparaison : « CM2-A », « cm2 a »,
/// « CM2A » → « CM2A » ; « 6ème 3 », « 6e3 » → « 6EME3 ».
String cleClasse(String libelle) {
  var c = _compact(libelle).replaceFirst(RegExp(r'^CLASSE(DE|DU)?'), '');
  for (final (ecriture, niveau) in _ecritures) {
    if (c.startsWith(ecriture)) {
      final reste = c.substring(ecriture.length);
      // « 6E » suivi d'un chiffre ou d'une lettre : section (« 6E3 »,
      // « 2NDG1A » pour la 2nde G1 A de l'enseignement technique).
      if (RegExp(r'^[A-Z0-9]{0,4}$').hasMatch(reste)) return '$niveau$reste';
    }
  }
  return c;
}

/// Classe lue dans un texte (« Classe : CM2 A », « LISTE DES ÉLÈVES DE 6ème 3 »,
/// « 2nd G1 », « Terminale F2-2 », « BT 1 »).
ClasseLue? lireClasse(String texte) {
  final t = normaliserTexte(texte).replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ');
  final motifs = _ecritures.map((e) => e.$1.replaceAll('SECTION', ' SECTION')).join('|');
  // Niveau, puis éventuellement une section, jamais un mot :
  // - série avec groupe : « G1 A », « G1A », « F2 2 » ;
  // - lettre ou série : « A », « D », « G », « G1 », « F2 » ;
  // - numéro : « 3 », « 12 », « 4B ».
  const section = r'[A-Z][0-9] ?[A-Z]|[A-Z][0-9]? ?[0-9]{1,2}|[A-Z][0-9]?|[0-9]{1,2}[A-Z]?';
  final re = RegExp('(?:^| )($motifs)(?: ?($section))?(?= |\$)');
  for (final m in re.allMatches(t)) {
    final ecriture = m[1]!.replaceAll(' ', '');
    final niveau = _ecritures.firstWhere((e) => e.$1 == ecriture).$2;
    final section = m[2];
    final affiche = switch (niveau) {
      'PS' => 'Petite section',
      'MS' => 'Moyenne section',
      'GS' => 'Grande section',
      '6EME' || '5EME' || '4EME' || '3EME' => '${niveau.substring(0, 1)}ème',
      '2NDE' => '2nde',
      '1ERE' => '1ère',
      'TLE' => 'Tle',
      _ => niveau,
    };
    return ClasseLue(section == null ? affiche : '$affiche $section', niveau);
  }
  return null;
}

/// Classe existante de l'établissement qui correspond à une classe lue :
/// même libellé à l'écriture près (« 2nd G1 » = « 2nde G1 » = « Seconde G1 »),
/// sinon la seule classe du niveau quand la classe lue n'a pas de section
/// (« CM2 » pour une école qui n'a qu'un CM2).
ClasseConnue? rapprocherClasse(ClasseLue lue, String etablissementId, List<ClasseConnue> classes) {
  final cle = cleClasse(lue.libelle);
  final memeLibelle = [for (final c in classes) if (c.etablissementId == etablissementId && cleClasse(c.libelle) == cle) c];
  if (memeLibelle.length == 1) return memeLibelle.single;
  if (memeLibelle.isEmpty && lue.niveau.isNotEmpty && cle == lue.niveau) {
    final memeNiveau = [
      for (final c in classes)
        if (c.etablissementId == etablissementId && (lireClasse(c.libelle)?.niveau ?? c.niveau) == lue.niveau) c
    ];
    if (memeNiveau.length == 1) return memeNiveau.single;
  }
  return null;
}

/// Niveau normalisé d'un libellé de classe (« 2nde G1 » → « 2NDE »), pour
/// remplir le niveau d'une classe créée sans niveau.
String? niveauDeClasse(String libelle) => lireClasse(libelle)?.niveau;

/// Classes usuelles proposées à la saisie, par ordre d'enseignement.
final Map<String, List<String>> classesUsuelles = {
  'Préscolaire': ['Petite section', 'Moyenne section', 'Grande section'],
  'Primaire': ['CP1', 'CP2', 'CE1', 'CE2', 'CM1', 'CM2'],
  'Secondaire général': [
    '6ème', '5ème', '4ème', '3ème', '2nde A', '2nde C', '1ère A', '1ère C', '1ère D', 'Tle A', 'Tle C', 'Tle D'
  ],
  'Enseignement technique': [
    '2nde G',
    for (final n in ['2nde', '1ère', 'Tle'])
      for (final s in ['B', 'E', 'F1', 'F2', 'F3', 'F4', 'F7', 'G1', 'G2']) '$n $s',
    'BT 1', 'BT 2', 'BT 3', 'CAP 1', 'CAP 2', 'CAP 3', 'BEP 1', 'BEP 2',
  ],
};

/// Classes usuelles qui commencent comme la saisie, à l'écriture près
/// (« 2nd g » → 2nde G, 2nde G1, 2nde G2 ; « tle f » → Tle F1… ; « g1 » → les G1).
List<String> suggestionsClasses(String saisie) {
  final t = saisie.trim();
  if (t.isEmpty) return const [];
  final cle = cleClasse(t);
  final compact = _compact(t);
  return [
    for (final groupe in classesUsuelles.values)
      for (final c in groupe)
        if (cleClasse(c).startsWith(cle) || (compact.length >= 2 && _compact(c).contains(compact))) c
  ];
}

// ----------------------------------------------------------- établissement

/// Petits mots ignorés.
const _motsVides = {'DE', 'DU', 'DES', 'LA', 'LE', 'LES', 'L', 'D', 'ET', 'A', 'AU', 'AUX', 'EN'};

/// Note de 0 à 1 : mots distinctifs du nom retrouvés (80 %), mots du type
/// d'établissement retrouvés (EPP, collège… : 20 %), numéro de l'école
/// obligatoire ; code de l'établissement : certitude.
double _scoreEtablissement(EtablissementConnu e, Set<String> mots, String compact) {
  final code = _compact(e.code);
  if (code.length >= 3 && (mots.contains(code) || compact.contains(code))) return 1;
  final nom = [for (final m in _mots(e.nom)) if (!_motsVides.contains(m)) m];
  final distinctifs = [for (final m in nom) if (!_motsCommuns.contains(m)) m];
  final types = [for (final m in nom) if (_motsCommuns.contains(m)) m];
  final nombres = [for (final m in distinctifs) if (RegExp(r'^\d+$').hasMatch(m)) m];
  final lettres = [for (final m in distinctifs) if (!RegExp(r'^\d+$').hasMatch(m)) m];
  if (lettres.isEmpty) return 0;
  // Un long mot peut être collé à un autre (« EPPKOUASSIKRO »).
  bool trouve(String m) => mots.contains(m) || (m.length >= 8 && compact.contains(m));
  final partDistinctive = lettres.where(trouve).length / lettres.length;
  if (partDistinctive == 0) return 0;
  var score = types.isEmpty ? partDistinctive : 0.8 * partDistinctive + 0.2 * (types.where(trouve).length / types.length);
  // Numéro de l'école (« KOUASSIKRO 1 » / « KOUASSIKRO 2 ») : doit correspondre.
  if (nombres.isNotEmpty && !nombres.every(mots.contains)) score *= 0.5;
  // Nom complet présent : certitude plus grande.
  if (compact.contains(_compact(e.nom)) && score < 0.95) score = 0.95;
  return score;
}

/// Propose l'établissement et la classe d'une liste. [titres] : texte lu
/// avant l'en-tête du tableau ; [nomFichier] : nom du fichier importé ;
/// [classes] : classes de l'année en cours. [classeLue] : classe déjà lue
/// (colonne « Classe », nom de la feuille), prioritaire sur les titres.
/// [lireLaClasse] faux : fichier de plusieurs classes, seul l'établissement
/// est cherché (chaque classe est rapprochée à part, voir [rapprocherClasse]).
ReconnaissanceListe reconnaitreListe({
  required List<String> titres,
  String? nomFichier,
  required List<EtablissementConnu> etablissements,
  required List<ClasseConnue> classes,
  ClasseLue? classeLue,
  bool lireLaClasse = true,
}) {
  final fichier = nomFichier == null ? '' : nomFichier.replaceAll(RegExp(r'\.[A-Za-z0-9]{2,4}$'), '').replaceAll('_', ' ');
  final sources = [...titres, if (fichier.isNotEmpty) fichier];
  final texte = sources.join(' ');
  final mots = _mots(texte).toSet();
  final compact = _compact(texte);
  final raisons = <String>[];

  // Établissement : meilleur score, avec un écart suffisant sur le suivant.
  EtablissementConnu? etab;
  var meilleur = 0.0;
  var second = 0.0;
  for (final e in etablissements) {
    final s = _scoreEtablissement(e, mots, compact);
    if (s > meilleur) {
      second = meilleur;
      meilleur = s;
      etab = e;
    } else if (s > second) {
      second = s;
    }
  }
  if (etab == null || meilleur < 0.6 || meilleur - second < 0.15) {
    if (etab != null && meilleur >= 0.6) raisons.add('Plusieurs établissements possibles : choisissez-le.');
    etab = null;
    meilleur = 0;
  } else {
    final dansFichier = _scoreEtablissement(etab, _mots(fichier).toSet(), _compact(fichier)) >= meilleur &&
        _scoreEtablissement(etab, _mots(titres.join(' ')).toSet(), _compact(titres.join(' '))) < meilleur;
    raisons.add('Établissement « ${etab.nom} » reconnu dans ${dansFichier ? 'le nom du fichier' : 'le titre de la liste'}.');
  }

  // Classe : celle déjà lue, sinon d'abord dans les titres, puis dans le nom du fichier.
  ClasseLue? lue = lireLaClasse ? classeLue : null;
  if (lireLaClasse && lue == null) {
    for (final s in sources) {
      lue = lireClasse(s);
      if (lue != null) break;
    }
  }
  ClasseConnue? classe;
  if (lue != null && etab != null) {
    classe = rapprocherClasse(lue, etab.id, classes);
    if (classe != null) {
      raisons.add('Classe « ${classe.libelle} » reconnue.');
    } else {
      raisons.add('Classe « ${lue.libelle} » lue : elle n\'existe pas encore dans cet établissement pour cette année.');
    }
  } else if (lue != null) {
    raisons.add('Classe « ${lue.libelle} » lue.');
  }
  if (!lireLaClasse && etab == null) {
    raisons.add('Établissement non reconnu : choisissez-le.');
  } else if (etab == null && lue == null) {
    raisons.add('Ni l\'établissement ni la classe n\'ont été reconnus : choisissez-les.');
  }
  return ReconnaissanceListe(
    etablissement: etab,
    confianceEtablissement: meilleur,
    classe: classe,
    classeLue: lue,
    raisons: raisons,
  );
}
