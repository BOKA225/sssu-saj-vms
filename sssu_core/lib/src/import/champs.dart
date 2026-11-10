/// Champs d'une liste nominative et reconnaissance des intitulés de colonnes,
/// quelle que soit leur écriture (« Nom et prénoms », « NOMS & PRENOMS »,
/// « Né(e) le », « Date naiss. »…).
library;

import '../regles/identite.dart';

enum ChampListe {
  numero('N° d\'ordre'),
  matricule('Matricule'),
  nom('Nom'),
  prenoms('Prénoms'),
  nomPrenoms('Nom et prénoms'),
  dateNaissance('Date de naissance'),
  age('Âge'),
  sexe('Sexe'),
  telephone('Téléphone'),
  ignorer('(ignorer)');

  final String libelle;
  const ChampListe(this.libelle);

  bool get estNom => this == nom || this == prenoms || this == nomPrenoms;
}

/// Intitulés reconnus, après normalisation (majuscules, sans accents ni ponctuation).
const Map<ChampListe, List<String>> synonymesEntete = {
  ChampListe.numero: ['N', 'NO', 'NUM', 'NUMERO', 'N ORDRE', 'NO ORDRE', 'NUMERO D ORDRE', 'N D ORDRE', 'ORDRE', 'RANG'],
  ChampListe.matricule: [
    'MATRICULE', 'MATRICULES', 'MAT', 'MLE', 'N MATRICULE', 'NO MATRICULE', 'NUMERO MATRICULE',
    'NUMERO DE MATRICULE', 'MATRICULE ELEVE', 'ID ELEVE', 'IDENTIFIANT', 'IDENTIFIANT ELEVE',
  ],
  ChampListe.nom: ['NOM', 'NOMS', 'NOM DE FAMILLE', 'NOM ELEVE', 'PATRONYME'],
  ChampListe.prenoms: ['PRENOM', 'PRENOMS', 'PRENOM S'],
  ChampListe.nomPrenoms: [
    'NOM ET PRENOMS', 'NOM ET PRENOM', 'NOM ET PRENOM S', 'NOMS ET PRENOMS', 'NOM PRENOMS', 'NOM PRENOM',
    'NOMS PRENOMS', 'NOM ET PRENOMS DE L ELEVE', 'NOM ET PRENOMS ELEVE', 'ELEVE', 'ELEVES', 'NOM COMPLET',
    'IDENTITE', 'NOM PRENOMS ELEVE',
  ],
  ChampListe.dateNaissance: [
    'DATE DE NAISSANCE', 'DATE NAISSANCE', 'DATE DE NAIS', 'DATE NAIS', 'DATE NAISS', 'DATE DE NAISS',
    'D NAISSANCE', 'DN', 'NE LE', 'NE E LE', 'NEE LE', 'NE A', 'NAISSANCE', 'DATE ET LIEU DE NAISSANCE',
  ],
  ChampListe.age: ['AGE', 'AGES', 'AGE ANS', 'AGE EN ANNEES'],
  ChampListe.sexe: ['SEXE', 'SEXES', 'GENRE', 'S', 'SX', 'G F', 'M F'],
  ChampListe.telephone: [
    'TELEPHONE', 'TEL', 'N TEL', 'NO TEL', 'NUMERO DE TELEPHONE', 'CONTACT', 'CONTACTS', 'CONTACT PARENT',
    'CONTACT DU PARENT', 'TEL PARENT', 'TELEPHONE PARENT', 'CELLULAIRE', 'CEL', 'PORTABLE',
  ],
};

/// Normalisation d'un intitulé : `normaliserTexte` puis suppression de toute
/// ponctuation (« N° », « Né(e) le », « Nom & Prénoms » → « N », « NE E LE », « NOM PRENOMS »).
String normaliserEntete(String s) => normaliserTexte(s)
    .replaceAll('°', ' ')
    .replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

final Map<String, ChampListe> _index = {
  for (final e in synonymesEntete.entries)
    for (final s in e.value) s: e.key,
};

/// Champ dont un synonyme est exactement cet intitulé (après normalisation).
ChampListe? reconnaitreEnteteExact(String intitule) => _index[normaliserEntete(intitule)];

/// Champ correspondant à un intitulé, ou `null` s'il n'est pas reconnu.
ChampListe? reconnaitreEntete(String intitule) {
  final n = normaliserEntete(intitule);
  if (n.isEmpty) return null;
  final direct = _index[n];
  if (direct != null) return direct;
  // Intitulés plus longs : « NOM ET PRENOMS DES ELEVES », « DATE DE NAISSANCE (JJ/MM/AAAA) »…
  if (n.startsWith('DATE') && n.contains('NAIS')) return ChampListe.dateNaissance;
  if (n.contains('MATRICULE')) return ChampListe.matricule;
  if (n.contains('NOM') && n.contains('PRENOM')) return ChampListe.nomPrenoms;
  if (n.startsWith('PRENOM')) return ChampListe.prenoms;
  if (n.startsWith('NOM')) return ChampListe.nom;
  if (n.startsWith('TEL') || n.startsWith('CONTACT')) return ChampListe.telephone;
  if (n.startsWith('SEXE') || n.startsWith('GENRE')) return ChampListe.sexe;
  if (n.startsWith('AGE ')) return ChampListe.age;
  return null;
}

/// Nombre de mots maximal d'un intitulé (pour le regroupement des mots d'un PDF).
const int motsMaxIntitule = 7;
