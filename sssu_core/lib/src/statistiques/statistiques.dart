/// Calcul des indicateurs (sections 4 et 12 du prompt).
///
/// Le calcul est fait en mémoire à partir d'un [JeuStatistiques], construit
/// par le poste central (PostgreSQL, toutes les données) ou par le téléphone
/// (SQLite, données de l'appareil). Les deux versions affichent donc des
/// indicateurs calculés de la même façon.
///
/// Définitions :
/// - effectif : élèves inscrits (statut « inscrit ») dans une classe de l'année ;
/// - élève examiné : élève de l'effectif ayant au moins une visite autre
///   qu'une ébauche entre le début et la fin de l'année scolaire (et dans la
///   période choisie, si elle est filtrée) ;
/// - taux de couverture : examinés / effectif × 100 ;
/// - cas d'une pathologie : élèves examinés chez qui elle a été dépistée lors
///   d'au moins une de ces visites ; prévalence : cas / examinés × 100 ;
/// - conclusion, tranche d'âge : celles de la dernière visite de l'élève ;
/// - inspections : la dernière inspection (non ébauche) de chaque
///   établissement sur l'année ou la période.
library;

import '../commun/commun.dart';
import '../modeles/enums.dart';
import '../regles/age.dart';

// ------------------------------------------------------------- données d'entrée

class AnneeStat {
  final String id;
  final String libelle;
  final DateTime debut;
  final DateTime fin;
  const AnneeStat(this.id, this.libelle, this.debut, this.fin);
}

class ClasseStat {
  final String id;
  final String libelle;
  final String? niveau;
  final String etablissementId;
  const ClasseStat(this.id, this.libelle, this.niveau, this.etablissementId);
}

/// Élève inscrit dans une classe de l'année. Les champs d'identité ne sont
/// chargés que pour les listes nominatives.
class EleveStat {
  final String id;
  final Sexe sexe;
  final DateTime? dateNaissance;
  final String classeId;
  final String etablissementId;
  final String? nom;
  final String? prenoms;
  final String? matricule;
  final String? telephoneContact;
  const EleveStat({
    required this.id,
    required this.sexe,
    required this.dateNaissance,
    required this.classeId,
    required this.etablissementId,
    this.nom,
    this.prenoms,
    this.matricule,
    this.telephoneContact,
  });

  String get nomComplet => [nom, prenoms].whereType<String>().join(' ');
}

class VisiteStat {
  final String id;
  final String eleveId;
  final DateTime date;
  final StatutVisite statut;
  final ConclusionVisite? conclusion;
  final Set<String> pathologieIds;

  /// Détails pour les listes des élèves référés et à suivre.
  final String? diagnostic;
  final String? structureReference;
  final DateTime? dateControle;
  const VisiteStat({
    required this.id,
    required this.eleveId,
    required this.date,
    required this.statut,
    this.conclusion,
    this.pathologieIds = const {},
    this.diagnostic,
    this.structureReference,
    this.dateControle,
  });
}

class InspectionStat {
  final String id;
  final String etablissementId;
  final DateTime date;
  final StatutInspection statut;
  final double? taux;
  final NiveauConformite? niveau;
  final int conformes;
  final int partiels;
  final int nonConformes;
  final int nonApplicables;

  /// Résultat par identifiant de critère.
  final Map<String, ResultatInspection> reponses;
  const InspectionStat({
    required this.id,
    required this.etablissementId,
    required this.date,
    required this.statut,
    this.taux,
    this.niveau,
    this.conformes = 0,
    this.partiels = 0,
    this.nonConformes = 0,
    this.nonApplicables = 0,
    this.reponses = const {},
  });
}

class JeuStatistiques {
  final AnneeStat annee;

  /// Établissements (identifiant → nom), dans l'ordre d'affichage.
  final Map<String, String> etablissements;
  final Map<String, ClasseStat> classes;
  final List<EleveStat> eleves;
  final List<VisiteStat> visites;

  /// Pathologies (identifiant → libellé), dans l'ordre de la liste officielle.
  final Map<String, String> pathologies;

  /// Critères d'inspection (identifiant → libellé).
  final Map<String, String> criteres;
  final List<InspectionStat> inspections;

  const JeuStatistiques({
    required this.annee,
    required this.etablissements,
    required this.classes,
    required this.eleves,
    required this.visites,
    required this.pathologies,
    this.criteres = const {},
    this.inspections = const [],
  });

  /// Construction à partir des lignes lues en base (une liste par table,
  /// colonnes du modèle de données). Les dates peuvent être des chaînes
  /// `AAAA-MM-JJ…` ou des `DateTime`.
  ///
  /// - [inscriptions] : lignes de l'année (`eleve_id`, `classe_id`, `statut`) ;
  /// - [eleves] : lignes `eleve` (`id`, `sexe`, `date_naissance`…) ;
  /// - [visitePathologies] : (`visite_id`, `pathologie_id`) ;
  /// - [reponsesInspection] : (`inspection_id`, `critere_id`, `resultat`).
  factory JeuStatistiques.depuisLignes({
    required AnneeStat annee,
    required List<Map<String, Object?>> etablissements,
    required List<Map<String, Object?>> classes,
    required List<Map<String, Object?>> inscriptions,
    required List<Map<String, Object?>> eleves,
    required List<Map<String, Object?>> visites,
    required List<Map<String, Object?>> visitePathologies,
    required List<Map<String, Object?>> pathologies,
    List<Map<String, Object?>> criteres = const [],
    List<Map<String, Object?>> inspections = const [],
    List<Map<String, Object?>> reponsesInspection = const [],
    bool identite = false,
  }) {
    String id(Map<String, Object?> l, [String cle = 'id']) => l[cle].toString();
    final classesParId = {
      for (final c in classes)
        if (_actif(c) && id(c, 'annee_scolaire_id') == annee.id)
          id(c): ClasseStat(id(c), c['libelle']! as String, c['niveau'] as String?, id(c, 'etablissement_id'))
    };
    final elevesParId = {for (final e in eleves) if (_actif(e)) id(e): e};
    final listeEleves = <EleveStat>[];
    final dejaInscrits = <String>{};
    for (final i in inscriptions) {
      if (!_actif(i) || (i['statut'] ?? 'inscrit') != 'inscrit') continue;
      final classe = classesParId[id(i, 'classe_id')];
      final e = elevesParId[id(i, 'eleve_id')];
      if (classe == null || e == null || !dejaInscrits.add(id(e))) continue;
      listeEleves.add(EleveStat(
        id: id(e),
        sexe: Sexe.depuisCode(e['sexe']! as String),
        dateNaissance: _date(e['date_naissance']),
        classeId: classe.id,
        etablissementId: classe.etablissementId,
        nom: identite ? e['nom'] as String? : null,
        prenoms: identite ? e['prenoms'] as String? : null,
        matricule: identite ? e['matricule'] as String? : null,
        telephoneContact: identite ? e['telephone_contact'] as String? : null,
      ));
    }
    final pathosParVisite = <String, Set<String>>{};
    for (final vp in visitePathologies) {
      if (_actif(vp)) (pathosParVisite[id(vp, 'visite_id')] ??= {}).add(id(vp, 'pathologie_id'));
    }
    final listeVisites = [
      for (final v in visites)
        if (_actif(v) && _date(v['date_visite']) != null)
          VisiteStat(
            id: id(v),
            eleveId: id(v, 'eleve_id'),
            date: _date(v['date_visite'])!,
            statut: StatutVisite.depuisCode((v['statut'] as String?) ?? 'ebauche'),
            conclusion: v['conclusion'] == null ? null : ConclusionVisite.depuisCode(v['conclusion']! as String),
            pathologieIds: pathosParVisite[id(v)] ?? const {},
            diagnostic: identite ? v['diagnostic'] as String? : null,
            structureReference: identite ? v['structure_reference'] as String? : null,
            dateControle: identite ? _date(v['date_controle']) : null,
          )
    ];
    final reponsesParInspection = <String, Map<String, ResultatInspection>>{};
    for (final r in reponsesInspection) {
      if (!_actif(r)) continue;
      (reponsesParInspection[id(r, 'inspection_id')] ??= {})[id(r, 'critere_id')] =
          ResultatInspection.depuisCode(r['resultat']! as String);
    }
    final listeInspections = [
      for (final x in inspections)
        if (_actif(x) && _date(x['date_inspection']) != null)
          InspectionStat(
            id: id(x),
            etablissementId: id(x, 'etablissement_id'),
            date: _date(x['date_inspection'])!,
            statut: StatutInspection.depuisCode((x['statut'] as String?) ?? 'ebauche'),
            taux: (x['taux_conformite'] as num?)?.toDouble(),
            niveau: x['niveau'] == null ? null : NiveauConformite.depuisCode(x['niveau']! as String),
            conformes: _entier(x['nb_conformes']),
            partiels: _entier(x['nb_partiels']),
            nonConformes: _entier(x['nb_non_conformes']),
            nonApplicables: _entier(x['nb_non_applicables']),
            reponses: reponsesParInspection[id(x)] ?? const {},
          )
    ];
    final etabs = [for (final e in etablissements) if (_actif(e)) e]
      ..sort((a, b) => (a['nom']! as String).compareTo(b['nom']! as String));
    final pathos = [for (final p in pathologies) if (_actif(p)) p]
      ..sort((a, b) => _entier(a['ordre']).compareTo(_entier(b['ordre'])));
    return JeuStatistiques(
      annee: annee,
      etablissements: {for (final e in etabs) id(e): e['nom']! as String},
      classes: classesParId,
      eleves: listeEleves,
      visites: listeVisites,
      pathologies: {for (final p in pathos) id(p): p['libelle']! as String},
      criteres: {for (final c in criteres) id(c): c['libelle']! as String},
      inspections: listeInspections,
    );
  }
}

bool _actif(Map<String, Object?> l) => l['deleted_at'] == null;

int _entier(Object? v) => v == null ? 0 : (v is num ? v.toInt() : int.parse(v.toString()));

DateTime? _date(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return DateTime.utc(v.year, v.month, v.day);
  final s = v.toString();
  if (s.length < 10) return null;
  return lireDate(s.substring(0, 10));
}

// ------------------------------------------------------------------ filtres

class FiltreStatistiques {
  final String? etablissementId;
  final String? classeId;
  final Sexe? sexe;

  /// Période (bornes incluses), à l'intérieur de l'année scolaire.
  final DateTime? du;
  final DateTime? au;
  const FiltreStatistiques({this.etablissementId, this.classeId, this.sexe, this.du, this.au});

  bool get vide => etablissementId == null && classeId == null && sexe == null && du == null && au == null;
}

// ------------------------------------------------------------------ résultats

/// Tranches d'âge des statistiques (âge à la date de la visite).
enum TrancheAge {
  moins6('< 6 ans', 0, 5),
  de6a9('6–9 ans', 6, 9),
  de10a14('10–14 ans', 10, 14),
  de15a19('15–19 ans', 15, 19),
  de20a24('20–24 ans', 20, 24),
  plus25('25 ans et plus', 25, 200),
  inconnu('Âge inconnu', -1, -1);

  final String libelle;
  final int min;
  final int max;
  const TrancheAge(this.libelle, this.min, this.max);

  static TrancheAge pour(DateTime? naissance, DateTime date) {
    if (naissance == null || naissance.isAfter(date)) return inconnu;
    final a = calculerAge(naissance, date).annees;
    return values.firstWhere((t) => t != inconnu && a >= t.min && a <= t.max);
  }
}

double? taux(int numerateur, int denominateur) =>
    denominateur == 0 ? null : (numerateur / denominateur * 1000).roundToDouble() / 10;

/// Effectif et couverture d'une population (district, établissement, classe).
class Couverture {
  final String? id;
  final String libelle;
  final int effectif;
  final int garcons;
  final int filles;
  final int examines;
  final int garconsExamines;
  final int fillesExamines;
  const Couverture({
    this.id,
    required this.libelle,
    required this.effectif,
    required this.garcons,
    required this.filles,
    required this.examines,
    required this.garconsExamines,
    required this.fillesExamines,
  });

  int get nonExamines => effectif - examines;
  double? get tauxCouverture => taux(examines, effectif);
  double? get tauxGarcons => taux(garconsExamines, garcons);
  double? get tauxFilles => taux(fillesExamines, filles);

  /// Part des garçons et des filles parmi les examinés.
  double? get partGarconsExamines => taux(garconsExamines, examines);
  double? get partFillesExamines => taux(fillesExamines, examines);
}

class LignePathologie {
  final String id;
  final String libelle;
  final int cas;
  final int garcons;
  final int filles;
  final Map<TrancheAge, int> parTranche;

  /// Cas par établissement et par classe (identifiant → nombre).
  final Map<String, int> parEtablissement;
  final Map<String, int> parClasse;

  /// Cas / élèves examinés × 100.
  final double? prevalence;
  const LignePathologie({
    required this.id,
    required this.libelle,
    required this.cas,
    required this.garcons,
    required this.filles,
    required this.parTranche,
    required this.parEtablissement,
    required this.parClasse,
    required this.prevalence,
  });
}

class Insuffisance {
  final String critereId;
  final String libelle;
  final int nonConformes;
  final int partiels;
  const Insuffisance(this.critereId, this.libelle, this.nonConformes, this.partiels);
  int get total => nonConformes + partiels;
}

class SyntheseInspections {
  /// Établissements du périmètre et établissements inspectés.
  final int etablissements;
  final int inspectes;
  final int satisfaisants;
  final int moyens;
  final int insuffisants;
  final double? tauxMoyen;

  /// Insuffisances les plus fréquentes (dernières inspections), par ordre décroissant.
  final List<Insuffisance> principalesInsuffisances;

  /// Dernière inspection de chaque établissement inspecté.
  final Map<String, InspectionStat> dernieres;
  const SyntheseInspections({
    required this.etablissements,
    required this.inspectes,
    required this.satisfaisants,
    required this.moyens,
    required this.insuffisants,
    required this.tauxMoyen,
    required this.principalesInsuffisances,
    required this.dernieres,
  });

  /// Établissements « conformes » : niveau satisfaisant ; « non conformes » : moyen ou insuffisant.
  int get conformes => satisfaisants;
  int get nonConformes => moyens + insuffisants;
}

class PointEvolution {
  /// Mois au format `AAAA-MM`.
  final String mois;
  final int visites;

  /// Élèves examinés pour la première fois de l'année ce mois-là.
  final int nouveauxExamines;

  /// Taux de couverture cumulé à la fin du mois.
  final double? couvertureCumulee;
  const PointEvolution(this.mois, this.visites, this.nouveauxExamines, this.couvertureCumulee);
}

class Statistiques {
  final FiltreStatistiques filtre;
  final int nbEtablissements;
  final int nbClasses;
  final int nbVisites;
  final Couverture generale;
  final List<Couverture> parEtablissement;
  final List<Couverture> parClasse;

  /// Conclusion de la dernière visite des élèves examinés.
  final Map<ConclusionVisite, int> conclusions;
  final List<LignePathologie> pathologies;

  /// Élèves examinés porteurs d'au moins une pathologie.
  final int elevesAvecPathologie;
  final SyntheseInspections inspections;
  final List<PointEvolution> evolution;
  const Statistiques({
    required this.filtre,
    required this.nbEtablissements,
    required this.nbClasses,
    required this.nbVisites,
    required this.generale,
    required this.parEtablissement,
    required this.parClasse,
    required this.conclusions,
    required this.pathologies,
    required this.elevesAvecPathologie,
    required this.inspections,
    required this.evolution,
  });
}

// ------------------------------------------------------------------- calcul

/// Population, visites retenues et dernière visite de chaque élève examiné.
class Perimetre {
  final List<EleveStat> eleves;
  final Map<String, List<VisiteStat>> visitesParEleve;
  final Set<String> etablissements;
  final Set<String> classes;
  final DateTime debut;
  final DateTime fin;
  const Perimetre(this.eleves, this.visitesParEleve, this.etablissements, this.classes, this.debut, this.fin);

  bool examine(String eleveId) => visitesParEleve.containsKey(eleveId);
  VisiteStat? derniere(String eleveId) => visitesParEleve[eleveId]?.last;
}

Perimetre perimetre(JeuStatistiques jeu, FiltreStatistiques f) {
  final debut = f.du != null && f.du!.isAfter(jeu.annee.debut) ? f.du! : jeu.annee.debut;
  final fin = f.au != null && f.au!.isBefore(jeu.annee.fin) ? f.au! : jeu.annee.fin;
  final classes = <String>{
    for (final c in jeu.classes.values)
      if ((f.etablissementId == null || c.etablissementId == f.etablissementId) &&
          (f.classeId == null || c.id == f.classeId))
        c.id
  };
  final etabs = <String>{
    if (f.classeId != null)
      ...{for (final c in classes) jeu.classes[c]!.etablissementId}
    else
      for (final e in jeu.etablissements.keys)
        if (f.etablissementId == null || e == f.etablissementId) e
  };
  final eleves = [
    for (final e in jeu.eleves)
      if (classes.contains(e.classeId) && (f.sexe == null || e.sexe == f.sexe)) e
  ];
  final ids = {for (final e in eleves) e.id};
  final parEleve = <String, List<VisiteStat>>{};
  for (final v in jeu.visites) {
    if (v.statut == StatutVisite.ebauche || !ids.contains(v.eleveId)) continue;
    if (v.date.isBefore(debut) || v.date.isAfter(fin)) continue;
    (parEleve[v.eleveId] ??= []).add(v);
  }
  for (final l in parEleve.values) {
    l.sort((a, b) => a.date.compareTo(b.date));
  }
  return Perimetre(eleves, parEleve, etabs, classes, debut, fin);
}

Couverture _couverture(String? id, String libelle, Iterable<EleveStat> eleves, Perimetre p) {
  var g = 0, fi = 0, ex = 0, gx = 0, fx = 0;
  for (final e in eleves) {
    final m = e.sexe == Sexe.masculin;
    if (m) {
      g++;
    } else {
      fi++;
    }
    if (p.examine(e.id)) {
      ex++;
      if (m) {
        gx++;
      } else {
        fx++;
      }
    }
  }
  return Couverture(
      id: id,
      libelle: libelle,
      effectif: g + fi,
      garcons: g,
      filles: fi,
      examines: ex,
      garconsExamines: gx,
      fillesExamines: fx);
}

Statistiques calculerStatistiques(JeuStatistiques jeu, [FiltreStatistiques f = const FiltreStatistiques()]) {
  final p = perimetre(jeu, f);
  final generale = _couverture(null, 'Ensemble', p.eleves, p);

  final elevesParEtab = <String, List<EleveStat>>{};
  final elevesParClasse = <String, List<EleveStat>>{};
  for (final e in p.eleves) {
    (elevesParEtab[e.etablissementId] ??= []).add(e);
    (elevesParClasse[e.classeId] ??= []).add(e);
  }
  final parEtab = [
    for (final id in jeu.etablissements.keys.where(p.etablissements.contains))
      _couverture(id, jeu.etablissements[id]!, elevesParEtab[id] ?? const [], p)
  ];
  final classesTriees = p.classes.map((c) => jeu.classes[c]!).toList()
    ..sort((a, b) {
      final e = (jeu.etablissements[a.etablissementId] ?? '').compareTo(jeu.etablissements[b.etablissementId] ?? '');
      if (e != 0) return e;
      final n = (a.niveau ?? '').compareTo(b.niveau ?? '');
      return n != 0 ? n : a.libelle.compareTo(b.libelle);
    });
  final plusieursEtabs = p.etablissements.length > 1;
  final parClasse = [
    for (final c in classesTriees)
      _couverture(c.id, plusieursEtabs ? '${jeu.etablissements[c.etablissementId] ?? ''} – ${c.libelle}' : c.libelle,
          elevesParClasse[c.id] ?? const [], p)
  ];

  // Conclusions et pathologies.
  final conclusions = {for (final c in ConclusionVisite.values) c: 0};
  final cas = <String, List<EleveStat>>{};
  final trancheEleve = <String, TrancheAge>{};
  var avecPathologie = 0;
  var nbVisites = 0;
  for (final e in p.eleves) {
    final visites = p.visitesParEleve[e.id];
    if (visites == null) continue;
    nbVisites += visites.length;
    final derniere = visites.last;
    if (derniere.conclusion != null) conclusions[derniere.conclusion!] = conclusions[derniere.conclusion!]! + 1;
    trancheEleve[e.id] = TrancheAge.pour(e.dateNaissance, derniere.date);
    final pathos = {for (final v in visites) ...v.pathologieIds};
    if (pathos.isNotEmpty) avecPathologie++;
    for (final pid in pathos) {
      (cas[pid] ??= []).add(e);
    }
  }
  final pathologies = <LignePathologie>[];
  final ordre = [...jeu.pathologies.keys, ...cas.keys.where((k) => !jeu.pathologies.containsKey(k))];
  for (final pid in ordre) {
    final l = cas[pid] ?? const <EleveStat>[];
    final parTranche = <TrancheAge, int>{};
    final parE = <String, int>{};
    final parC = <String, int>{};
    for (final e in l) {
      parTranche[trancheEleve[e.id]!] = (parTranche[trancheEleve[e.id]!] ?? 0) + 1;
      parE[e.etablissementId] = (parE[e.etablissementId] ?? 0) + 1;
      parC[e.classeId] = (parC[e.classeId] ?? 0) + 1;
    }
    pathologies.add(LignePathologie(
      id: pid,
      libelle: jeu.pathologies[pid] ?? 'Pathologie retirée de la liste',
      cas: l.length,
      garcons: l.where((e) => e.sexe == Sexe.masculin).length,
      filles: l.where((e) => e.sexe == Sexe.feminin).length,
      parTranche: parTranche,
      parEtablissement: parE,
      parClasse: parC,
      prevalence: taux(l.length, generale.examines),
    ));
  }

  // Évolution mensuelle.
  final evolution = <PointEvolution>[];
  if (p.visitesParEleve.isNotEmpty) {
    final visitesParMois = <String, int>{};
    final nouveauxParMois = <String, int>{};
    for (final l in p.visitesParEleve.values) {
      for (final v in l) {
        visitesParMois[_mois(v.date)] = (visitesParMois[_mois(v.date)] ?? 0) + 1;
      }
      nouveauxParMois[_mois(l.first.date)] = (nouveauxParMois[_mois(l.first.date)] ?? 0) + 1;
    }
    var mois = DateTime.utc(p.debut.year, p.debut.month);
    final dernierMois = _dernierMoisAvecDonnees(visitesParMois.keys, p.fin);
    var cumul = 0;
    while (!mois.isAfter(dernierMois)) {
      final m = _mois(mois);
      cumul += nouveauxParMois[m] ?? 0;
      evolution.add(PointEvolution(m, visitesParMois[m] ?? 0, nouveauxParMois[m] ?? 0, taux(cumul, generale.effectif)));
      mois = DateTime.utc(mois.year, mois.month + 1);
    }
  }

  return Statistiques(
    filtre: f,
    nbEtablissements: p.etablissements.length,
    nbClasses: p.classes.length,
    nbVisites: nbVisites,
    generale: generale,
    parEtablissement: parEtab,
    parClasse: parClasse,
    conclusions: conclusions,
    pathologies: pathologies,
    elevesAvecPathologie: avecPathologie,
    inspections: syntheseInspections(jeu, p),
    evolution: evolution,
  );
}

String _mois(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

DateTime _dernierMoisAvecDonnees(Iterable<String> mois, DateTime fin) {
  final m = mois.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
  final d = DateTime.utc(int.parse(m.substring(0, 4)), int.parse(m.substring(5, 7)));
  final f = DateTime.utc(fin.year, fin.month);
  return d.isAfter(f) ? f : d;
}

SyntheseInspections syntheseInspections(JeuStatistiques jeu, Perimetre p) {
  final dernieres = <String, InspectionStat>{};
  for (final x in jeu.inspections) {
    if (x.statut == StatutInspection.ebauche || !p.etablissements.contains(x.etablissementId)) continue;
    if (x.date.isBefore(p.debut) || x.date.isAfter(p.fin)) continue;
    final d = dernieres[x.etablissementId];
    if (d == null || x.date.isAfter(d.date) || (x.date == d.date && x.id.compareTo(d.id) > 0)) {
      dernieres[x.etablissementId] = x;
    }
  }
  final nc = <String, int>{};
  final pa = <String, int>{};
  for (final x in dernieres.values) {
    x.reponses.forEach((critere, r) {
      if (r == ResultatInspection.nonConforme) nc[critere] = (nc[critere] ?? 0) + 1;
      if (r == ResultatInspection.partiel) pa[critere] = (pa[critere] ?? 0) + 1;
    });
  }
  final insuffisances = [
    for (final c in {...nc.keys, ...pa.keys}) Insuffisance(c, jeu.criteres[c] ?? 'Critère retiré', nc[c] ?? 0, pa[c] ?? 0)
  ]..sort((a, b) {
      final n = b.nonConformes.compareTo(a.nonConformes);
      if (n != 0) return n;
      final t = b.total.compareTo(a.total);
      return t != 0 ? t : a.libelle.compareTo(b.libelle);
    });
  final tauxConnus = [for (final x in dernieres.values) if (x.taux != null) x.taux!];
  return SyntheseInspections(
    etablissements: p.etablissements.length,
    inspectes: dernieres.length,
    satisfaisants: dernieres.values.where((x) => x.niveau == NiveauConformite.satisfaisant).length,
    moyens: dernieres.values.where((x) => x.niveau == NiveauConformite.moyen).length,
    insuffisants: dernieres.values.where((x) => x.niveau == NiveauConformite.insuffisant).length,
    tauxMoyen: tauxConnus.isEmpty
        ? null
        : (tauxConnus.reduce((a, b) => a + b) / tauxConnus.length * 10).roundToDouble() / 10,
    principalesInsuffisances: insuffisances,
    dernieres: dernieres,
  );
}

// ------------------------------------------------------- listes nominatives

class LigneListeEleve {
  final EleveStat eleve;
  final String etablissement;
  final String classe;
  final VisiteStat? derniereVisite;
  const LigneListeEleve(this.eleve, this.etablissement, this.classe, this.derniereVisite);
}

List<LigneListeEleve> _lignes(JeuStatistiques jeu, Perimetre p, bool Function(EleveStat e) garder) {
  final l = [
    for (final e in p.eleves)
      if (garder(e))
        LigneListeEleve(e, jeu.etablissements[e.etablissementId] ?? '', jeu.classes[e.classeId]?.libelle ?? '',
            p.derniere(e.id))
  ]..sort((a, b) {
      final x = a.etablissement.compareTo(b.etablissement);
      if (x != 0) return x;
      final y = a.classe.compareTo(b.classe);
      return y != 0 ? y : a.eleve.nomComplet.compareTo(b.eleve.nomComplet);
    });
  return l;
}

/// Élèves examinés ([examines] vrai) ou non examinés du périmètre.
List<LigneListeEleve> listeEleves(JeuStatistiques jeu, FiltreStatistiques f, {required bool examines}) {
  final p = perimetre(jeu, f);
  return _lignes(jeu, p, (e) => p.examine(e.id) == examines);
}

/// Élèves dont la dernière visite conclut à une référence ou à un suivi médical.
List<LigneListeEleve> listeSuivis(JeuStatistiques jeu, FiltreStatistiques f, {Set<ConclusionVisite>? conclusions}) {
  final garder = conclusions ?? {ConclusionVisite.reference, ConclusionVisite.suivi};
  final p = perimetre(jeu, f);
  return _lignes(jeu, p, (e) => garder.contains(p.derniere(e.id)?.conclusion));
}
