/// Formulaire de visite médicale (rubriques A à F) et contrôles avant
/// transmission. Le formulaire est indépendant du stockage : le téléphone le
/// charge depuis sa base et l'y enregistre (visite, antécédents, examens par
/// appareil, pathologies dépistées).
library;

import '../commun/commun.dart';
import '../modeles/enums.dart';
import '../regles/age.dart';
import '../regles/constantes.dart';
import '../regles/imc.dart';

class ReponseAntecedent {
  bool coche;
  String commentaire;
  ReponseAntecedent({this.coche = false, this.commentaire = ''});

  bool get renseigne => coche || commentaire.trim().isNotEmpty;
}

class ReponseExamen {
  ResultatExamen resultat;
  String observation;
  ReponseExamen({this.resultat = ResultatExamen.nonExamine, this.observation = ''});
}

class FormulaireVisite {
  /// Identifiant de la visite (créé à la première sauvegarde).
  String? id;
  final String eleveId;
  final String? inscriptionId;
  final String agentId;
  final String? appareilId;
  DateTime dateVisite;
  String? structureOrigine;
  StatutVisite statut;

  double? poidsKg;
  double? tailleCm;
  int? taSys;
  int? taDia;
  double? temperatureC;
  int? fc;
  int? fr;

  ConclusionVisite? conclusion;
  String diagnostic;
  String conduiteATenir;
  String traitementConseils;
  String structureReference;
  DateTime? dateControle;
  String observations;

  final Map<TypeAntecedent, ReponseAntecedent> antecedents;
  final Map<AppareilExamen, ReponseExamen> examens;

  /// Pathologies dépistées : identifiant → précision (texte libre).
  final Map<String, String> pathologies;

  FormulaireVisite({
    this.id,
    required this.eleveId,
    this.inscriptionId,
    required this.agentId,
    this.appareilId,
    required this.dateVisite,
    this.structureOrigine,
    this.statut = StatutVisite.ebauche,
    this.poidsKg,
    this.tailleCm,
    this.taSys,
    this.taDia,
    this.temperatureC,
    this.fc,
    this.fr,
    this.conclusion,
    this.diagnostic = '',
    this.conduiteATenir = '',
    this.traitementConseils = '',
    this.structureReference = '',
    this.dateControle,
    this.observations = '',
    Map<TypeAntecedent, ReponseAntecedent>? antecedents,
    Map<AppareilExamen, ReponseExamen>? examens,
    Map<String, String>? pathologies,
  })  : antecedents = antecedents ?? {for (final t in TypeAntecedent.values) t: ReponseAntecedent()},
        examens = examens ?? {for (final a in AppareilExamen.values) a: ReponseExamen()},
        pathologies = pathologies ?? {};

  /// IMC calculé, ou `null` si le poids ou la taille manque.
  double? get imc {
    final p = poidsKg, t = tailleCm;
    if (p == null || t == null || p <= 0 || t <= 0) return null;
    return calculerImc(poidsKg: p, tailleCm: t);
  }

  InterpretationImc? interpretationImc({required Sexe sexe, required DateTime? dateNaissance, TableImcOms? table}) {
    final v = imc;
    if (v == null || dateNaissance == null || dateNaissance.isAfter(dateVisite)) return null;
    return interpreterImc(imc: v, sexe: sexe, age: calculerAge(dateNaissance, dateVisite), table: table);
  }

  bool get modifiable => statut == StatutVisite.ebauche || statut == StatutVisite.enregistre;

  /// Données de la table `visite` (colonnes métier).
  Map<String, Object?> donneesVisite({InterpretationImc? interpretation, String? validateurId, DateTime? valideLe}) => {
        'eleve_id': eleveId,
        'inscription_id': inscriptionId,
        'agent_id': agentId,
        'appareil_id': appareilId,
        'validateur_id': validateurId,
        'date_visite': formaterDate(dateVisite),
        'structure_origine': _vide(structureOrigine),
        'statut': statut.code,
        'poids_kg': poidsKg,
        'taille_cm': tailleCm,
        'imc': imc,
        'imc_interpretation': interpretation?.categorie.code,
        'ta_sys': taSys,
        'ta_dia': taDia,
        'temperature_c': temperatureC,
        'fc': fc,
        'fr': fr,
        'conclusion': conclusion?.code,
        'diagnostic': _vide(diagnostic),
        'conduite_a_tenir': _vide(conduiteATenir),
        'traitement_conseils': _vide(traitementConseils),
        'structure_reference': _vide(structureReference),
        'date_controle': dateControle == null ? null : formaterDate(dateControle!),
        'observations': _vide(observations),
        'valide_le': valideLe == null ? null : formaterHorodatage(valideLe),
      };

  /// Remplit le formulaire à partir des données d'une visite enregistrée.
  void chargerVisite(Map<String, Object?> d) {
    String s(String k) => (d[k] as String?) ?? '';
    dateVisite = lireDate(d['date_visite']! as String);
    structureOrigine = d['structure_origine'] as String?;
    statut = StatutVisite.depuisCode((d['statut'] as String?) ?? 'ebauche');
    poidsKg = (d['poids_kg'] as num?)?.toDouble();
    tailleCm = (d['taille_cm'] as num?)?.toDouble();
    taSys = (d['ta_sys'] as num?)?.toInt();
    taDia = (d['ta_dia'] as num?)?.toInt();
    temperatureC = (d['temperature_c'] as num?)?.toDouble();
    fc = (d['fc'] as num?)?.toInt();
    fr = (d['fr'] as num?)?.toInt();
    conclusion = d['conclusion'] == null ? null : ConclusionVisite.depuisCode(d['conclusion']! as String);
    diagnostic = s('diagnostic');
    conduiteATenir = s('conduite_a_tenir');
    traitementConseils = s('traitement_conseils');
    structureReference = s('structure_reference');
    dateControle = d['date_controle'] == null ? null : lireDate(d['date_controle']! as String);
    observations = s('observations');
  }

  static String? _vide(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
}

/// La rubrique gynécologique n'est proposée qu'aux filles à partir de 9 ans
/// (ou d'âge inconnu).
bool rubriqueGynecologiqueVisible(Sexe sexe, DateTime? dateNaissance, DateTime dateVisite) {
  if (sexe != Sexe.feminin) return false;
  if (dateNaissance == null || dateNaissance.isAfter(dateVisite)) return true;
  return calculerAge(dateNaissance, dateVisite).annees >= 9;
}

class ControleVisite {
  /// Empêchent la transmission.
  final List<String> erreurs;

  /// Points à vérifier, sans blocage.
  final List<String> avertissements;
  const ControleVisite(this.erreurs, this.avertissements);

  bool get transmissible => erreurs.isEmpty;
}

/// Contrôles avant « Valider et synchroniser ».
/// [pathologiesAPreciser] : identifiants des pathologies dont la précision est
/// obligatoire (« Autres pathologies », « Handicap »).
ControleVisite controlerVisite(FormulaireVisite f, {Set<String> pathologiesAPreciser = const {}, DateTime? aujourdhui}) {
  final erreurs = <String>[];
  final avert = <String>[];
  final jour = aujourdhui ?? DateTime.now().toUtc();
  if (f.dateVisite.isAfter(jour.add(const Duration(days: 1)))) erreurs.add('La date de la visite est dans le futur.');
  if (f.conclusion == null) erreurs.add('Choisir la conclusion de la visite.');
  if (f.conclusion == ConclusionVisite.reference && f.structureReference.trim().isEmpty) {
    erreurs.add('Indiquer la structure de référence.');
  }
  if ((f.conclusion == ConclusionVisite.anomalie ||
          f.conclusion == ConclusionVisite.suivi ||
          f.conclusion == ConclusionVisite.reference) &&
      f.diagnostic.trim().isEmpty) {
    erreurs.add('Indiquer le diagnostic ou le problème identifié.');
  }
  if (f.conclusion == ConclusionVisite.suivi && f.dateControle == null) {
    avert.add('Aucune date de rendez-vous de contrôle pour un élève à suivre.');
  }
  for (final id in f.pathologies.keys) {
    if (pathologiesAPreciser.contains(id) && f.pathologies[id]!.trim().isEmpty) {
      erreurs.add('Préciser la pathologie « autre » ou le handicap dépisté.');
    }
  }
  if (f.conclusion == ConclusionVisite.sansAnomalie && f.pathologies.isNotEmpty) {
    avert.add('Des pathologies sont cochées alors que la conclusion est « sans anomalie ».');
  }
  for (final e in f.examens.entries) {
    if (e.value.resultat == ResultatExamen.anormal && e.value.observation.trim().isEmpty) {
      avert.add('${e.key.libelle} anormal sans observation.');
    }
  }
  if (f.examens.values.every((e) => e.resultat == ResultatExamen.nonExamine)) {
    avert.add('Aucun examen par appareil n\'a été renseigné.');
  }
  if (f.poidsKg == null || f.tailleCm == null) avert.add('Poids ou taille non renseigné : IMC non calculé.');
  for (final a in verifierConstantes(
    poidsKg: f.poidsKg,
    tailleCm: f.tailleCm,
    taSys: f.taSys,
    taDia: f.taDia,
    temperatureC: f.temperatureC,
    fc: f.fc,
    fr: f.fr,
  )) {
    avert.add('Constante à vérifier : $a');
  }
  return ControleVisite(erreurs, avert);
}

/// Libellé du statut affiché, qui combine le statut de la visite et son état
/// de synchronisation sur le téléphone.
String statutAffiche(StatutVisite statut, EtatSync etat) {
  if (etat == EtatSync.conflit) return 'À vérifier (conflit)';
  switch (statut) {
    case StatutVisite.ebauche:
      return 'Ébauche';
    case StatutVisite.enregistre:
      return 'Enregistré localement';
    case StatutVisite.valide:
      return 'Validé';
    case StatutVisite.enAttente:
    case StatutVisite.synchronise:
      return etat == EtatSync.synchronise ? 'Synchronisé' : 'En attente de synchronisation';
  }
}
