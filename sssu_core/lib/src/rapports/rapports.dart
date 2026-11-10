/// Composition des rapports (section 13) : fiches individuelles de visite,
/// listes d'élèves examinés, non examinés, référés et à suivre, rapports par
/// établissement, par classe et annuels, rapport des pathologies, rapports
/// d'inspection sanitaire. Chaque fonction renvoie un [DocumentRapport],
/// rendu ensuite en PDF ou en Excel.
///
/// Les contrôles de droits sont faits ici : documents nominatifs réservés au
/// droit `rapport.exporter_nominatif`, photographies médicales au droit
/// `photo.voir_toutes` et sur demande explicite.
library;

import 'dart:convert';

import '../auth/permissions.dart';
import '../commun/commun.dart';
import '../inspection/formulaire_inspection.dart';
import '../modeles/enums.dart';
import '../regles/age.dart';
import '../regles/imc.dart';
import '../statistiques/statistiques.dart';
import '../sync/depot_serveur.dart';
import '../sync/enregistrement.dart';
import 'document.dart';

class RapportRefuse implements Exception {
  final String message;
  const RapportRefuse(this.message);
  @override
  String toString() => message;
}

void _exiger(Droits a, Permission p, String quoi) {
  if (!a.peut(p)) throw RapportRefuse('Votre profil ne permet pas d\'éditer $quoi.');
}

String _date(DateTime? d) {
  if (d == null) return '';
  String z(int n) => n.toString().padLeft(2, '0');
  return '${z(d.day)}/${z(d.month)}/${d.year}';
}

/// Description lisible des filtres appliqués.
String descriptionPerimetre(JeuStatistiques jeu, FiltreStatistiques f) {
  final morceaux = <String>['Année scolaire ${jeu.annee.libelle}'];
  if (f.etablissementId != null) morceaux.add(jeu.etablissements[f.etablissementId] ?? 'établissement');
  if (f.classeId != null) morceaux.add('classe ${jeu.classes[f.classeId]?.libelle ?? ''}');
  if (f.sexe != null) morceaux.add(f.sexe == Sexe.masculin ? 'garçons' : 'filles');
  if (f.du != null || f.au != null) {
    morceaux.add('période du ${_date(f.du ?? jeu.annee.debut)} au ${_date(f.au ?? jeu.annee.fin)}');
  }
  return morceaux.join(' · ');
}

BlocTableau _tableauCouverture(String titre, String premiereColonne, List<Couverture> lignes, {Couverture? total}) =>
    BlocTableau(
      titre: titre,
      entetes: [premiereColonne, 'Effectif', 'Garçons', 'Filles', 'Examinés', 'Non examinés', 'Couverture'],
      largeurs: const [4, 1.3, 1.3, 1.3, 1.3, 1.5, 1.5],
      lignes: [
        for (final c in lignes)
          [c.libelle, c.effectif, c.garcons, c.filles, c.examines, c.nonExamines, pourcentage(c.tauxCouverture)]
      ],
      totaux: total == null
          ? null
          : ['Total', total.effectif, total.garcons, total.filles, total.examines, total.nonExamines,
              pourcentage(total.tauxCouverture)],
    );

List<BlocRapport> _blocsPathologies(Statistiques s, JeuStatistiques jeu, {bool detail = true}) {
  final avecCas = s.pathologies.where((p) => p.cas > 0).toList()..sort((a, b) => b.cas.compareTo(a.cas));
  final blocs = <BlocRapport>[
    BlocParagraphe('${s.elevesAvecPathologie} élève(s) examiné(s) sur ${s.generale.examines} présentent au moins une '
        'pathologie (${pourcentage(taux(s.elevesAvecPathologie, s.generale.examines))}).'),
    BlocTableau(
      titre: 'Cas par pathologie et par sexe',
      entetes: ['Pathologie', 'Cas', 'Garçons', 'Filles', 'Prévalence'],
      largeurs: const [5, 1.2, 1.2, 1.2, 1.5],
      lignes: [for (final p in s.pathologies) [p.libelle, p.cas, p.garcons, p.filles, pourcentage(p.prevalence)]],
    ),
  ];
  if (detail && avecCas.isNotEmpty) {
    final tranches = TrancheAge.values.where((t) => avecCas.any((p) => (p.parTranche[t] ?? 0) > 0)).toList();
    blocs.add(BlocTableau(
      titre: 'Répartition par tranche d\'âge (pathologies dépistées)',
      entetes: ['Pathologie', for (final t in tranches) t.libelle],
      lignes: [for (final p in avecCas) [p.libelle, for (final t in tranches) p.parTranche[t] ?? 0]],
    ));
    if (s.parEtablissement.length > 1) {
      blocs.add(BlocTableau(
        titre: 'Répartition par établissement (nombre de cas)',
        entetes: ['Pathologie', for (final e in s.parEtablissement) e.libelle],
        lignes: [for (final p in avecCas) [p.libelle, for (final e in s.parEtablissement) p.parEtablissement[e.id] ?? 0]],
      ));
    }
    if (s.parClasse.length > 1 && s.parClasse.length <= 12) {
      blocs.add(BlocTableau(
        titre: 'Répartition par classe (nombre de cas)',
        entetes: ['Pathologie', for (final c in s.parClasse) c.libelle],
        lignes: [for (final p in avecCas) [p.libelle, for (final c in s.parClasse) p.parClasse[c.id] ?? 0]],
      ));
    }
  }
  return blocs;
}

List<BlocRapport> _blocsInspections(SyntheseInspections x, JeuStatistiques jeu) => [
      BlocChamps([
        ('Établissements du périmètre', '${x.etablissements}'),
        ('Établissements inspectés', '${x.inspectes}'),
        ('Niveau satisfaisant (conformes)', '${x.satisfaisants}'),
        ('Niveau moyen', '${x.moyens}'),
        ('Niveau insuffisant', '${x.insuffisants}'),
        ('Taux moyen de conformité', pourcentage(x.tauxMoyen)),
      ]),
      if (x.dernieres.isNotEmpty)
        BlocTableau(
          titre: 'Dernière inspection par établissement',
          entetes: ['Établissement', 'Date', 'Conformes', 'Partiels', 'Non conformes', 'Taux', 'Niveau'],
          largeurs: const [4, 1.6, 1.3, 1.3, 1.5, 1.3, 1.6],
          lignes: [
            for (final e in jeu.etablissements.keys)
              if (x.dernieres[e] case final i?)
                [jeu.etablissements[e], _date(i.date), i.conformes, i.partiels, i.nonConformes, pourcentage(i.taux),
                  i.niveau?.libelle ?? '—']
          ],
        ),
      if (x.principalesInsuffisances.isNotEmpty)
        BlocTableau(
          titre: 'Principales insuffisances (dernières inspections)',
          entetes: ['Critère', 'Non conforme', 'Partiellement conforme'],
          largeurs: const [6, 1.5, 2],
          lignes: [for (final i in x.principalesInsuffisances.take(15)) [i.libelle, i.nonConformes, i.partiels]],
        ),
    ];

enum PorteeRapport {
  annuel('Rapport annuel des visites médicales scolaires'),
  etablissement('Rapport des visites médicales – établissement'),
  classe('Rapport des visites médicales – classe');

  final String titre;
  const PorteeRapport(this.titre);
}

/// Rapport statistique par établissement, par classe ou annuel (district).
DocumentRapport rapportStatistique(
  JeuStatistiques jeu,
  FiltreStatistiques f, {
  required PorteeRapport portee,
  required EnteteRapport entete,
  required Droits acteur,
  required DateTime genereLe,
}) {
  _exiger(acteur, Permission.statistiquesConsulter, 'les rapports statistiques');
  if (portee == PorteeRapport.etablissement && f.etablissementId == null) {
    throw const RapportRefuse('Choisir l\'établissement du rapport.');
  }
  if (portee == PorteeRapport.classe && f.classeId == null) throw const RapportRefuse('Choisir la classe du rapport.');
  final s = calculerStatistiques(jeu, f);
  final g = s.generale;
  final blocs = <BlocRapport>[
    const BlocTitre('1. Indicateurs généraux'),
    BlocChamps([
      if (portee == PorteeRapport.annuel) ('Établissements', '${s.nbEtablissements}'),
      if (portee != PorteeRapport.classe) ('Classes', '${s.nbClasses}'),
      ('Effectif total', '${g.effectif} (${g.garcons} garçons, ${g.filles} filles)'),
      ('Élèves examinés', '${g.examines} (${g.garconsExamines} garçons, ${g.fillesExamines} filles)'),
      ('Élèves non examinés', '${g.nonExamines}'),
      ('Visites médicales enregistrées', '${s.nbVisites}'),
      ('Taux de couverture', pourcentage(g.tauxCouverture)),
    ]),
    const BlocTitre('2. Couverture par sexe'),
    BlocTableau(
      entetes: ['Sexe', 'Effectif', 'Examinés', 'Couverture', 'Part des examinés'],
      lignes: [
        ['Garçons', g.garcons, g.garconsExamines, pourcentage(g.tauxGarcons), pourcentage(g.partGarconsExamines)],
        ['Filles', g.filles, g.fillesExamines, pourcentage(g.tauxFilles), pourcentage(g.partFillesExamines)],
      ],
      totaux: ['Total', g.effectif, g.examines, pourcentage(g.tauxCouverture), g.examines == 0 ? '—' : '100 %'],
    ),
    if (portee == PorteeRapport.annuel && s.parEtablissement.isNotEmpty)
      _tableauCouverture('Couverture par établissement', 'Établissement', s.parEtablissement, total: g),
    if (portee != PorteeRapport.classe && s.parClasse.isNotEmpty)
      _tableauCouverture('Couverture par classe', 'Classe', s.parClasse, total: g),
    const BlocTitre('3. Conclusions des visites'),
    BlocTableau(
      entetes: ['Conclusion (dernière visite)', 'Élèves', 'Part des examinés'],
      largeurs: const [6, 1.3, 1.8],
      lignes: [
        for (final c in ConclusionVisite.values) [c.libelle, s.conclusions[c] ?? 0, pourcentage(taux(s.conclusions[c] ?? 0, g.examines))]
      ],
    ),
    const BlocTitre('4. Profil des pathologies'),
    ..._blocsPathologies(s, jeu, detail: portee != PorteeRapport.classe),
    if (portee != PorteeRapport.classe) ...[
      const BlocTitre('5. Inspections sanitaires'),
      ..._blocsInspections(s.inspections, jeu),
    ],
    if (s.evolution.length > 1) ...[
      BlocTitre(portee == PorteeRapport.classe ? '5. Évolution mensuelle' : '6. Évolution mensuelle'),
      BlocTableau(
        entetes: ['Mois', 'Visites', 'Nouveaux examinés', 'Couverture cumulée'],
        lignes: [for (final e in s.evolution) [_mois(e.mois), e.visites, e.nouveauxExamines, pourcentage(e.couvertureCumulee)]],
      ),
    ],
    BlocSignature(fonction: 'Le Médecin-Chef', nom: entete.nomMedecinChef),
  ];
  return DocumentRapport(
    titre: portee.titre,
    sousTitre: descriptionPerimetre(jeu, f),
    entete: entete,
    blocs: blocs,
    genereLe: genereLe,
  );
}

String _mois(String m) {
  const noms = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre',
    'novembre', 'décembre'];
  return '${noms[int.parse(m.substring(5, 7)) - 1]} ${m.substring(0, 4)}';
}

DocumentRapport rapportPathologies(
  JeuStatistiques jeu,
  FiltreStatistiques f, {
  required EnteteRapport entete,
  required Droits acteur,
  required DateTime genereLe,
}) {
  _exiger(acteur, Permission.statistiquesConsulter, 'les rapports statistiques');
  final s = calculerStatistiques(jeu, f);
  return DocumentRapport(
    titre: 'Rapport statistique des pathologies dépistées',
    sousTitre: descriptionPerimetre(jeu, f),
    entete: entete,
    paysage: s.parEtablissement.length > 4,
    blocs: [
      BlocChamps([
        ('Élèves examinés', '${s.generale.examines}'),
        ('Élèves porteurs d\'au moins une pathologie', '${s.elevesAvecPathologie}'),
      ]),
      ..._blocsPathologies(s, jeu),
      const BlocParagraphe(
          'Prévalence : élèves chez qui la pathologie a été dépistée, rapportés aux élèves examinés du périmètre. '
          'Tranche d\'âge : âge à la date de la dernière visite.',
          italique: true),
      BlocSignature(fonction: 'Le Médecin-Chef', nom: entete.nomMedecinChef),
    ],
    genereLe: genereLe,
  );
}

/// Liste nominative des élèves examinés ou non examinés.
DocumentRapport rapportListeEleves(
  JeuStatistiques jeu,
  FiltreStatistiques f, {
  required bool examines,
  required EnteteRapport entete,
  required Droits acteur,
  required DateTime genereLe,
}) {
  _exiger(acteur, Permission.rapportExporterNominatif, 'les listes nominatives');
  final l = listeEleves(jeu, f, examines: examines);
  final avecEtab = f.etablissementId == null && f.classeId == null;
  return DocumentRapport(
    titre: examines ? 'Liste des élèves examinés' : 'Liste des élèves non examinés',
    sousTitre: descriptionPerimetre(jeu, f),
    entete: entete,
    confidentiel: true,
    blocs: [
      BlocParagraphe('${l.length} élève(s).'),
      BlocTableau(
        entetes: ['N°', 'Matricule', 'Nom et prénoms', 'Sexe', 'Date de naissance', if (avecEtab) 'Établissement', 'Classe',
          if (examines) 'Dernière visite'],
        largeurs: [0.6, 1.6, 4, 0.8, 1.6, if (avecEtab) 3, 1.4, if (examines) 1.6],
        lignes: [
          for (var i = 0; i < l.length; i++)
            [
              i + 1,
              l[i].eleve.matricule ?? '',
              l[i].eleve.nomComplet,
              l[i].eleve.sexe.code,
              _date(l[i].eleve.dateNaissance),
              if (avecEtab) l[i].etablissement,
              l[i].classe,
              if (examines) _date(l[i].derniereVisite?.date),
            ]
        ],
      ),
    ],
    genereLe: genereLe,
  );
}

/// Élèves référés et élèves nécessitant un suivi médical (dernière visite).
DocumentRapport rapportSuivis(
  JeuStatistiques jeu,
  FiltreStatistiques f, {
  required EnteteRapport entete,
  required Droits acteur,
  required DateTime genereLe,
}) {
  _exiger(acteur, Permission.rapportExporterNominatif, 'les listes nominatives');
  final refs = listeSuivis(jeu, f, conclusions: {ConclusionVisite.reference});
  final suivis = listeSuivis(jeu, f, conclusions: {ConclusionVisite.suivi});
  List<Object?> ligne(int i, LigneListeEleve x, {required bool reference}) => [
        i + 1,
        x.eleve.nomComplet,
        x.eleve.sexe.code,
        '${x.etablissement} – ${x.classe}',
        _date(x.derniereVisite?.date),
        x.derniereVisite?.diagnostic ?? '',
        reference ? (x.derniereVisite?.structureReference ?? '') : _date(x.derniereVisite?.dateControle),
        x.eleve.telephoneContact ?? '',
      ];
  return DocumentRapport(
    titre: 'Élèves référés et élèves nécessitant un suivi médical',
    sousTitre: descriptionPerimetre(jeu, f),
    entete: entete,
    confidentiel: true,
    paysage: true,
    blocs: [
      BlocTitre('Élèves référés vers une structure sanitaire (${refs.length})'),
      BlocTableau(
        entetes: ['N°', 'Nom et prénoms', 'Sexe', 'Établissement – classe', 'Visite', 'Diagnostic', 'Structure de référence',
          'Contact'],
        largeurs: const [0.5, 3, 0.6, 3, 1.3, 4, 2.6, 1.6],
        lignes: [for (var i = 0; i < refs.length; i++) ligne(i, refs[i], reference: true)],
      ),
      BlocTitre('Élèves nécessitant un suivi médical (${suivis.length})'),
      BlocTableau(
        entetes: ['N°', 'Nom et prénoms', 'Sexe', 'Établissement – classe', 'Visite', 'Diagnostic', 'Contrôle prévu',
          'Contact'],
        largeurs: const [0.5, 3, 0.6, 3, 1.3, 4, 1.6, 1.6],
        lignes: [for (var i = 0; i < suivis.length; i++) ligne(i, suivis[i], reference: false)],
      ),
      BlocSignature(fonction: 'Le Médecin-Chef', nom: entete.nomMedecinChef),
    ],
    genereLe: genereLe,
  );
}

// ---------------------------------------------------------- fiche de visite

class PhotoRapport {
  final List<int> image;
  final String legende;
  const PhotoRapport(this.image, this.legende);
}

/// Données d'une fiche individuelle de visite, lues sur le poste central.
class FicheVisite {
  final Enregistrement visite;
  final Enregistrement eleve;
  final String? etablissement;
  final String? classe;
  final String? annee;
  final String? agent;
  final String? validateur;
  final List<Enregistrement> antecedents;
  final List<Enregistrement> examens;

  /// Pathologies dépistées : (libellé, précision).
  final List<(String, String?)> pathologies;

  /// Identifiants des photographies de la visite (non supprimées).
  final List<String> photos;
  const FicheVisite({
    required this.visite,
    required this.eleve,
    this.etablissement,
    this.classe,
    this.annee,
    this.agent,
    this.validateur,
    required this.antecedents,
    required this.examens,
    required this.pathologies,
    required this.photos,
  });

  static Future<FicheVisite> charger(TransactionServeur tx, String visiteId) async {
    final v = await tx.lire('visite', visiteId);
    if (v == null || v.supprime) throw const RapportRefuse('Visite introuvable.');
    final e = (await tx.lire('eleve', v.donnees['eleve_id']! as String))!;
    Enregistrement? inscription;
    if (v.donnees['inscription_id'] case final String id) inscription = await tx.lire('inscription', id);
    final classe = inscription == null ? null : await tx.lire('classe', inscription.donnees['classe_id']! as String);
    final etab = classe == null
        ? (v.etablissementId == null ? null : await tx.lire('etablissement', v.etablissementId!))
        : await tx.lire('etablissement', classe.donnees['etablissement_id']! as String);
    final annee =
        classe == null ? null : await tx.lire('annee_scolaire', classe.donnees['annee_scolaire_id']! as String);
    Future<String?> nom(Object? id) async {
      if (id == null) return null;
      final u = await tx.lire('utilisateur', id as String);
      return u == null ? null : [u.donnees['nom'], u.donnees['prenoms']].whereType<String>().join(' ');
    }

    final pathos = <(String, String?)>[];
    for (final vp in await tx.chercher('visite_pathologie', {'visite_id': visiteId})) {
      if (vp.supprime) continue;
      final p = await tx.lire('pathologie', vp.donnees['pathologie_id']! as String);
      pathos.add((p?.donnees['libelle'] as String? ?? 'Pathologie', vp.donnees['precision'] as String?));
    }
    return FicheVisite(
      visite: v,
      eleve: e,
      etablissement: etab?.donnees['nom'] as String?,
      classe: classe?.donnees['libelle'] as String?,
      annee: annee?.donnees['libelle'] as String?,
      agent: await nom(v.donnees['agent_id']),
      validateur: await nom(v.donnees['validateur_id']),
      antecedents: [for (final a in await tx.chercher('antecedent', {'visite_id': visiteId})) if (!a.supprime) a],
      examens: [for (final x in await tx.chercher('examen_appareil', {'visite_id': visiteId})) if (!x.supprime) x],
      pathologies: pathos,
      photos: [for (final p in await tx.chercher('photo', {'visite_id': visiteId})) if (!p.supprime) p.id],
    );
  }
}

String _nombre(Object? v, String unite) => v == null ? '' : '${texteCellule(v is int ? v : (v as num).toDouble())} $unite';

/// Fiche individuelle de visite médicale. Les [photos] ne sont intégrées que
/// si elles sont fournies (demande explicite) et si le profil voit les photos.
DocumentRapport ficheVisite(
  FicheVisite fv, {
  required EnteteRapport entete,
  required Droits acteur,
  required DateTime genereLe,
  List<PhotoRapport> photos = const [],
}) {
  _exiger(acteur, Permission.rapportExporterNominatif, 'les fiches individuelles');
  if (photos.isNotEmpty) _exiger(acteur, Permission.photoVoirToutes, 'les photographies médicales');
  final v = fv.visite.donnees;
  final e = fv.eleve.donnees;
  final dateVisite = lireDate(v['date_visite']! as String);
  final naissance = e['date_naissance'] == null ? null : lireDate(e['date_naissance']! as String);
  final age = naissance == null || naissance.isAfter(dateVisite) ? '' : calculerAge(naissance, dateVisite).toString();
  final conclusion = v['conclusion'] == null ? null : ConclusionVisite.depuisCode(v['conclusion']! as String);
  final ta = v['ta_sys'] == null ? '' : '${v['ta_sys']}/${v['ta_dia'] ?? '?'} mmHg';
  return DocumentRapport(
    titre: 'Fiche individuelle de visite médicale',
    sousTitre: 'Visite du ${_date(dateVisite)}',
    entete: entete,
    confidentiel: true,
    blocs: [
      const BlocTitre('Identification de l\'élève'),
      BlocChamps([
        ('Nom et prénoms', [e['nom'], e['prenoms']].whereType<String>().join(' ')),
        ('Matricule', (e['matricule'] as String?) ?? ''),
        ('Sexe', Sexe.depuisCode(e['sexe']! as String).libelle),
        ('Date de naissance', _date(naissance)),
        ('Âge à la visite', age),
        ('Établissement', fv.etablissement ?? ''),
        ('Classe', [fv.classe, if (fv.annee != null) '(${fv.annee})'].whereType<String>().join(' ')),
        ('Contact', (e['telephone_contact'] as String?) ?? ''),
      ]),
      const BlocTitre('Visite'),
      BlocChamps([
        ('Date', _date(dateVisite)),
        ('Agent', fv.agent ?? ''),
        ('Structure d\'origine', (v['structure_origine'] as String?) ?? ''),
        ('Statut', StatutVisite.depuisCode(v['statut']! as String).libelle),
        if (fv.validateur != null) ('Validée par', fv.validateur!),
      ]),
      const BlocTitre('Antécédents'),
      BlocTableau(
        entetes: ['Antécédent', 'Présent', 'Précisions'],
        largeurs: const [3, 1, 5],
        lignes: [
          for (final a in fv.antecedents)
            [TypeAntecedent.depuisCode(a.donnees['type']! as String).libelle, a.donnees['coche'] == true ? 'Oui' : 'Non',
              (a.donnees['commentaire'] as String?) ?? '']
        ],
      ),
      const BlocTitre('Mesures et constantes'),
      BlocChamps([
        ('Poids', _nombre(v['poids_kg'], 'kg')),
        ('Taille', _nombre(v['taille_cm'], 'cm')),
        ('IMC', [
          if (v['imc'] != null) '${texteCellule((v['imc']! as num).toDouble())} kg/m²',
          CategorieImc.values.where((c) => c.code == v['imc_interpretation']).firstOrNull?.libelle ?? v['imc_interpretation'],
        ].whereType<String>().join(' – ')),
        ('Tension artérielle', ta),
        ('Température', _nombre(v['temperature_c'], '°C')),
        ('Fréquence cardiaque', _nombre(v['fc'], '/min')),
        ('Fréquence respiratoire', _nombre(v['fr'], '/min')),
      ]),
      const BlocTitre('Examen par appareil'),
      BlocTableau(
        entetes: ['Appareil', 'Résultat', 'Observation'],
        largeurs: const [3, 1.5, 5],
        lignes: [
          for (final x in fv.examens)
            [AppareilExamen.depuisCode(x.donnees['appareil']! as String).libelle,
              ResultatExamen.depuisCode(x.donnees['resultat']! as String).libelle, (x.donnees['observation'] as String?) ?? '']
        ],
      ),
      const BlocTitre('Pathologies dépistées'),
      if (fv.pathologies.isEmpty)
        const BlocParagraphe('Aucune pathologie dépistée.')
      else
        BlocTableau(
          entetes: ['Pathologie', 'Précision'],
          largeurs: const [4, 5],
          lignes: [for (final (l, p) in fv.pathologies) [l, p ?? '']],
        ),
      const BlocTitre('Conclusion'),
      BlocChamps([
        ('Conclusion', conclusion?.libelle ?? ''),
        ('Diagnostic', (v['diagnostic'] as String?) ?? ''),
        ('Conduite à tenir', (v['conduite_a_tenir'] as String?) ?? ''),
        ('Traitement et conseils', (v['traitement_conseils'] as String?) ?? ''),
        if (conclusion == ConclusionVisite.reference) ('Structure de référence', (v['structure_reference'] as String?) ?? ''),
        if (v['date_controle'] != null) ('Date de contrôle', _date(lireDate(v['date_controle']! as String))),
        ('Observations', (v['observations'] as String?) ?? ''),
      ]),
      if (photos.isNotEmpty) ...[
        const BlocTitre('Photographies cliniques'),
        for (final p in photos) BlocImage(p.image, legende: p.legende, largeurMax: 240),
      ],
      BlocSignature(fonction: 'Le médecin', nom: fv.validateur),
    ],
    genereLe: genereLe,
  );
}

// ------------------------------------------------------ fiche d'inspection

class ReponseFiche {
  final CritereGrille critere;
  final ResultatInspection resultat;
  final String? observation;

  /// Photographies des insuffisances constatées.
  final List<String> photos;
  const ReponseFiche(this.critere, this.resultat, this.observation, this.photos);
}

class FicheInspection {
  final Enregistrement inspection;
  final String etablissement;
  final String? annee;
  final String? inspecteur;
  final List<ReponseFiche> reponses;
  const FicheInspection({
    required this.inspection,
    required this.etablissement,
    this.annee,
    this.inspecteur,
    required this.reponses,
  });

  static Future<FicheInspection> charger(TransactionServeur tx, String inspectionId) async {
    final i = await tx.lire('inspection', inspectionId);
    if (i == null || i.supprime) throw const RapportRefuse('Inspection introuvable.');
    final etab = await tx.lire('etablissement', i.donnees['etablissement_id']! as String);
    final annee = await tx.lire('annee_scolaire', i.donnees['annee_scolaire_id']! as String);
    final u = await tx.lire('utilisateur', i.donnees['inspecteur_id']! as String);
    final reponses = <ReponseFiche>[];
    for (final r in await tx.chercher('inspection_reponse', {'inspection_id': inspectionId})) {
      if (r.supprime) continue;
      final c = await tx.lire('critere_inspection', r.donnees['critere_id']! as String);
      if (c == null) continue;
      reponses.add(ReponseFiche(
        CritereGrille.depuisDonnees(c.id, c.donnees),
        ResultatInspection.depuisCode(r.donnees['resultat']! as String),
        r.donnees['observation'] as String?,
        [for (final p in await tx.chercher('inspection_photo', {'inspection_reponse_id': r.id})) if (!p.supprime) p.id],
      ));
    }
    return FicheInspection(
      inspection: i,
      etablissement: etab?.donnees['nom'] as String? ?? '',
      annee: annee?.donnees['libelle'] as String?,
      inspecteur: u == null ? null : [u.donnees['nom'], u.donnees['prenoms']].whereType<String>().join(' '),
      reponses: reponses,
    );
  }
}

/// Rapport d'inspection sanitaire d'un établissement. [photos] : images des
/// insuffisances, par identifiant de photo (celles qui sont disponibles).
DocumentRapport rapportInspection(
  FicheInspection fi, {
  required EnteteRapport entete,
  required Droits acteur,
  required DateTime genereLe,
  Map<String, List<int>> photos = const {},
}) {
  if (!acteur.peut(Permission.inspectionRealiser) && !acteur.peut(Permission.statistiquesConsulter)) {
    throw const RapportRefuse('Votre profil ne permet pas d\'éditer les rapports d\'inspection.');
  }
  final d = fi.inspection.donnees;
  final parRubrique = grilleParRubrique(fi.reponses.map((r) => r.critere));
  final reponseDe = {for (final r in fi.reponses) r.critere.id: r};
  final signature = d['signature'] as String?;
  final niveau = d['niveau'] == null ? null : NiveauConformite.depuisCode(d['niveau']! as String);
  final photosInsuffisances = [
    for (final r in fi.reponses)
      for (final p in r.photos)
        if (photos[p] case final img?) BlocImage(img, legende: r.critere.libelle, largeurMax: 200)
  ];
  return DocumentRapport(
    titre: 'Rapport d\'inspection sanitaire',
    sousTitre: '${fi.etablissement} · ${_date(lireDate(d['date_inspection']! as String))}',
    entete: entete,
    blocs: [
      BlocChamps([
        ('Établissement', fi.etablissement),
        ('Année scolaire', fi.annee ?? ''),
        ('Date de l\'inspection', _date(lireDate(d['date_inspection']! as String))),
        ('Inspecteur', fi.inspecteur ?? ''),
      ]),
      const BlocTitre('Résultats'),
      BlocChamps([
        ('Critères conformes', '${d['nb_conformes'] ?? 0}'),
        ('Partiellement conformes', '${d['nb_partiels'] ?? 0}'),
        ('Non conformes', '${d['nb_non_conformes'] ?? 0}'),
        ('Non applicables', '${d['nb_non_applicables'] ?? 0}'),
        ('Taux de conformité', pourcentage((d['taux_conformite'] as num?)?.toDouble())),
        ('Niveau global', niveau?.libelle ?? '—'),
      ]),
      const BlocParagraphe(
          'Taux = (conformes + ½ partiellement conformes) / critères évalués ; les critères « non applicable » sont exclus.',
          italique: true),
      const BlocTitre('Grille d\'inspection'),
      for (final MapEntry(key: rub, value: criteres) in parRubrique.entries)
        BlocTableau(
          titre: '${rub.libelle} — ${rub.elements}',
          entetes: ['Critère', 'Résultat', 'Observation'],
          largeurs: const [4, 2, 4],
          lignes: [
            for (final c in criteres)
              [c.libelle, reponseDe[c.id]!.resultat.libelle, reponseDe[c.id]!.observation ?? '']
          ],
        ),
      const BlocTitre('Observations'),
      BlocParagraphe((d['observations'] as String?)?.trim().isNotEmpty == true ? d['observations']! as String : 'Néant.'),
      const BlocTitre('Recommandations'),
      BlocParagraphe(
          (d['recommandations'] as String?)?.trim().isNotEmpty == true ? d['recommandations']! as String : 'Néant.'),
      if (photosInsuffisances.isNotEmpty) ...[
        const BlocTitre('Photographies des insuffisances constatées'),
        ...photosInsuffisances,
      ],
      BlocSignature(
        fonction: 'L\'inspecteur',
        nom: fi.inspecteur,
        image: signature == null ? null : base64.decode(signature),
        cachet: false,
      ),
    ],
    genereLe: genereLe,
  );
}

/// Historique des inspections d'un établissement (ou de tous).
DocumentRapport rapportHistoriqueInspections(
  JeuStatistiques jeu, {
  String? etablissementId,
  required EnteteRapport entete,
  required Droits acteur,
  required DateTime genereLe,
}) {
  _exiger(acteur, Permission.statistiquesConsulter, 'la synthèse des inspections');
  final f = FiltreStatistiques(etablissementId: etablissementId);
  final s = calculerStatistiques(jeu, f);
  final liste = [
    for (final i in jeu.inspections)
      if (i.statut != StatutInspection.ebauche && (etablissementId == null || i.etablissementId == etablissementId)) i
  ]..sort((a, b) {
      final e = (jeu.etablissements[a.etablissementId] ?? '').compareTo(jeu.etablissements[b.etablissementId] ?? '');
      return e != 0 ? e : b.date.compareTo(a.date);
    });
  return DocumentRapport(
    titre: 'Synthèse des inspections sanitaires',
    sousTitre: descriptionPerimetre(jeu, f),
    entete: entete,
    blocs: [
      ..._blocsInspections(s.inspections, jeu),
      BlocTableau(
        titre: 'Historique des inspections',
        entetes: ['Établissement', 'Date', 'Conformes', 'Partiels', 'Non conformes', 'Non applicables', 'Taux', 'Niveau'],
        lignes: [
          for (final i in liste)
            [jeu.etablissements[i.etablissementId] ?? '', _date(i.date), i.conformes, i.partiels, i.nonConformes,
              i.nonApplicables, pourcentage(i.taux), i.niveau?.libelle ?? '—']
        ],
      ),
      BlocSignature(fonction: 'Le Médecin-Chef', nom: entete.nomMedecinChef),
    ],
    genereLe: genereLe,
  );
}
