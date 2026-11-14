/// Listes de valeurs du modèle de données. Chaque `code` est la valeur stockée
/// en base (contraintes CHECK des schémas SQLite et PostgreSQL).
library;

T _depuisCode<T extends Enum>(List<T> valeurs, String code, String Function(T) lire) {
  for (final v in valeurs) {
    if (lire(v) == code) return v;
  }
  throw ArgumentError.value(code, 'code', 'Valeur inconnue pour $T');
}

enum Sexe {
  masculin('M', 'Masculin'),
  feminin('F', 'Féminin');

  final String code;
  final String libelle;
  const Sexe(this.code, this.libelle);
  static Sexe depuisCode(String c) => _depuisCode(values, c, (v) => v.code);
}

enum TypeEtablissement {
  prescolaire('prescolaire', 'Préscolaire'),
  primaire('primaire', 'Primaire'),
  secondaire('secondaire', 'Secondaire'),
  technique('technique', 'Technique'),
  superieur('superieur', 'Supérieur');

  final String code;
  final String libelle;
  const TypeEtablissement(this.code, this.libelle);
  static TypeEtablissement depuisCode(String c) => _depuisCode(values, c, (v) => v.code);
}

enum StatutEtablissement {
  public('public', 'Public'),
  prive('prive', 'Privé');

  final String code;
  final String libelle;
  const StatutEtablissement(this.code, this.libelle);
  static StatutEtablissement depuisCode(String c) => _depuisCode(values, c, (v) => v.code);
}

enum StatutInscription {
  inscrit('inscrit'),
  transfere('transfere'),
  sorti('sorti');

  final String code;
  const StatutInscription(this.code);
  static StatutInscription depuisCode(String c) => _depuisCode(values, c, (v) => v.code);
}

enum StatutVisite {
  ebauche('ebauche', 'Ébauche'),
  enregistre('enregistre', 'Enregistré localement'),
  enAttente('en_attente', 'En attente de synchronisation'),
  synchronise('synchronise', 'Synchronisé'),
  valide('valide', 'Validé');

  final String code;
  final String libelle;
  const StatutVisite(this.code, this.libelle);
  static StatutVisite depuisCode(String c) => _depuisCode(values, c, (v) => v.code);
}

enum ConclusionVisite {
  sansAnomalie('sans_anomalie', 'Élève sans anomalie décelée'),
  anomalie('anomalie', 'Élève présentant une anomalie'),
  suivi('suivi', 'Élève nécessitant un suivi médical'),
  reference('reference', 'Élève nécessitant une référence vers une structure sanitaire');

  final String code;
  final String libelle;
  const ConclusionVisite(this.code, this.libelle);
  static ConclusionVisite depuisCode(String c) => _depuisCode(values, c, (v) => v.code);
}

/// Type de visite médicale : la visite systématique concerne tous les élèves ;
/// la visite d'aptitude, les classes d'examen (3ème et Tle). Leurs
/// statistiques sont calculées séparément.
enum TypeVisite {
  systematique('systematique', 'Visite médicale systématique', 'Systématique'),
  aptitude('aptitude', 'Visite médicale d\'aptitude', 'Aptitude');

  final String code;
  final String libelle;
  final String court;
  const TypeVisite(this.code, this.libelle, this.court);
  static TypeVisite depuisCode(String? c) => c == null ? systematique : _depuisCode(values, c, (v) => v.code);
}

/// Décision d'une visite d'aptitude (pratique de l'EPS et examens).
enum DecisionAptitude {
  apte('apte', 'Apte'),
  aptePartiel('apte_partiel', 'Aptitude partielle (avec restrictions)'),
  inapteTemporaire('inapte_temporaire', 'Inapte temporairement'),
  inapteDefinitif('inapte_definitif', 'Inapte définitivement');

  final String code;
  final String libelle;
  const DecisionAptitude(this.code, this.libelle);
  static DecisionAptitude depuisCode(String c) => _depuisCode(values, c, (v) => v.code);

  /// Les restrictions ou le motif doivent être précisés.
  bool get aPreciser => this != apte;
}

enum ResultatInspection {
  conforme('conforme', 'Conforme'),
  partiel('partiel', 'Partiellement conforme'),
  nonConforme('non_conforme', 'Non conforme'),
  nonApplicable('non_applicable', 'Non applicable');

  final String code;
  final String libelle;
  const ResultatInspection(this.code, this.libelle);
  static ResultatInspection depuisCode(String c) => _depuisCode(values, c, (v) => v.code);
}

/// Rubriques de la grille d'inspection sanitaire (section 11 du prompt).
/// Les critères de chaque rubrique sont paramétrables (table `critere_inspection`).
enum RubriqueInspection {
  // Grille d'inspection sanitaire des établissements scolaires (sections B à J).
  eauBoisson('eau_boisson', 'B. Eau de boisson et points de rafraîchissement', 'Points d\'eau, source, qualité, entretien',
      lettre: 'B'),
  latrines('latrines', 'C. Latrines et toilettes', 'Disponibilité, séparation, état, propreté, entretien', lettre: 'C'),
  hygieneMains('hygiene_mains', 'D. Hygiène des mains', 'Dispositifs de lavage des mains, savon, pratiques', lettre: 'D'),
  hygieneMenstruelle('hygiene_menstruelle', 'E. Gestion de l\'hygiène menstruelle', 'Équipements et accompagnement des filles',
      lettre: 'E'),
  courDechets('cour_dechets', 'F. Salubrité de la cour et gestion des déchets', 'Poubelles, collecte, gîtes larvaires',
      lettre: 'F'),
  sallesClasse('salles_classe', 'G. Salles de classe', 'Propreté, effectifs, aération, éclairage, bâti', lettre: 'G'),
  cantineVente('cantine_vente', 'H. Cantine scolaire et vente d\'aliments', 'Cuisine, vivres, cuisinières, vendeuses',
      lettre: 'H'),
  securiteEnvironnement('securite_environnement', 'I. Sécurité et environnement', 'Clôture, bâtiments, risques, nuisances',
      lettre: 'I'),
  santeScolaire('sante_scolaire', 'J. Santé scolaire et promotion de la santé', 'Pharmacie, référent, registres, prévention',
      lettre: 'J'),

  // Ancienne grille (inspections faites avant la version 1.2.0).
  eauPotable('eau_potable', 'Eau potable', 'Disponibilité, accessibilité et qualité'),
  toilettes('toilettes', 'Toilettes', 'Nombre, propreté, fonctionnalité, séparation filles/garçons'),
  lavageMains('lavage_mains', 'Lavage des mains', 'Dispositifs et disponibilité du savon'),
  dechets('dechets', 'Gestion des déchets', 'Poubelles, collecte et évacuation'),
  environnement('environnement', 'Environnement', 'Propreté de la cour et des salles'),
  cantine('cantine', 'Cantines scolaires', 'Hygiène des locaux et des aliments'),
  vendeuses('vendeuses', 'Vendeuses', 'Conditions d\'hygiène et visite médicale'),
  infirmerie('infirmerie', 'Infirmerie', 'Disponibilité et fonctionnalité'),
  securite('securite', 'Sécurité', 'État des bâtiments et risques environnementaux');

  final String code;
  final String libelle;
  final String elements;

  /// Lettre de la section dans la grille ; `null` pour l'ancienne grille.
  final String? lettre;
  const RubriqueInspection(this.code, this.libelle, this.elements, {this.lettre});

  /// Rubrique de l'ancienne grille (critères désactivés en version 1.2.0).
  bool get ancienne => lettre == null;

  /// Rubriques proposées pour un nouveau critère.
  static List<RubriqueInspection> get actuelles => [for (final r in values) if (!r.ancienne) r];
  static RubriqueInspection depuisCode(String c) => _depuisCode(values, c, (v) => v.code);
}

enum StatutInspection {
  ebauche('ebauche', 'Ébauche'),
  enregistre('enregistre', 'Enregistrée'),
  valide('valide', 'Validée');

  final String code;
  final String libelle;
  const StatutInspection(this.code, this.libelle);
  static StatutInspection depuisCode(String c) => _depuisCode(values, c, (v) => v.code);
}

enum NiveauConformite {
  satisfaisant('satisfaisant', 'Satisfaisant'),
  moyen('moyen', 'Moyen'),
  insuffisant('insuffisant', 'Insuffisant');

  final String code;
  final String libelle;
  const NiveauConformite(this.code, this.libelle);
  static NiveauConformite depuisCode(String c) => _depuisCode(values, c, (v) => v.code);
}

/// État de synchronisation d'un enregistrement sur le téléphone.
enum EtatSync {
  /// Enregistré sur le téléphone, pas encore à transmettre (ébauche, enregistré).
  local('local'),

  /// À transmettre au poste central à la prochaine synchronisation.
  enAttente('en_attente'),

  /// Identique à la version confirmée par le poste central.
  synchronise('synchronise'),

  /// Refusé ou en conflit : à examiner sur le poste central.
  conflit('conflit');

  final String code;
  const EtatSync(this.code);
  static EtatSync depuisCode(String c) => _depuisCode(values, c, (v) => v.code);
}

enum TypeAntecedent {
  personnel('personnel', 'Antécédents médicaux personnels'),
  chirurgical('chirurgical', 'Antécédents chirurgicaux'),
  familial('familial', 'Antécédents familiaux'),
  allergique('allergique', 'Antécédents allergiques'),
  gynecologique('gynecologique', 'Antécédents gynécologiques'),
  traitement('traitement', 'Traitement médical en cours');

  final String code;
  final String libelle;
  const TypeAntecedent(this.code, this.libelle);
  static TypeAntecedent depuisCode(String c) => _depuisCode(values, c, (v) => v.code);
}

enum AppareilExamen {
  general('general', 'Examen général'),
  dermatologique('dermatologique', 'Examen dermatologique'),
  orl('orl', 'Examen ORL'),
  ophtalmologique('ophtalmologique', 'Examen ophtalmologique'),
  buccoDentaire('bucco_dentaire', 'Examen bucco-dentaire'),
  cardiovasculaire('cardiovasculaire', 'Examen cardiovasculaire'),
  respiratoire('respiratoire', 'Examen respiratoire'),
  digestif('digestif', 'Examen digestif'),
  neurologique('neurologique', 'Examen neurologique'),
  osteoArticulaire('osteo_articulaire', 'Examen ostéo-articulaire'),
  genitoUrinaire('genito_urinaire', 'Examen génito-urinaire');

  final String code;
  final String libelle;
  const AppareilExamen(this.code, this.libelle);
  static AppareilExamen depuisCode(String c) => _depuisCode(values, c, (v) => v.code);
}

enum ResultatExamen {
  normal('normal', 'Normal'),
  anormal('anormal', 'Anormal'),
  nonExamine('non_examine', 'Non examiné');

  final String code;
  final String libelle;
  const ResultatExamen(this.code, this.libelle);
  static ResultatExamen depuisCode(String c) => _depuisCode(values, c, (v) => v.code);
}
