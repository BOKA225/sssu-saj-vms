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
  const RubriqueInspection(this.code, this.libelle, this.elements);
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
