/// IMPORTATION DE LA LISTE DES ÉTABLISSEMENTS (Excel ou CSV) : code, nom,
/// type, statut, région, district sanitaire, localité, responsable,
/// téléphone. En-tête reconnu automatiquement ; chaque ligne est comparée
/// aux établissements connus (même code, ou même nom) pour être créée ou
/// mise à jour ; rien n'est enregistré avant la validation.
library;

import '../modeles/enums.dart';
import '../regles/identite.dart';
import 'champs.dart' show normaliserEntete;

enum ChampEtablissement {
  code('Code', 'code'),
  nom('Nom', 'nom'),
  type('Type / ordre d\'enseignement', 'type'),
  statut('Statut', 'statut'),
  region('Région', 'region'),
  district('District sanitaire', 'district_sanitaire'),
  localite('Localité', 'localite'),
  responsable('Responsable', 'responsable'),
  telephone('Téléphone', 'telephone'),
  ignorer('(ignorer)', '');

  final String libelle;

  /// Colonne de la table `etablissement`.
  final String colonne;
  const ChampEtablissement(this.libelle, this.colonne);
}

const _synonymes = <ChampEtablissement, List<String>>{
  ChampEtablissement.code: ['CODE', 'CODE ECOLE', 'CODE ETABLISSEMENT', 'CODE ETAB', 'IDENTIFIANT', 'ID', 'MATRICULE ECOLE'],
  ChampEtablissement.nom: [
    'NOM', 'ETABLISSEMENT', 'ETABLISSEMENTS', 'NOM ETABLISSEMENT', 'NOM DE L ETABLISSEMENT', 'ECOLE', 'ECOLES',
    'NOM ECOLE', 'NOM DE L ECOLE', 'DENOMINATION', 'RAISON SOCIALE', 'LIBELLE'
  ],
  ChampEtablissement.type: ['TYPE', 'ORDRE', 'ORDRE D ENSEIGNEMENT', 'NIVEAU', 'CYCLE', 'CATEGORIE', 'TYPE ETABLISSEMENT'],
  ChampEtablissement.statut: ['STATUT', 'SECTEUR', 'PUBLIC PRIVE', 'PUBLIC OU PRIVE', 'STATUT JURIDIQUE'],
  ChampEtablissement.region: ['REGION', 'DRENA', 'DREN', 'DIRECTION REGIONALE'],
  ChampEtablissement.district: ['DISTRICT', 'DISTRICT SANITAIRE', 'DDS', 'AIRE SANITAIRE', 'ESPC'],
  ChampEtablissement.localite: ['LOCALITE', 'VILLAGE', 'VILLE', 'COMMUNE', 'QUARTIER', 'SOUS PREFECTURE', 'LIEU'],
  ChampEtablissement.responsable: [
    'RESPONSABLE', 'DIRECTEUR', 'DIRECTRICE', 'CHEF D ETABLISSEMENT', 'CHEF ETABLISSEMENT', 'PROVISEUR', 'PRINCIPAL',
    'NOM DU DIRECTEUR', 'NOM DU RESPONSABLE', 'DIRECTEUR TRICE'
  ],
  ChampEtablissement.telephone: ['TELEPHONE', 'TEL', 'CONTACT', 'CONTACTS', 'CELLULAIRE', 'NUMERO DE TELEPHONE', 'PORTABLE'],
};

final _index = {
  for (final e in _synonymes.entries)
    for (final s in e.value) s: e.key,
};

ChampEtablissement? reconnaitreEnteteEtablissement(String intitule) {
  final n = normaliserEntete(intitule);
  if (n.isEmpty) return null;
  final direct = _index[n];
  if (direct != null) return direct;
  if (n.startsWith('CODE')) return ChampEtablissement.code;
  if (n.startsWith('TEL') || n.startsWith('CONTACT')) return ChampEtablissement.telephone;
  if (n.startsWith('STATUT') || n.startsWith('SECTEUR')) return ChampEtablissement.statut;
  if (n.startsWith('TYPE') || n.startsWith('ORDRE') || n.startsWith('CYCLE')) return ChampEtablissement.type;
  if (n.startsWith('LOCALIT') || n.startsWith('VILLAGE')) return ChampEtablissement.localite;
  if (n.startsWith('DISTRICT')) return ChampEtablissement.district;
  if (n.startsWith('REGION') || n.startsWith('DRENA')) return ChampEtablissement.region;
  if (n.contains('DIRECTEUR') || n.contains('RESPONSABLE') || n.startsWith('CHEF')) return ChampEtablissement.responsable;
  if (n.contains('ETABLISSEMENT') || n.contains('ECOLE')) return ChampEtablissement.nom;
  return null;
}

/// En-tête de la liste : la ligne qui reconnaît le plus de champs (au moins
/// deux, dont le nom), parmi les 15 premières.
(int, Map<int, ChampEtablissement>)? detecterEnteteEtablissements(List<List<String>> lignes) {
  (int, Map<int, ChampEtablissement>)? meilleure;
  var score = 1;
  for (var i = 0; i < lignes.length && i < 15; i++) {
    final c = <int, ChampEtablissement>{};
    for (var j = 0; j < lignes[i].length; j++) {
      final f = reconnaitreEnteteEtablissement(lignes[i][j]);
      if (f != null && !c.containsValue(f)) c[j] = f;
    }
    if (!c.containsValue(ChampEtablissement.nom)) continue;
    if (c.length > score) {
      score = c.length;
      meilleure = (i, c);
    }
  }
  return meilleure;
}

/// Type d'établissement d'après une cellule ou le nom (« EPP », « Collège »…).
TypeEtablissement? lireTypeEtablissement(String? texte) {
  final n = normaliserTexte(texte ?? '');
  if (n.isEmpty) return null;
  final mots = n.split(' ');
  bool a(String m) => mots.contains(m) || n.startsWith(m);
  if (a('PRESCOLAIRE') || a('MATERNELLE') || mots.contains('PRE') || n.contains('JARDIN D ENFANT')) {
    return TypeEtablissement.prescolaire;
  }
  if (a('TECHNIQUE') || a('PROFESSIONNEL') || a('LYCEE PROFESSIONNEL') || a('CFP') || a('LP')) return TypeEtablissement.technique;
  if (a('UNIVERSITE') || a('SUPERIEUR') || a('INSTITUT')) return TypeEtablissement.superieur;
  if (a('COLLEGE') || a('LYCEE') || a('SECONDAIRE') || a('CEG')) return TypeEtablissement.secondaire;
  if (a('EPP') || a('EP') || a('PRIMAIRE') || a('ECOLE') || a('GS') || a('EPV') || a('EPC')) return TypeEtablissement.primaire;
  for (final t in TypeEtablissement.values) {
    if (n == normaliserTexte(t.libelle) || n == t.code.toUpperCase()) return t;
  }
  return null;
}

StatutEtablissement? lireStatutEtablissement(String? texte) {
  final n = normaliserTexte(texte ?? '');
  if (n.isEmpty) return null;
  if (n.contains('PRIV') || n.contains('CONFESSION') || n.contains('CATHOLIQUE') || n.contains('PROTESTANT') ||
      n.contains('ISLAMIQUE') || n.contains('LAIC') || n.contains('METHODISTE')) {
    return StatutEtablissement.prive;
  }
  if (n.contains('PUBLIC') || n == 'ETAT' || n.contains('COMMUNAUTAIRE') || n.startsWith('EPP')) {
    return StatutEtablissement.public;
  }
  return null;
}

enum ActionEtablissement { creer, mettreAJour, ignorer }

class LigneEtablissementImport {
  final int numeroSource;
  final Map<ChampEtablissement, String> brut;
  String code;
  String nom;
  TypeEtablissement? type;
  StatutEtablissement? statut;
  String? region;
  String? district;
  String? localite;
  String? responsable;
  String? telephone;

  /// Établissement existant correspondant (même code, ou même nom).
  String? existantId;
  String? existantNom;
  ActionEtablissement action = ActionEtablissement.creer;
  final List<String> erreurs = [];
  final List<String> avertissements = [];

  LigneEtablissementImport({required this.numeroSource, required this.brut, required this.code, required this.nom});

  bool get bloquee => erreurs.isNotEmpty && action != ActionEtablissement.ignorer;

  /// Données de la table `etablissement` (champs connus seulement, pour ne
  /// pas effacer ce que la liste ne donne pas lors d'une mise à jour).
  Map<String, Object?> donnees() => {
        'code': code.trim().toUpperCase(),
        'nom': nom.trim(),
        if (type != null) 'type': type!.code,
        if (statut != null) 'statut': statut!.code,
        if (region?.trim().isNotEmpty ?? false) 'region': region!.trim(),
        if (district?.trim().isNotEmpty ?? false) 'district_sanitaire': district!.trim(),
        if (localite?.trim().isNotEmpty ?? false) 'localite': localite!.trim(),
        if (responsable?.trim().isNotEmpty ?? false) 'responsable': responsable!.trim(),
        if (telephone?.trim().isNotEmpty ?? false) 'telephone': telephone!.trim(),
      };
}

class EtablissementExistant {
  final String id;
  final String code;
  final String nom;
  const EtablissementExistant(this.id, this.code, this.nom);
}

/// Code proposé pour un établissement sans code (initiales et numéro du nom).
String codePropose(String nom, Set<String> pris) {
  final mots = normaliserTexte(nom).replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ').split(' ').where((m) => m.isNotEmpty).toList();
  final b = StringBuffer();
  for (final m in mots) {
    if (RegExp(r'^\d+$').hasMatch(m)) {
      b.write(m);
    } else {
      b.write(m.length <= 3 ? m : m.substring(0, 3));
    }
    if (b.length >= 12) break;
  }
  var base = b.toString();
  if (base.isEmpty) base = 'ETAB';
  if (base.length > 12) base = base.substring(0, 12);
  var code = base;
  for (var n = 2; pris.contains(code); n++) {
    code = '$base$n';
  }
  return code;
}

/// Lignes de la liste, contrôlées et comparées aux établissements connus.
/// [correspondance] : colonne → champ (après vérification par l'utilisateur).
List<LigneEtablissementImport> analyserEtablissements(
  List<List<String>> lignes, {
  required int? ligneEntete,
  required Map<int, ChampEtablissement> correspondance,
  required List<EtablissementExistant> existants,
}) {
  final parCode = {for (final e in existants) normaliserTexte(e.code).replaceAll(' ', ''): e};
  final parNom = {for (final e in existants) normaliserTexte(e.nom): e};
  final codesPris = {for (final e in existants) e.code.toUpperCase()};
  final vus = <String, int>{};
  final r = <LigneEtablissementImport>[];
  for (var i = (ligneEntete ?? -1) + 1; i < lignes.length; i++) {
    final cellules = lignes[i];
    final brut = <ChampEtablissement, String>{};
    for (final MapEntry(key: col, value: champ) in correspondance.entries) {
      if (champ == ChampEtablissement.ignorer || col >= cellules.length) continue;
      final v = cellules[col].trim();
      if (v.isNotEmpty) brut[champ] = brut[champ] == null ? v : '${brut[champ]} $v';
    }
    final nom = brut[ChampEtablissement.nom] ?? '';
    if (nom.isEmpty && brut.length <= 1) continue; // ligne vide, total ou numéro seul
    // En-tête répété (liste sur plusieurs pages).
    if (reconnaitreEnteteEtablissement(nom) == ChampEtablissement.nom && brut.length > 1 &&
        brut.values.where((v) => reconnaitreEnteteEtablissement(v) != null).length >= 2) {
      continue;
    }
    final l = LigneEtablissementImport(
        numeroSource: i + 1, brut: brut, code: (brut[ChampEtablissement.code] ?? '').toUpperCase(), nom: nom)
      ..region = brut[ChampEtablissement.region]
      ..district = brut[ChampEtablissement.district]
      ..localite = brut[ChampEtablissement.localite]
      ..responsable = brut[ChampEtablissement.responsable]
      ..telephone = brut[ChampEtablissement.telephone];
    if (nom.isEmpty) l.erreurs.add('Nom de l\'établissement manquant.');

    l.type = lireTypeEtablissement(brut[ChampEtablissement.type]) ?? lireTypeEtablissement(nom);
    l.statut = lireStatutEtablissement(brut[ChampEtablissement.statut]) ?? lireStatutEtablissement(nom);

    final existant = (l.code.isNotEmpty ? parCode[normaliserTexte(l.code).replaceAll(' ', '')] : null) ??
        parNom[normaliserTexte(nom)];
    if (existant != null) {
      l
        ..existantId = existant.id
        ..existantNom = existant.nom
        ..action = ActionEtablissement.mettreAJour;
      if (l.code.isEmpty) l.code = existant.code;
      if (l.code.toUpperCase() != existant.code.toUpperCase()) {
        l.avertissements.add('Même nom que « ${existant.nom} » (code ${existant.code}) : le code sera remplacé par ${l.code}.');
      }
    } else {
      if (l.type == null) {
        l.type = TypeEtablissement.primaire;
        l.avertissements.add('Type non précisé : « Primaire » retenu (à vérifier).');
      }
      if (l.statut == null) {
        l.statut = StatutEtablissement.public;
        l.avertissements.add('Statut non précisé : « Public » retenu (à vérifier).');
      }
      if (l.code.isEmpty && nom.isNotEmpty) {
        l.code = codePropose(nom, codesPris);
        l.avertissements.add('Code absent de la liste : ${l.code} proposé.');
      }
    }
    if (l.code.isNotEmpty) codesPris.add(l.code.toUpperCase());
    if (brut[ChampEtablissement.type] != null && lireTypeEtablissement(brut[ChampEtablissement.type]) == null) {
      l.avertissements.add('Type « ${brut[ChampEtablissement.type]} » non reconnu.');
    }
    final cle = l.code.isNotEmpty ? 'C:${l.code}' : 'N:${normaliserTexte(nom)}';
    final premiere = vus[cle];
    if (premiere != null) {
      l
        ..action = ActionEtablissement.ignorer
        ..avertissements.add('Doublon de la ligne $premiere dans la liste : ignorée.');
    } else {
      vus[cle] = l.numeroSource;
    }
    r.add(l);
  }
  return r;
}

class BilanEtablissements {
  final int aCreer;
  final int aMettreAJour;
  final int ignorees;
  final int bloquees;
  const BilanEtablissements(this.aCreer, this.aMettreAJour, this.ignorees, this.bloquees);
  bool get validable => bloquees == 0 && aCreer + aMettreAJour > 0;
}

BilanEtablissements bilanEtablissements(List<LigneEtablissementImport> l) => BilanEtablissements(
      l.where((x) => x.action == ActionEtablissement.creer && !x.bloquee).length,
      l.where((x) => x.action == ActionEtablissement.mettreAJour && !x.bloquee).length,
      l.where((x) => x.action == ActionEtablissement.ignorer).length,
      l.where((x) => x.bloquee).length,
    );
