/// GRILLE D'INSPECTION SANITAIRE DES ÉTABLISSEMENTS SCOLAIRES du SSSU-SAJ de
/// Kouassi-Kouassikro (normes MENA 2022 pour le préscolaire et le primaire,
/// normes OMS pour le secondaire).
///
/// - Sections B à J : 118 critères cotés C (1 point), NC (0) ou NA (exclu),
///   dont 7 critères critiques ★ ([_criteresGrille], table `critere_inspection`).
/// - Identification de la visite, section A (structure, effectifs,
///   équipements, ratios), types de source et de latrines, constats et plan
///   d'action : [DonneesGrille], enregistrées en JSON dans `inspection.grille`.
/// - Score d'un domaine = points ÷ critères applicables × 100 ; score global
///   sur l'ensemble des critères applicables ; classement Satisfaisant (≥ 80 %),
///   Acceptable (60–79 %), Insuffisant (40–59 %), Critique (< 40 %) ; un seul NC
///   sur un critère ★ plafonne le classement à « Insuffisant » ([EvaluationGrille]).
library;

import '../modeles/enums.dart';

part 'grille_criteres.dart';

/// Critère de la grille nationale (identifiant fixe, commun au poste et aux
/// téléphones).
class DefinitionCritere {
  final String id;
  final String code;
  final RubriqueInspection rubrique;
  final int ordre;
  final String libelle;

  /// Critère critique ★.
  final bool critique;

  /// Sous-titre de regroupement dans la section (« Disponibilité et séparation »…).
  final String? groupe;
  const DefinitionCritere(this.id, this.code, this.rubrique, this.ordre, this.libelle,
      {this.critique = false, this.groupe});
}

/// Les 118 critères, dans l'ordre de la grille.
const List<DefinitionCritere> criteresGrille = _criteresGrille;

final Map<String, DefinitionCritere> _parCode = {for (final c in _criteresGrille) c.code: c};
final Map<String, DefinitionCritere> _parId = {for (final c in _criteresGrille) c.id: c};

DefinitionCritere? definitionParCode(String code) => _parCode[code];
DefinitionCritere? definitionParId(String id) => _parId[id];

/// Consignes propres à une section, reprises de la grille.
const Map<RubriqueInspection, String> consignesSections = {
  RubriqueInspection.hygieneMenstruelle:
      'Coter NA toute la section pour le préscolaire et les établissements sans filles ; au primaire, elle concerne les filles du CM.',
  RubriqueInspection.sallesClasse:
      'Inspecter au moins 3 classes de niveaux différents ; un critère est NC dès qu\'une classe visitée n\'est pas conforme.',
  RubriqueInspection.cantineVente: 'Coter NA les critères H1 à H10 si l\'établissement n\'a pas de cantine.',
};

const consignesRemplissage = [
  'Chaque critère se vérifie par observation directe le jour de la visite ; une déclaration non vérifiable est cotée NC.',
  'Cotation : une seule réponse par critère. C = conforme (1 point) ; NC = non conforme (0 point) ; NA = non applicable '
      '(exclu du calcul, justifier en observation).',
  'Critères critiques (★) : un seul NC sur un critère ★ plafonne le classement de l\'établissement à « Insuffisant », quel '
      'que soit le score, et appelle une mesure corrective immédiate.',
  'Score d\'un domaine = points obtenus ÷ (nombre de critères – nombre de NA) × 100.',
  'Observations : noter les chiffres utiles (ex. « 3 cabines filles sur 5 fonctionnelles ») et la localisation du problème.',
  'Entretiens : interroger au moins 2 filles et 2 garçons (CM ou secondaire) sur l\'usage des latrines, du savon et '
      'l\'hygiène menstruelle, hors présence des enseignants.',
  'Références : normes MENA 2022 pour le préscolaire et le primaire ; normes OMS pour le secondaire.',
];

const ampliationGrille =
    'Ampliation : établissement inspecté ; DRENA / IEPP ; Direction départementale de la santé ; archives du SSSU-SAJ.';
const referencesGrille =
    'Références : Normes et standards nationaux pour l\'eau, l\'hygiène et l\'assainissement dans les écoles préscolaires et '
    'primaires (MENA, Direction de la Vie Scolaire, mars 2022) ; normes OMS d\'eau, d\'assainissement et d\'hygiène en milieu scolaire.';

// ------------------------------------------------------------------ choix

/// Choix à une seule réponse de la grille (cases ☐).
class Choix {
  final String code;
  final String libelle;
  const Choix(this.code, this.libelle);
}

String? libelleChoix(List<Choix> liste, String? code) {
  for (final c in liste) {
    if (c.code == code) return c.libelle;
  }
  return null;
}

const typesVisite = [Choix('programmee', 'Programmée'), Choix('inopinee', 'Inopinée'), Choix('contre_visite', 'Contre-visite')];
const ordresEnseignement = [
  Choix('prescolaire', 'Préscolaire'),
  Choix('primaire', 'Primaire'),
  Choix('secondaire_general', 'Secondaire général'),
  Choix('technique', 'Technique / professionnel'),
];
const statutsGrille = [
  Choix('public', 'Public'),
  Choix('prive_laic', 'Privé laïc'),
  Choix('prive_confessionnel', 'Privé confessionnel'),
  Choix('communautaire', 'Communautaire'),
];
const frequentations = [Choix('mixte', 'Mixte'), Choix('filles', 'Filles uniquement'), Choix('garcons', 'Garçons uniquement')];
const regimes = [Choix('externat', 'Externat'), Choix('demi_pension', 'Demi-pension'), Choix('internat', 'Internat')];
const milieux = [Choix('urbain', 'Urbain'), Choix('rural', 'Rural')];
const electricites = [Choix('reseau', 'Réseau'), Choix('solaire', 'Solaire'), Choix('aucune', 'Aucune')];
const sourcesEau = [
  Choix('reseau', 'Réseau (robinet)'),
  Choix('forage', 'Forage équipé'),
  Choix('puits_protege', 'Puits protégé'),
  Choix('citerne', 'Citerne d\'eau de pluie'),
  Choix('puits_non_protege', 'Puits non protégé'),
  Choix('eau_surface', 'Eau de surface'),
  Choix('apportee', 'Eau apportée par les élèves'),
];
const sourcesAmeliorees = {'reseau', 'forage', 'puits_protege', 'citerne'};
const typesLatrines = [
  Choix('wc', 'WC à chasse raccordé (fosse septique ou réseau)'),
  Choix('vip', 'Latrine ventilée (VIP)'),
  Choix('fosse_dalle', 'Latrine à fosse avec dalle'),
  Choix('fosse_sans_dalle', 'Fosse sans dalle'),
  Choix('aucune', 'Aucune installation'),
];
const latrinesAmeliorees = {'wc', 'vip', 'fosse_dalle'};

/// Lignes du tableau des effectifs (garçons / hommes, filles / femmes).
const categoriesEffectifs = [
  Choix('eleves', 'Élèves'),
  Choix('eleves_handicap', 'Élèves en situation de handicap'),
  Choix('enseignants', 'Enseignants'),
  Choix('personnel_admin', 'Personnel administratif et d\'appui'),
  Choix('personnel_cantine', 'Personnel de cantine / vendeuses'),
];

/// Inventaire des équipements (existant / fonctionnel) et norme de référence.
class Equipement {
  final String code;
  final String libelle;
  final String norme;

  /// Sans colonne « fonctionnel » (salles de classe utilisées).
  final bool sansFonctionnel;
  const Equipement(this.code, this.libelle, this.norme, {this.sansFonctionnel = false});
}

const equipementsGrille = [
  Equipement('salles', 'Salles de classe utilisées', '—', sansFonctionnel: true),
  Equipement('places', 'Places assises (tables-bancs × places)', '1 place par élève'),
  Equipement('cabines_filles', 'Cabines latrines filles',
      'Primaire : 1 pour 2 classes (MENA) ; secondaire : 1 pour 25 filles (OMS)'),
  Equipement('cabines_garcons', 'Cabines latrines garçons',
      'Primaire : 1 pour 2 classes (MENA) ; secondaire : 1 pour 50 garçons (OMS)'),
  Equipement('urinoirs', 'Urinoirs garçons (ou mètres de rigole)',
      'Primaire : 1 urinoir ou 1 m par classe (MENA) ; secondaire : 1 pour 50 garçons (OMS)'),
  Equipement('cabines_personnel', 'Cabines personnel (hommes / femmes)', 'Au moins 1 hommes + 1 femmes'),
  Equipement('cabines_pmr', 'Cabines adaptées aux personnes à mobilité réduite', '1 côté filles + 1 côté garçons (MENA)'),
  Equipement('points_eau', 'Points d\'eau de boisson', 'Primaire : 1 par classe ; préscolaire : 2 pour 3 classes (MENA)'),
  Equipement('dlm', 'Dispositifs de lavage des mains (DLM)', '1 par classe (MENA)'),
  Equipement('poubelles', 'Poubelles', '1 par classe + poubelles dans la cour (MENA)'),
];

// ------------------------------------------------------------- données

/// Deux nombres saisis (garçons / filles, ou existant / fonctionnel).
class Paire {
  int? a;
  int? b;
  Paire([this.a, this.b]);
  int? get total => a == null && b == null ? null : (a ?? 0) + (b ?? 0);
  List<int?> versJson() => [a, b];
  factory Paire.depuisJson(Object? j) {
    final l = j is List ? j : const [];
    int? n(int i) => i < l.length && l[i] is num ? (l[i] as num).toInt() : null;
    return Paire(n(0), n(1));
  }
}

/// Problème prioritaire du plan d'action.
class ProblemeConstate {
  String probleme;

  /// Numéro(s) du critère concerné (« C4, C11 »).
  String criteres;
  String mesure;
  String responsable;
  String delai;

  /// Réalisé à la contre-visite (oui / non), inconnu avant.
  bool? realise;
  ProblemeConstate({
    this.probleme = '',
    this.criteres = '',
    this.mesure = '',
    this.responsable = '',
    this.delai = '',
    this.realise,
  });

  bool get vide => [probleme, criteres, mesure, responsable, delai].every((s) => s.trim().isEmpty);

  Map<String, Object?> versJson() => {
        'probleme': probleme,
        'criteres': criteres,
        'mesure': mesure,
        'responsable': responsable,
        'delai': delai,
        'realise': realise,
      };
  factory ProblemeConstate.depuisJson(Map<String, Object?> j) => ProblemeConstate(
        probleme: (j['probleme'] as String?) ?? '',
        criteres: (j['criteres'] as String?) ?? '',
        mesure: (j['mesure'] as String?) ?? '',
        responsable: (j['responsable'] as String?) ?? '',
        delai: (j['delai'] as String?) ?? '',
        realise: j['realise'] as bool?,
      );
}

/// Niveau de service eau, assainissement et hygiène (définitions OMS/UNICEF).
enum NiveauService {
  elementaire('elementaire', 'Élémentaire'),
  limite('limite', 'Limité'),
  absence('absence', 'Absence de service');

  final String code;
  final String libelle;
  const NiveauService(this.code, this.libelle);
  static NiveauService? depuisCode(String? c) {
    for (final v in values) {
      if (v.code == c) return v;
    }
    return null;
  }
}

/// Domaines du niveau de service, avec la définition de chaque niveau.
enum DomaineService {
  eau('eau', 'Eau de boisson', [
    'Point d\'eau amélioré avec eau disponible',
    'Point d\'eau amélioré sans eau ce jour',
    'Source non améliorée ou aucun point d\'eau'
  ]),
  assainissement('assainissement', 'Assainissement', [
    'Latrines améliorées, non mixtes et utilisables',
    'Latrines améliorées mais mixtes ou inutilisables',
    'Latrines non améliorées ou absentes'
  ]),
  hygiene('hygiene', 'Hygiène des mains', ['DLM avec eau et savon', 'DLM avec eau sans savon', 'Ni DLM ni eau']);

  final String code;
  final String libelle;

  /// Définition des niveaux élémentaire, limité, absence de service.
  final List<String> definitions;
  const DomaineService(this.code, this.libelle, this.definitions);
}

/// Tout ce que la grille contient en plus des cotations des critères.
class DonneesGrille {
  // Identification de la visite
  String ficheNumero = '';
  String drenaIepp = '';
  String localite = '';
  String aireSanitaire = '';
  String chefEtablissement = '';
  String accompagnateur = '';
  String heureArrivee = '';
  String heureDepart = '';
  String? typeVisite;
  DateTime? dateDerniereInspection;
  String equipe = '';

  // A. Structure et effectifs (non coté)
  String? ordreEnseignement;
  String? statut;
  String? frequentation;
  String? regime;
  String? milieu;
  String? electricite;
  bool? cantine;
  final Map<String, Paire> effectifs = {for (final c in categoriesEffectifs) c.code: Paire()};
  final Map<String, Paire> equipements = {for (final e in equipementsGrille) e.code: Paire()};

  // Précisions des sections
  String? sourceEau;
  String? typeLatrine;
  String classesVisitees = '';
  int? nbCuisinieres;
  int? nbVendeuses;
  String dateJourneeSalubrite = '';

  /// Niveaux de service choisis par l'inspecteur (sinon : proposition calculée).
  final Map<DomaineService, NiveauService?> niveauxService = {for (final d in DomaineService.values) d: null};

  // Constats, recommandations et signatures
  String pointsForts = '';
  final List<ProblemeConstate> problemes = [];
  DateTime? dateContreVisite;
  String chefEquipe = '';

  DonneesGrille();

  /// Grille préremplie avec ce que l'application sait déjà : fiche de
  /// l'établissement, élèves inscrits (garçons / filles), nombre de classes,
  /// date de la dernière inspection. Tout reste modifiable par l'inspecteur.
  factory DonneesGrille.preremplie({
    Map<String, Object?>? etablissement,
    int? garcons,
    int? filles,
    int? classes,
    DateTime? derniereInspection,
  }) {
    final g = DonneesGrille()
      ..typeVisite = 'programmee'
      ..dateDerniereInspection = derniereInspection;
    final e = etablissement;
    if (e != null) {
      g.localite = (e['localite'] as String?) ?? '';
      final resp = (e['responsable'] as String?)?.trim() ?? '';
      final tel = (e['telephone'] as String?)?.trim() ?? '';
      g.chefEtablissement = [resp, tel].where((x) => x.isNotEmpty).join(', ');
      g.ordreEnseignement = switch (e['type']) {
        'prescolaire' => 'prescolaire',
        'primaire' => 'primaire',
        'secondaire' => 'secondaire_general',
        'technique' => 'technique',
        _ => null,
      };
      g.statut = e['statut'] == 'public' ? 'public' : null;
    }
    if (garcons != null || filles != null) g.effectifs['eleves'] = Paire(garcons, filles);
    if (classes != null && classes > 0) g.equipements['salles'] = Paire(classes);
    if (garcons != null && filles != null && garcons + filles > 0) {
      g.frequentation = filles == 0 ? 'garcons' : garcons == 0 ? 'filles' : 'mixte';
    }
    return g;
  }

  Map<String, Object?> versJson() {
    String? d(DateTime? x) => x == null
        ? null
        : '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    return {
      'version': 1,
      'fiche_numero': ficheNumero,
      'drena_iepp': drenaIepp,
      'localite': localite,
      'aire_sanitaire': aireSanitaire,
      'chef_etablissement': chefEtablissement,
      'accompagnateur': accompagnateur,
      'heure_arrivee': heureArrivee,
      'heure_depart': heureDepart,
      'type_visite': typeVisite,
      'date_derniere_inspection': d(dateDerniereInspection),
      'equipe': equipe,
      'ordre_enseignement': ordreEnseignement,
      'statut': statut,
      'frequentation': frequentation,
      'regime': regime,
      'milieu': milieu,
      'electricite': electricite,
      'cantine': cantine,
      'effectifs': {for (final e in effectifs.entries) e.key: e.value.versJson()},
      'equipements': {for (final e in equipements.entries) e.key: e.value.versJson()},
      'source_eau': sourceEau,
      'type_latrine': typeLatrine,
      'classes_visitees': classesVisitees,
      'nb_cuisinieres': nbCuisinieres,
      'nb_vendeuses': nbVendeuses,
      'date_journee_salubrite': dateJourneeSalubrite,
      'niveaux_service': {for (final e in niveauxService.entries) e.key.code: e.value?.code},
      'points_forts': pointsForts,
      'problemes': [for (final p in problemes) if (!p.vide) p.versJson()],
      'date_contre_visite': d(dateContreVisite),
      'chef_equipe': chefEquipe,
    };
  }

  factory DonneesGrille.depuisJson(Map<String, Object?> j) {
    String s(String k) => (j[k] as String?) ?? '';
    DateTime? d(String k) {
      final v = j[k];
      if (v is! String || v.isEmpty) return null;
      final x = DateTime.tryParse(v);
      return x == null ? null : DateTime.utc(x.year, x.month, x.day);
    }

    int? n(String k) => j[k] is num ? (j[k]! as num).toInt() : null;
    final g = DonneesGrille()
      ..ficheNumero = s('fiche_numero')
      ..drenaIepp = s('drena_iepp')
      ..localite = s('localite')
      ..aireSanitaire = s('aire_sanitaire')
      ..chefEtablissement = s('chef_etablissement')
      ..accompagnateur = s('accompagnateur')
      ..heureArrivee = s('heure_arrivee')
      ..heureDepart = s('heure_depart')
      ..typeVisite = j['type_visite'] as String?
      ..dateDerniereInspection = d('date_derniere_inspection')
      ..equipe = s('equipe')
      ..ordreEnseignement = j['ordre_enseignement'] as String?
      ..statut = j['statut'] as String?
      ..frequentation = j['frequentation'] as String?
      ..regime = j['regime'] as String?
      ..milieu = j['milieu'] as String?
      ..electricite = j['electricite'] as String?
      ..cantine = j['cantine'] as bool?
      ..sourceEau = j['source_eau'] as String?
      ..typeLatrine = j['type_latrine'] as String?
      ..classesVisitees = s('classes_visitees')
      ..nbCuisinieres = n('nb_cuisinieres')
      ..nbVendeuses = n('nb_vendeuses')
      ..dateJourneeSalubrite = s('date_journee_salubrite')
      ..pointsForts = s('points_forts')
      ..dateContreVisite = d('date_contre_visite')
      ..chefEquipe = s('chef_equipe');
    final ef = j['effectifs'];
    if (ef is Map) {
      for (final e in ef.entries) {
        g.effectifs[e.key as String] = Paire.depuisJson(e.value);
      }
    }
    final eq = j['equipements'];
    if (eq is Map) {
      for (final e in eq.entries) {
        g.equipements[e.key as String] = Paire.depuisJson(e.value);
      }
    }
    final ns = j['niveaux_service'];
    if (ns is Map) {
      for (final dom in DomaineService.values) {
        g.niveauxService[dom] = NiveauService.depuisCode(ns[dom.code] as String?);
      }
    }
    final pr = j['problemes'];
    if (pr is List) {
      for (final p in pr) {
        if (p is Map) g.problemes.add(ProblemeConstate.depuisJson(p.cast<String, Object?>()));
      }
    }
    return g;
  }

  // ------------------------------------------------------------ ratios

  int? get eleves => effectifs['eleves']?.total;
  int? get garcons => effectifs['eleves']?.a;
  int? get filles => effectifs['eleves']?.b;
  int? get enseignants => effectifs['enseignants']?.total;
  int? get salles => equipements['salles']?.a;

  /// Nombre fonctionnel, à défaut existant.
  int? fonctionnels(String code) => equipements[code]?.b ?? equipements[code]?.a;

  /// Ratios calculés de la section A (valeur `null` si incalculable).
  List<Ratio> get ratios {
    double? div(int? a, int? b) => a == null || b == null || b == 0 ? null : (a / b * 10).roundToDouble() / 10;
    final places = fonctionnels('places');
    return [
      Ratio('Élèves par classe', 'Élèves ÷ salles utilisées', div(eleves, salles),
          'Préscolaire ≤ 25 ; primaire ≤ 50 (MENA)',
          depasse: (v) => v > (ordreEnseignement == 'prescolaire' ? 25 : 50)),
      Ratio('Élèves sans place assise', 'Élèves – places assises',
          eleves == null || places == null ? null : (eleves! > places ? eleves! - places : 0).toDouble(), '0',
          depasse: (v) => v > 0),
      Ratio('Filles par cabine fonctionnelle', 'Filles ÷ cabines filles fonctionnelles',
          div(filles, fonctionnels('cabines_filles')), 'Secondaire ≤ 25',
          depasse: (v) => _secondaire && v > 25),
      Ratio('Garçons par cabine fonctionnelle', 'Garçons ÷ cabines garçons fonctionnelles',
          div(garcons, fonctionnels('cabines_garcons')), 'Secondaire ≤ 50',
          depasse: (v) => _secondaire && v > 50),
      Ratio('Classes par point d\'eau fonctionnel', 'Classes ÷ points d\'eau fonctionnels',
          div(salles, fonctionnels('points_eau')), 'Primaire ≤ 1',
          depasse: (v) => ordreEnseignement == 'primaire' && v > 1),
      Ratio('Classes par DLM fonctionnel', 'Classes ÷ DLM fonctionnels', div(salles, fonctionnels('dlm')), '≤ 1',
          depasse: (v) => v > 1),
      Ratio('Élèves par enseignant', 'Élèves ÷ enseignants', div(eleves, enseignants), 'Selon carte scolaire'),
    ];
  }

  bool get _secondaire => ordreEnseignement == 'secondaire_general' || ordreEnseignement == 'technique';

  /// Critères à coter NA d'après la structure de l'établissement, avec le
  /// motif (consignes de la grille).
  Map<String, String> get nonApplicablesAutomatiques {
    final r = <String, String>{};
    if (ordreEnseignement == 'prescolaire' || frequentation == 'garcons' || (filles == 0 && eleves != null && eleves! > 0)) {
      final motif = ordreEnseignement == 'prescolaire' ? 'Préscolaire' : 'Établissement sans filles';
      for (final c in _criteresGrille) {
        if (c.rubrique == RubriqueInspection.hygieneMenstruelle) r[c.code] = motif;
      }
    }
    if (cantine == false) {
      for (var i = 1; i <= 10; i++) {
        r['H$i'] = 'Pas de cantine';
      }
    }
    if (electricite == 'aucune') r['G8'] = 'Sans électricité';
    return r;
  }
}

class Ratio {
  final String libelle;
  final String calcul;
  final double? valeur;
  final String seuil;
  final bool Function(double)? _depasse;
  const Ratio(this.libelle, this.calcul, this.valeur, this.seuil, {bool Function(double)? depasse}) : _depasse = depasse;

  /// Valeur hors norme.
  bool get horsNorme => valeur != null && (_depasse?.call(valeur!) ?? false);
}

// ----------------------------------------------------------- évaluation

enum ClassementGrille {
  satisfaisant('satisfaisant', 'Satisfaisant', 'vert', 'Féliciter, maintenir ; prochaine inspection dans l\'année'),
  acceptable('acceptable', 'Acceptable', 'jaune', 'Recommandations écrites ; suivi au trimestre suivant'),
  insuffisant('insuffisant', 'Insuffisant', 'orange', 'Plan correctif daté ; contre-visite sous 1 mois'),
  critique('critique', 'Critique', 'rouge',
      'Mesures immédiates ; rapport à la DDS et à la DRENA ; contre-visite sous 15 jours');

  final String code;
  final String libelle;
  final String couleur;
  final String conduite;
  const ClassementGrille(this.code, this.libelle, this.couleur, this.conduite);

  static ClassementGrille depuisScore(double score) => score >= 80
      ? satisfaisant
      : score >= 60
          ? acceptable
          : score >= 40
              ? insuffisant
              : critique;

  /// Niveau enregistré dans `inspection.niveau` (statistiques).
  NiveauConformite get niveau => switch (this) {
        satisfaisant => NiveauConformite.satisfaisant,
        acceptable => NiveauConformite.moyen,
        insuffisant || critique => NiveauConformite.insuffisant,
      };
}

/// Classement d'une inspection enregistrée avec la grille nationale, d'après
/// `inspection.niveau` et `inspection.taux_conformite` (« Critique » est
/// enregistré « insuffisant » avec un score < 40 %).
ClassementGrille? classementEnregistre(String? niveau, double? taux) => switch (niveau) {
      'satisfaisant' => ClassementGrille.satisfaisant,
      'moyen' => ClassementGrille.acceptable,
      'insuffisant' => taux != null && taux < 40 ? ClassementGrille.critique : ClassementGrille.insuffisant,
      _ => null,
    };

/// Barème du score global, repris de la grille (seuil, classement, conduite).
const baremeGrille = [
  ('≥ 80 %', ClassementGrille.satisfaisant),
  ('60 – 79 %', ClassementGrille.acceptable),
  ('40 – 59 %', ClassementGrille.insuffisant),
  ('< 40 %', ClassementGrille.critique),
];

/// Critère coté, pour le calcul (code, rubrique, critique).
class CritereCote {
  final String code;
  final String libelle;
  final RubriqueInspection rubrique;
  final bool critique;
  final ResultatInspection? resultat;
  const CritereCote(this.code, this.libelle, this.rubrique, this.critique, this.resultat);
}

class ScoreDomaine {
  final RubriqueInspection rubrique;
  final int criteres;
  final double points;
  final int applicables;
  final int sansReponse;
  final List<CritereCote> critiquesNonConformes;
  const ScoreDomaine(this.rubrique, this.criteres, this.points, this.applicables, this.sansReponse, this.critiquesNonConformes);

  /// Score en pourcentage (une décimale), `null` sans critère applicable.
  double? get score => applicables == 0 ? null : (points / applicables * 1000).roundToDouble() / 10;
}

class EvaluationGrille {
  final List<ScoreDomaine> domaines;
  const EvaluationGrille(this.domaines);

  int get criteres => domaines.fold(0, (s, d) => s + d.criteres);
  double get points => domaines.fold(0.0, (s, d) => s + d.points);
  int get applicables => domaines.fold(0, (s, d) => s + d.applicables);
  int get sansReponse => domaines.fold(0, (s, d) => s + d.sansReponse);
  List<CritereCote> get critiquesNonConformes => [for (final d in domaines) ...d.critiquesNonConformes];

  double? get scoreGlobal => applicables == 0 ? null : (points / applicables * 1000).roundToDouble() / 10;

  /// Classement d'après le score, plafonné à « Insuffisant » par un critère ★ NC.
  ClassementGrille? get classement {
    final s = scoreGlobal;
    if (s == null) return null;
    final c = ClassementGrille.depuisScore(s);
    return critiquesNonConformes.isNotEmpty && c.index < ClassementGrille.insuffisant.index
        ? ClassementGrille.insuffisant
        : c;
  }

  /// Classement plafonné par un critère critique (le score seul donnerait mieux).
  bool get plafonne {
    final s = scoreGlobal;
    return s != null && critiquesNonConformes.isNotEmpty && ClassementGrille.depuisScore(s).index < ClassementGrille.insuffisant.index;
  }

  static EvaluationGrille calculer(Iterable<CritereCote> criteres) {
    final parRubrique = <RubriqueInspection, List<CritereCote>>{};
    for (final c in criteres) {
      if (c.rubrique.ancienne) continue;
      parRubrique.putIfAbsent(c.rubrique, () => []).add(c);
    }
    return EvaluationGrille([
      for (final r in RubriqueInspection.actuelles)
        if (parRubrique[r] case final l?)
          ScoreDomaine(
            r,
            l.length,
            l.fold(0.0, (s, c) => s + (c.resultat == ResultatInspection.conforme ? 1 : c.resultat == ResultatInspection.partiel ? 0.5 : 0)),
            l.where((c) => c.resultat != null && c.resultat != ResultatInspection.nonApplicable).length,
            l.where((c) => c.resultat == null).length,
            [for (final c in l) if (c.critique && c.resultat == ResultatInspection.nonConforme) c],
          )
    ]);
  }
}

/// Niveau de service proposé d'après les cotations (B1–B3, C1–C2, D1–D5) et
/// les types de source et de latrines ; `null` si les éléments manquent.
NiveauService? niveauServicePropose(DomaineService d, Map<String, ResultatInspection?> r, DonneesGrille g) {
  bool c(String code) => r[code] == ResultatInspection.conforme;
  bool nc(String code) => r[code] == ResultatInspection.nonConforme;
  switch (d) {
    case DomaineService.eau:
      if (nc('B1') || nc('B2') || (g.sourceEau != null && !sourcesAmeliorees.contains(g.sourceEau))) {
        return NiveauService.absence;
      }
      if (c('B1') && c('B2')) {
        if (c('B3')) return NiveauService.elementaire;
        if (nc('B3')) return NiveauService.limite;
      }
      return null;
    case DomaineService.assainissement:
      if (g.typeLatrine != null && !latrinesAmeliorees.contains(g.typeLatrine)) return NiveauService.absence;
      if (c('C1') && c('C2')) return NiveauService.elementaire;
      if (nc('C1') || nc('C2')) return g.typeLatrine == null ? null : NiveauService.limite;
      return null;
    case DomaineService.hygiene:
      if (c('D1')) return NiveauService.elementaire;
      if (nc('D1')) {
        final dlm = g.fonctionnels('dlm');
        if (dlm == 0) return NiveauService.absence;
        if (nc('D5') && (dlm ?? 0) > 0) return NiveauService.limite;
      }
      return null;
  }
}
