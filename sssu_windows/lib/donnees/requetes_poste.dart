/// Requêtes de consultation du poste central (PostgreSQL) : établissements,
/// classes, élèves, dossiers, photos, synchronisations, journal d'audit.
library;

import 'package:sssu_core/sssu_core.dart';

import 'depot_postgres.dart';

String _d(Object? v) => v == null ? '' : (v is DateTime ? formaterDate(v) : v.toString().substring(0, 10));
String? _dn(Object? v) => v == null ? null : _d(v);
String? _s(Object? v) => v?.toString();
int _i(Object? v) => v == null ? 0 : (v as num).toInt();

class Annee {
  final String id;
  final String libelle;
  final String debut;
  final String fin;
  final bool active;
  const Annee(this.id, this.libelle, this.debut, this.fin, this.active);
}

class LigneEtablissement {
  final Map<String, dynamic> donnees;
  final int classes;
  final int effectif;
  final int examines;
  final int telephones;
  const LigneEtablissement(this.donnees, this.classes, this.effectif, this.examines, this.telephones);
  String get id => donnees['id'].toString();
  String get nom => donnees['nom'] as String;
}

class LigneClasse {
  final String id;
  final String libelle;
  final String? niveau;
  final int effectif;
  final int garcons;
  final int filles;
  final int examines;
  const LigneClasse(this.id, this.libelle, this.niveau, this.effectif, this.garcons, this.filles, this.examines);
}

class LigneEleve {
  final String id;
  final String? matricule;
  final String nom;
  final String prenoms;
  final String sexe;
  final String? dateNaissance;
  final String? inscriptionId;
  final String? classe;
  final String? etablissement;
  final String? derniereVisite;
  final String? statutVisite;
  const LigneEleve(this.id, this.matricule, this.nom, this.prenoms, this.sexe, this.dateNaissance, this.inscriptionId,
      this.classe, this.etablissement, this.derniereVisite, this.statutVisite);
}

class LigneInscription {
  final String id;
  final String annee;
  final String classeId;
  final String classe;
  final String etablissement;
  final String statut;
  const LigneInscription(this.id, this.annee, this.classeId, this.classe, this.etablissement, this.statut);
}

class LigneVisite {
  final String id;
  final String date;
  final String statut;
  final String? conclusion;
  final String agent;
  final String? diagnostic;
  final int photos;
  const LigneVisite(this.id, this.date, this.statut, this.conclusion, this.agent, this.diagnostic, this.photos);
}

class LignePhoto {
  final String id;
  final String visiteId;
  final String dateVisite;
  final String? commentaire;
  final String? pathologie;
  final String auteurId;
  final String auteur;
  final String prisLe;
  final String statutTransfert;
  const LignePhoto(this.id, this.visiteId, this.dateVisite, this.commentaire, this.pathologie, this.auteurId, this.auteur,
      this.prisLe, this.statutTransfert);
}

class RequetesPoste {
  final DepotPostgres depot;
  RequetesPoste(this.depot);

  Future<List<Annee>> annees() async => [
        for (final r in await depot.requete('SELECT id, libelle, date_debut, date_fin, active FROM annee_scolaire '
            'WHERE deleted_at IS NULL ORDER BY date_debut DESC'))
          Annee(r['id'].toString(), r['libelle'] as String, _d(r['date_debut']), _d(r['date_fin']), r['active'] as bool),
      ];

  Future<Annee?> anneeCourante() async {
    final a = await annees();
    if (a.isEmpty) return null;
    return a.firstWhere((x) => x.active, orElse: () => a.first);
  }

  static const _examine = 'EXISTS (SELECT 1 FROM visite v WHERE v.eleve_id = i.eleve_id AND v.deleted_at IS NULL '
      "AND v.statut <> 'ebauche' AND v.date_visite BETWEEN a.date_debut AND a.date_fin)";

  /// Tous les établissements non archivés (paramètres), par code.
  Future<List<Map<String, dynamic>>> listeEtablissements() =>
      depot.requete('SELECT * FROM etablissement WHERE deleted_at IS NULL ORDER BY code, nom');

  Future<List<LigneEtablissement>> etablissements(Annee annee) async {
    final r = await depot.requete(
      'SELECT e.*, '
      '(SELECT COUNT(*) FROM classe c WHERE c.etablissement_id = e.id AND c.annee_scolaire_id = a.id AND c.deleted_at IS NULL) AS nb_classes, '
      '(SELECT COUNT(*) FROM inscription i JOIN classe c ON c.id = i.classe_id WHERE c.etablissement_id = e.id '
      "AND i.annee_scolaire_id = a.id AND i.deleted_at IS NULL AND i.statut = 'inscrit') AS effectif, "
      '(SELECT COUNT(*) FROM inscription i JOIN classe c ON c.id = i.classe_id WHERE c.etablissement_id = e.id '
      "AND i.annee_scolaire_id = a.id AND i.deleted_at IS NULL AND i.statut = 'inscrit' AND $_examine) AS examines, "
      '(SELECT COUNT(*) FROM appareil_etablissement ae WHERE ae.etablissement_id = e.id AND ae.deleted_at IS NULL) AS telephones '
      'FROM etablissement e CROSS JOIN annee_scolaire a '
      'WHERE e.deleted_at IS NULL AND a.id = CAST(@annee AS uuid) ORDER BY e.nom',
      {'annee': annee.id},
    );
    return [
      for (final l in r) LigneEtablissement(l, _i(l['nb_classes']), _i(l['effectif']), _i(l['examines']), _i(l['telephones']))
    ];
  }

  Future<List<LigneClasse>> classes(String etablissementId, Annee annee) async {
    final r = await depot.requete(
      'SELECT c.id, c.libelle, c.niveau, COUNT(i.id) AS effectif, '
      "COUNT(*) FILTER (WHERE el.sexe = 'M') AS garcons, COUNT(*) FILTER (WHERE el.sexe = 'F') AS filles, "
      'COUNT(*) FILTER (WHERE i.id IS NOT NULL AND $_examine) AS examines '
      'FROM classe c JOIN annee_scolaire a ON a.id = c.annee_scolaire_id '
      "LEFT JOIN inscription i ON i.classe_id = c.id AND i.deleted_at IS NULL AND i.statut = 'inscrit' "
      'LEFT JOIN eleve el ON el.id = i.eleve_id '
      'WHERE c.etablissement_id = CAST(@etab AS uuid) AND c.annee_scolaire_id = CAST(@annee AS uuid) AND c.deleted_at IS NULL '
      'GROUP BY c.id, c.libelle, c.niveau ORDER BY c.niveau, c.libelle',
      {'etab': etablissementId, 'annee': annee.id},
    );
    return [
      for (final l in r)
        LigneClasse(l['id'].toString(), l['libelle'] as String, l['niveau'] as String?, _i(l['effectif']),
            _i(l['garcons']), _i(l['filles']), _i(l['examines']))
    ];
  }

  /// Listes de classe d'un établissement pour l'année : chaque classe (même
  /// vide) avec ses élèves inscrits, classes dans l'ordre scolaire (CP1… CM2,
  /// 6ème… Tle), élèves par nom.
  Future<List<ListeDeClasse>> listesDeClasses(String etablissementId, Annee annee) async {
    final classes = await depot.requete(
      'SELECT CAST(id AS text) AS id, libelle, niveau FROM classe '
      'WHERE etablissement_id = CAST(@etab AS uuid) AND annee_scolaire_id = CAST(@annee AS uuid) AND deleted_at IS NULL',
      {'etab': etablissementId, 'annee': annee.id},
    );
    final eleves = await depot.requete(
      'SELECT CAST(i.classe_id AS text) AS classe_id, CAST(el.id AS text) AS id, el.matricule, el.nom, el.prenoms, el.sexe, '
      'el.date_naissance, el.telephone_contact, dv.date_visite AS derniere_visite, dv.statut AS statut_visite '
      'FROM inscription i '
      'JOIN classe c ON c.id = i.classe_id AND c.deleted_at IS NULL '
      'JOIN eleve el ON el.id = i.eleve_id AND el.deleted_at IS NULL '
      'LEFT JOIN LATERAL (SELECT v.date_visite, v.statut FROM visite v WHERE v.eleve_id = el.id AND v.deleted_at IS NULL '
      'AND v.date_visite BETWEEN CAST(@debut AS date) AND CAST(@fin AS date) '
      'ORDER BY v.date_visite DESC, v.updated_at DESC LIMIT 1) dv ON TRUE '
      "WHERE c.etablissement_id = CAST(@etab AS uuid) AND i.annee_scolaire_id = CAST(@annee AS uuid) "
      "AND i.deleted_at IS NULL AND i.statut = 'inscrit' "
      'ORDER BY el.nom, el.prenoms',
      {'etab': etablissementId, 'annee': annee.id, 'debut': annee.debut, 'fin': annee.fin},
    );
    final parClasse = <String, List<EleveListe>>{};
    for (final l in eleves) {
      (parClasse[l['classe_id'] as String] ??= []).add(EleveListe(
        id: l['id'] as String,
        matricule: _s(l['matricule']),
        nom: l['nom'] as String,
        prenoms: l['prenoms'] as String,
        sexe: l['sexe'] as String,
        dateNaissance: _dn(l['date_naissance']),
        telephone: _s(l['telephone_contact']),
        derniereVisite: _dn(l['derniere_visite']),
        statutVisite: _s(l['statut_visite']),
      ));
    }
    return [
      for (final c in classes)
        ListeDeClasse(
          classeId: c['id'] as String,
          libelle: c['libelle'] as String,
          niveau: _s(c['niveau']),
          eleves: parClasse[c['id']] ?? const [],
        )
    ]..sort((a, b) => comparerClasses(a.libelle, b.libelle));
  }

  /// Toutes les classes de l'année (reconnaissance des listes importées).
  Future<List<ClasseConnue>> classesDeLAnnee(Annee annee) async => [
        for (final l in await depot.requete(
            'SELECT CAST(id AS text) AS id, CAST(etablissement_id AS text) AS etablissement_id, libelle, niveau FROM classe '
            'WHERE annee_scolaire_id = CAST(@annee AS uuid) AND deleted_at IS NULL',
            {'annee': annee.id}))
          ClasseConnue(
              id: l['id'] as String,
              etablissementId: l['etablissement_id'] as String,
              libelle: l['libelle'] as String,
              niveau: l['niveau'] as String?)
      ];

  /// Élèves de l'année, filtrés par établissement, classe ou texte (nom,
  /// prénoms, matricule). Sans filtre de classe ni d'établissement, la
  /// recherche porte aussi sur les élèves non inscrits cette année.
  Future<List<LigneEleve>> eleves(Annee annee, {String? etablissementId, String? classeId, String? texte, int limite = 500}) async {
    final conditions = <String>['el.deleted_at IS NULL'];
    final params = <String, Object?>{'annee': annee.id, 'debut': annee.debut, 'fin': annee.fin};
    if (classeId != null) {
      conditions.add('i.classe_id = CAST(@classe AS uuid)');
      params['classe'] = classeId;
    } else if (etablissementId != null) {
      conditions.add('c.etablissement_id = CAST(@etab AS uuid)');
      params['etab'] = etablissementId;
    }
    if (texte != null && texte.trim().isNotEmpty) {
      // Sans tenir compte des accents ni de la casse (« kone » trouve « KONÉ »).
      conditions.add("(sssu_sans_accents(lower(el.nom || ' ' || el.prenoms)) LIKE sssu_sans_accents(lower(@texte)) "
          "OR sssu_sans_accents(lower(el.prenoms || ' ' || el.nom)) LIKE sssu_sans_accents(lower(@texte)) "
          'OR el.matricule ILIKE @matricule)');
      params['texte'] = '%${texte.trim()}%';
      params['matricule'] = '%${normaliserMatricule(texte) ?? texte.trim()}%';
    }
    final r = await depot.requete(
      'SELECT el.id, el.matricule, el.nom, el.prenoms, el.sexe, el.date_naissance, i.id AS inscription_id, '
      'c.libelle AS classe, e.nom AS etablissement, dv.date_visite AS derniere_visite, dv.statut AS statut_visite '
      'FROM eleve el '
      'LEFT JOIN inscription i ON i.eleve_id = el.id AND i.annee_scolaire_id = CAST(@annee AS uuid) AND i.deleted_at IS NULL '
      'LEFT JOIN classe c ON c.id = i.classe_id '
      'LEFT JOIN etablissement e ON e.id = c.etablissement_id '
      'LEFT JOIN LATERAL (SELECT v.date_visite, v.statut FROM visite v WHERE v.eleve_id = el.id AND v.deleted_at IS NULL '
      'AND v.date_visite BETWEEN CAST(@debut AS date) AND CAST(@fin AS date) '
      'ORDER BY v.date_visite DESC, v.updated_at DESC LIMIT 1) dv ON TRUE '
      'WHERE ${conditions.join(' AND ')} ORDER BY el.nom, el.prenoms LIMIT $limite',
      params,
    );
    return [
      for (final l in r)
        LigneEleve(
          l['id'].toString(),
          _s(l['matricule']),
          l['nom'] as String,
          l['prenoms'] as String,
          l['sexe'] as String,
          _dn(l['date_naissance']),
          _s(l['inscription_id']),
          _s(l['classe']),
          _s(l['etablissement']),
          _dn(l['derniere_visite']),
          _s(l['statut_visite']),
        )
    ];
  }

  Future<List<LigneInscription>> inscriptions(String eleveId) async => [
        for (final l in await depot.requete(
          'SELECT i.id, a.libelle AS annee, c.id AS classe_id, c.libelle AS classe, e.nom AS etablissement, i.statut '
          'FROM inscription i JOIN annee_scolaire a ON a.id = i.annee_scolaire_id '
          'JOIN classe c ON c.id = i.classe_id JOIN etablissement e ON e.id = c.etablissement_id '
          'WHERE i.eleve_id = CAST(@eleve AS uuid) AND i.deleted_at IS NULL ORDER BY a.date_debut DESC',
          {'eleve': eleveId},
        ))
          LigneInscription(l['id'].toString(), l['annee'] as String, l['classe_id'].toString(), l['classe'] as String,
              l['etablissement'] as String, l['statut'] as String),
      ];

  Future<List<LigneVisite>> visites(String eleveId) async => [
        for (final l in await depot.requete(
          'SELECT v.id, v.date_visite, v.statut, v.conclusion, v.diagnostic, '
          "COALESCE(u.prenoms || ' ', '') || COALESCE(u.nom, '?') AS agent, "
          '(SELECT COUNT(*) FROM photo p WHERE p.visite_id = v.id AND p.deleted_at IS NULL) AS photos '
          'FROM visite v LEFT JOIN utilisateur u ON u.id = v.agent_id '
          'WHERE v.eleve_id = CAST(@eleve AS uuid) AND v.deleted_at IS NULL ORDER BY v.date_visite DESC, v.updated_at DESC',
          {'eleve': eleveId},
        ))
          LigneVisite(l['id'].toString(), _d(l['date_visite']), l['statut'] as String, _s(l['conclusion']),
              l['agent'] as String, _s(l['diagnostic']), _i(l['photos'])),
      ];

  /// Photographies de toutes les visites de l'élève (visites précédentes comprises).
  Future<List<LignePhoto>> photos(String eleveId) async => [
        for (final l in await depot.requete(
          'SELECT p.id, p.visite_id, v.date_visite, p.commentaire, pa.libelle AS pathologie, p.auteur_id, '
          "COALESCE(u.prenoms || ' ', '') || COALESCE(u.nom, '?') AS auteur, p.pris_le, p.statut_transfert "
          'FROM photo p JOIN visite v ON v.id = p.visite_id '
          'LEFT JOIN visite_pathologie vp ON vp.id = p.visite_pathologie_id '
          'LEFT JOIN pathologie pa ON pa.id = vp.pathologie_id '
          'LEFT JOIN utilisateur u ON u.id = p.auteur_id '
          'WHERE p.eleve_id = CAST(@eleve AS uuid) AND p.deleted_at IS NULL ORDER BY v.date_visite DESC, p.pris_le',
          {'eleve': eleveId},
        ))
          LignePhoto(
            l['id'].toString(),
            l['visite_id'].toString(),
            _d(l['date_visite']),
            _s(l['commentaire']),
            _s(l['pathologie']),
            l['auteur_id'].toString(),
            l['auteur'] as String,
            l['pris_le'] is DateTime ? formaterHorodatage(l['pris_le'] as DateTime) : l['pris_le'].toString(),
            l['statut_transfert'] as String,
          ),
      ];

  Future<Map<String, String>> libellesPathologies() async => {
        for (final l in await depot.requete('SELECT id, libelle FROM pathologie WHERE deleted_at IS NULL'))
          l['id'].toString(): l['libelle'] as String,
      };

  Future<Map<String, String>> nomsUtilisateurs() async => {
        for (final l in await depot.requete(
            "SELECT id, COALESCE(prenoms || ' ', '') || nom AS nom FROM utilisateur"))
          l['id'].toString(): l['nom'] as String,
      };

  Future<List<Map<String, dynamic>>> journalSynchronisations({int limite = 300}) => depot.requete(
        'SELECT j.debut, j.fin, j.canal, j.envoyes, j.recus, j.erreurs, j.detail, a.nom AS appareil, '
        "COALESCE(u.prenoms || ' ', '') || COALESCE(u.nom, '') AS utilisateur "
        'FROM journal_sync j JOIN appareil a ON a.id = j.appareil_id LEFT JOIN utilisateur u ON u.id = j.utilisateur_id '
        'ORDER BY j.debut DESC LIMIT $limite',
      );

  Future<List<Map<String, dynamic>>> journalAudit({String? action, String? utilisateurId, String? table, int limite = 500}) {
    final conditions = <String>['TRUE'];
    final params = <String, Object?>{};
    if (action != null) {
      conditions.add('j.action = @action');
      params['action'] = action;
    }
    if (utilisateurId != null) {
      conditions.add('j.utilisateur_id = CAST(@u AS uuid)');
      params['u'] = utilisateurId;
    }
    if (table != null) {
      conditions.add('j.table_cible = @table');
      params['table'] = table;
    }
    return depot.requete(
      'SELECT j.survenu_le, j.action, j.table_cible, CAST(j.enregistrement_id AS text) AS enregistrement_id, j.avant, j.apres, '
      "COALESCE(u.prenoms || ' ', '') || COALESCE(u.nom, '(appareil)') AS utilisateur, a.nom AS appareil "
      'FROM journal_audit j LEFT JOIN utilisateur u ON u.id = j.utilisateur_id LEFT JOIN appareil a ON a.id = j.appareil_id '
      'WHERE ${conditions.join(' AND ')} ORDER BY j.survenu_le DESC LIMIT $limite',
      params,
    );
  }

  Future<List<Map<String, dynamic>>> appareils() => depot.requete(
        'SELECT a.id, a.nom, a.modele, a.date_appairage, a.bloque, a.cle_publique IS NOT NULL AS appaire, '
        "COALESCE(u.prenoms || ' ', '') || COALESCE(u.nom, '') AS titulaire, "
        "COALESCE(string_agg(e.nom, ', ' ORDER BY e.nom), '') AS etablissements, "
        "COALESCE(array_agg(CAST(e.id AS text)) FILTER (WHERE e.id IS NOT NULL), '{}') AS etablissement_ids, "
        '(SELECT MAX(j.debut) FROM journal_sync j WHERE j.appareil_id = a.id) AS derniere_sync '
        'FROM appareil a LEFT JOIN utilisateur u ON u.id = a.titulaire_id '
        'LEFT JOIN appareil_etablissement ae ON ae.appareil_id = a.id AND ae.deleted_at IS NULL '
        'LEFT JOIN etablissement e ON e.id = ae.etablissement_id '
        'WHERE a.deleted_at IS NULL GROUP BY a.id, u.prenoms, u.nom ORDER BY a.nom',
      );
}
