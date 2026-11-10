/// Formulaire d'inspection sanitaire d'un établissement (section 11) :
/// réponse à chaque critère actif de la grille, observations,
/// recommandations, inspecteur, date et signature tracée à l'écran.
///
/// Indépendant du stockage, comme le formulaire de visite : le téléphone le
/// charge depuis sa base et l'y enregistre (`inspection`,
/// `inspection_reponse`, `inspection_photo`) ; le poste central l'utilise
/// pour ses rapports.
library;

import 'dart:convert';

import '../commun/commun.dart';
import '../modeles/enums.dart';
import '../regles/inspection.dart';

/// Critère de la grille (table `critere_inspection`).
class CritereGrille {
  final String id;
  final RubriqueInspection rubrique;
  final String code;
  final String libelle;
  final int ordre;
  final bool actif;

  const CritereGrille({
    required this.id,
    required this.rubrique,
    required this.code,
    required this.libelle,
    this.ordre = 0,
    this.actif = true,
  });

  factory CritereGrille.depuisDonnees(String id, Map<String, Object?> d) => CritereGrille(
        id: id,
        rubrique: RubriqueInspection.depuisCode(d['rubrique']! as String),
        code: d['code']! as String,
        libelle: d['libelle']! as String,
        ordre: (d['ordre'] as num?)?.toInt() ?? 0,
        actif: d['actif'] != false && d['actif'] != 0,
      );
}

/// Critères classés par rubrique (ordre des rubriques du prompt, puis ordre du critère).
Map<RubriqueInspection, List<CritereGrille>> grilleParRubrique(Iterable<CritereGrille> criteres) {
  final r = <RubriqueInspection, List<CritereGrille>>{};
  for (final rub in RubriqueInspection.values) {
    final l = criteres.where((c) => c.rubrique == rub).toList()
      ..sort((a, b) => a.ordre != b.ordre ? a.ordre.compareTo(b.ordre) : a.libelle.compareTo(b.libelle));
    if (l.isNotEmpty) r[rub] = l;
  }
  return r;
}

/// Seuils du niveau global (paramètres `seuil_conformite_satisfaisant` et
/// `seuil_conformite_moyen`, 80 et 50 par défaut).
class SeuilsConformite {
  final double satisfaisant;
  final double moyen;
  const SeuilsConformite({this.satisfaisant = 80, this.moyen = 50});

  factory SeuilsConformite.depuisParametres(Map<String, String?> p) {
    double lire(String cle, double defaut) => double.tryParse((p[cle] ?? '').replaceAll(',', '.')) ?? defaut;
    final s = SeuilsConformite(
        satisfaisant: lire('seuil_conformite_satisfaisant', 80), moyen: lire('seuil_conformite_moyen', 50));
    return s.moyen > s.satisfaisant ? const SeuilsConformite() : s;
  }
}

class ReponseCritere {
  ResultatInspection? resultat;
  String observation;
  ReponseCritere({this.resultat, this.observation = ''});
}

class FormulaireInspection {
  /// Identifiant de l'inspection (créé à la première sauvegarde).
  String? id;
  final String etablissementId;
  final String anneeScolaireId;
  final String inspecteurId;
  DateTime dateInspection;
  String observations;
  String recommandations;

  /// Signature tracée à l'écran (image PNG).
  List<int>? signaturePng;
  StatutInspection statut;

  /// Critères de la grille au moment de l'inspection : critères actifs, plus
  /// ceux, désactivés depuis, auxquels l'inspection a déjà répondu.
  final List<CritereGrille> criteres;

  /// Réponses par identifiant de critère.
  final Map<String, ReponseCritere> reponses;

  FormulaireInspection({
    this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    required this.inspecteurId,
    required this.dateInspection,
    required Iterable<CritereGrille> criteres,
    this.observations = '',
    this.recommandations = '',
    this.signaturePng,
    this.statut = StatutInspection.ebauche,
  })  : criteres = criteres.toList(),
        reponses = {for (final c in criteres) c.id: ReponseCritere()};

  bool get modifiable => statut == StatutInspection.ebauche;

  Map<RubriqueInspection, List<CritereGrille>> get parRubrique => grilleParRubrique(criteres);

  int get nombreRepondus => reponses.values.where((r) => r.resultat != null).length;

  ResultatConformite resultat([SeuilsConformite seuils = const SeuilsConformite()]) => calculerConformite(
        [for (final r in reponses.values) if (r.resultat != null) r.resultat!],
        seuilSatisfaisant: seuils.satisfaisant,
        seuilMoyen: seuils.moyen,
      );

  /// Critères non conformes ou partiellement conformes (insuffisances).
  List<CritereGrille> get insuffisances => [
        for (final c in criteres)
          if (reponses[c.id]?.resultat == ResultatInspection.nonConforme ||
              reponses[c.id]?.resultat == ResultatInspection.partiel)
            c
      ];

  /// Données de la table `inspection`, compteurs et taux recalculés.
  Map<String, Object?> donneesInspection([SeuilsConformite seuils = const SeuilsConformite()]) {
    final r = resultat(seuils);
    String? texte(String s) => s.trim().isEmpty ? null : s.trim();
    return {
      'etablissement_id': etablissementId,
      'annee_scolaire_id': anneeScolaireId,
      'inspecteur_id': inspecteurId,
      'date_inspection': formaterDate(dateInspection),
      'observations': texte(observations),
      'recommandations': texte(recommandations),
      'signature': signaturePng == null ? null : base64.encode(signaturePng!),
      'nb_conformes': r.conformes,
      'nb_partiels': r.partiels,
      'nb_non_conformes': r.nonConformes,
      'nb_non_applicables': r.nonApplicables,
      'taux_conformite': r.taux,
      'niveau': r.niveau?.code,
      'statut': statut.code,
    };
  }

  /// Données d'une ligne `inspection_reponse` (null si le critère est sans réponse).
  Map<String, Object?>? donneesReponse(String critereId) {
    final r = reponses[critereId];
    if (r == null || r.resultat == null) return null;
    return {
      'inspection_id': id,
      'critere_id': critereId,
      'resultat': r.resultat!.code,
      'observation': r.observation.trim().isEmpty ? null : r.observation.trim(),
    };
  }

  void chargerInspection(Map<String, Object?> d) {
    dateInspection = lireDate(d['date_inspection']! as String);
    observations = (d['observations'] as String?) ?? '';
    recommandations = (d['recommandations'] as String?) ?? '';
    final sig = d['signature'] as String?;
    signaturePng = sig == null ? null : base64.decode(sig);
    statut = StatutInspection.depuisCode((d['statut'] as String?) ?? 'ebauche');
  }

  /// Charge une réponse enregistrée. Un critère désactivé depuis est ajouté à
  /// la grille de cette inspection si [critere] est fourni.
  void chargerReponse(Map<String, Object?> d, {CritereGrille? critere}) {
    final id = d['critere_id']! as String;
    if (!reponses.containsKey(id)) {
      if (critere == null) return;
      criteres.add(critere);
    }
    reponses[id] = ReponseCritere(
      resultat: ResultatInspection.depuisCode(d['resultat']! as String),
      observation: (d['observation'] as String?) ?? '',
    );
  }
}

class ControleInspection {
  final List<String> erreurs;
  final List<String> avertissements;
  const ControleInspection(this.erreurs, this.avertissements);
  bool get transmissible => erreurs.isEmpty;
}

/// Contrôles avant « Enregistrer et transmettre ».
ControleInspection controlerInspection(FormulaireInspection f, {DateTime? aujourdhui}) {
  final erreurs = <String>[];
  final avert = <String>[];
  final jour = aujourdhui ?? DateTime.now().toUtc();
  if (f.dateInspection.isAfter(jour.add(const Duration(days: 1)))) {
    erreurs.add('La date de l\'inspection est dans le futur.');
  }
  final sansReponse = f.criteres.where((c) => f.reponses[c.id]?.resultat == null).length;
  if (sansReponse > 0) {
    erreurs.add(sansReponse == 1
        ? 'Un critère est sans réponse (choisir « Non applicable » s\'il ne concerne pas l\'établissement).'
        : '$sansReponse critères sont sans réponse (choisir « Non applicable » s\'ils ne concernent pas l\'établissement).');
  }
  if (f.signaturePng == null || f.signaturePng!.isEmpty) erreurs.add('L\'inspecteur doit signer à l\'écran.');
  if (f.criteres.isNotEmpty && f.resultat().evalues == 0 && sansReponse == 0) {
    avert.add('Tous les critères sont « non applicable » : aucun taux de conformité ne sera calculé.');
  }
  for (final c in f.insuffisances) {
    if (f.reponses[c.id]!.observation.trim().isEmpty) avert.add('« ${c.libelle} » : insuffisance sans observation.');
  }
  if (f.insuffisances.isNotEmpty && f.recommandations.trim().isEmpty) {
    avert.add('Des insuffisances sont constatées sans recommandation.');
  }
  return ControleInspection(erreurs, avert);
}
