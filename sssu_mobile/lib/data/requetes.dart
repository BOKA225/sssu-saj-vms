/// Requêtes de consultation de la base du téléphone (établissements, classes,
/// effectifs, élèves, visites, ébauches).
library;

import 'package:drift/drift.dart';
import 'package:sssu_core/sssu_core.dart';

import 'base_locale.dart';
import 'conversion_sql.dart';

class AnneeCourante {
  final String id;
  final String libelle;
  final String debut;
  final String fin;
  const AnneeCourante(this.id, this.libelle, this.debut, this.fin);
}

class ResumeEtablissement {
  final String id;
  final String nom;
  final String code;
  final TypeEtablissement type;
  final StatutEtablissement statut;
  final String? localite;
  final int classes;
  final int effectif;
  final int examines;
  const ResumeEtablissement(this.id, this.nom, this.code, this.type, this.statut, this.localite, this.classes,
      this.effectif, this.examines);

  double get couverture => effectif == 0 ? 0 : examines / effectif;
}

class ResumeClasse {
  final String id;
  final String libelle;
  final String? niveau;
  final String etablissementId;
  final String anneeScolaireId;
  final int effectif;
  final int garcons;
  final int filles;
  final int examines;
  const ResumeClasse(this.id, this.libelle, this.niveau, this.etablissementId, this.anneeScolaireId, this.effectif,
      this.garcons, this.filles, this.examines);
}

class ResumeVisite {
  final String id;
  final String date;
  final StatutVisite statut;
  final EtatSync etat;
  final String? conclusion;
  final String agentId;
  const ResumeVisite(this.id, this.date, this.statut, this.etat, this.conclusion, this.agentId);

  String get libelleStatut => statutAffiche(statut, etat);
}

class LigneEleve {
  final Eleve eleve;
  final String? inscriptionId;
  final String? classeId;
  final String? classeLibelle;
  final String? etablissementId;
  final String? etablissementNom;

  /// Dernière visite de l'année scolaire, s'il y en a une.
  final ResumeVisite? derniereVisite;

  const LigneEleve(this.eleve, this.inscriptionId, this.classeId, this.classeLibelle, this.etablissementId,
      this.etablissementNom, this.derniereVisite);

  bool get examine => derniereVisite != null && derniereVisite!.statut != StatutVisite.ebauche;
}

class EbaucheVisite {
  final String visiteId;
  final String date;
  final StatutVisite statut;
  final String eleveId;
  final String eleveNom;
  final String? classeLibelle;
  const EbaucheVisite(this.visiteId, this.date, this.statut, this.eleveId, this.eleveNom, this.classeLibelle);
}

class Pathologie {
  final String id;
  final String code;
  final String libelle;
  final bool precisionRequise;
  const Pathologie(this.id, this.code, this.libelle, this.precisionRequise);
}

class Requetes {
  final BaseLocale db;
  Requetes(this.db);

  Future<List<QueryRow>> _q(String sql, [List<Object?> args = const []]) =>
      db.customSelect(sql, variables: [for (final a in args) variable(a)]).get();

  /// Année scolaire active (à défaut, la plus récente).
  Future<AnneeCourante?> anneeCourante() async {
    final r = await _q('SELECT id, libelle, date_debut, date_fin FROM annee_scolaire WHERE deleted_at IS NULL '
        'ORDER BY active DESC, date_debut DESC LIMIT 1');
    if (r.isEmpty) return null;
    final l = r.first;
    return AnneeCourante(
        l.read<String>('id'), l.read<String>('libelle'), l.read<String>('date_debut'), l.read<String>('date_fin'));
  }

  /// Sous-requête : élève examiné pendant l'année (visite autre qu'une ébauche).
  static const _examine = 'EXISTS (SELECT 1 FROM visite v WHERE v.eleve_id = i.eleve_id AND v.deleted_at IS NULL '
      "AND v.statut <> 'ebauche' AND v.date_visite BETWEEN ? AND ?)";

  Future<List<ResumeEtablissement>> etablissements(AnneeCourante a) async {
    final r = await _q(
      'SELECT e.id, e.nom, e.code, e.type, e.statut, e.localite, '
      '(SELECT COUNT(*) FROM classe c WHERE c.etablissement_id = e.id AND c.annee_scolaire_id = ? AND c.deleted_at IS NULL) AS nb_classes, '
      '(SELECT COUNT(*) FROM inscription i JOIN classe c ON c.id = i.classe_id WHERE c.etablissement_id = e.id '
      "AND i.annee_scolaire_id = ? AND i.deleted_at IS NULL AND i.statut = 'inscrit') AS effectif, "
      '(SELECT COUNT(*) FROM inscription i JOIN classe c ON c.id = i.classe_id WHERE c.etablissement_id = e.id '
      "AND i.annee_scolaire_id = ? AND i.deleted_at IS NULL AND i.statut = 'inscrit' AND $_examine) AS examines "
      'FROM etablissement e WHERE e.deleted_at IS NULL ORDER BY e.nom',
      [a.id, a.id, a.id, a.debut, a.fin],
    );
    return [
      for (final l in r)
        ResumeEtablissement(
          l.read<String>('id'),
          l.read<String>('nom'),
          l.read<String>('code'),
          TypeEtablissement.depuisCode(l.read<String>('type')),
          StatutEtablissement.depuisCode(l.read<String>('statut')),
          l.readNullable<String>('localite'),
          l.read<int>('nb_classes'),
          l.read<int>('effectif'),
          l.read<int>('examines'),
        )
    ];
  }

  Future<List<ResumeClasse>> classes(String etablissementId, AnneeCourante a) async {
    final r = await _q(
      'SELECT c.id, c.libelle, c.niveau, c.etablissement_id, c.annee_scolaire_id, '
      "COUNT(i.id) AS effectif, SUM(CASE WHEN el.sexe = 'M' THEN 1 ELSE 0 END) AS garcons, "
      "SUM(CASE WHEN el.sexe = 'F' THEN 1 ELSE 0 END) AS filles, "
      'SUM(CASE WHEN i.id IS NOT NULL AND $_examine THEN 1 ELSE 0 END) AS examines '
      'FROM classe c '
      "LEFT JOIN inscription i ON i.classe_id = c.id AND i.deleted_at IS NULL AND i.statut = 'inscrit' "
      'LEFT JOIN eleve el ON el.id = i.eleve_id '
      'WHERE c.etablissement_id = ? AND c.annee_scolaire_id = ? AND c.deleted_at IS NULL '
      'GROUP BY c.id ORDER BY c.niveau, c.libelle',
      [a.debut, a.fin, etablissementId, a.id],
    );
    return [
      for (final l in r)
        ResumeClasse(
          l.read<String>('id'),
          l.read<String>('libelle'),
          l.readNullable<String>('niveau'),
          l.read<String>('etablissement_id'),
          l.read<String>('annee_scolaire_id'),
          l.read<int>('effectif'),
          l.readNullable<int>('garcons') ?? 0,
          l.readNullable<int>('filles') ?? 0,
          l.readNullable<int>('examines') ?? 0,
        )
    ];
  }

  static const _selectEleve = 'SELECT el.*, i.id AS inscription_id, c.id AS classe_id, c.libelle AS classe_libelle, '
      'e.id AS etab_id, e.nom AS etab_nom, '
      '(SELECT v.id FROM visite v WHERE v.eleve_id = el.id AND v.deleted_at IS NULL AND v.date_visite BETWEEN ? AND ? '
      'ORDER BY v.date_visite DESC, v.updated_at DESC LIMIT 1) AS visite_id '
      'FROM eleve el '
      "LEFT JOIN inscription i ON i.eleve_id = el.id AND i.annee_scolaire_id = ? AND i.deleted_at IS NULL "
      'LEFT JOIN classe c ON c.id = i.classe_id '
      'LEFT JOIN etablissement e ON e.id = c.etablissement_id ';

  Future<List<LigneEleve>> _eleves(String where, List<Object?> args, AnneeCourante a, {int limite = 500}) async {
    final r = await _q('$_selectEleve WHERE el.deleted_at IS NULL AND $where ORDER BY el.nom, el.prenoms LIMIT $limite',
        [a.debut, a.fin, a.id, ...args]);
    final spec = registreParNom['eleve']!;
    final resultat = <LigneEleve>[];
    for (final l in r) {
      final e = lireLigne(spec, l.data);
      final visiteId = l.readNullable<String>('visite_id');
      resultat.add(LigneEleve(
        Eleve.depuisDonnees(e.id, e.donnees),
        l.readNullable<String>('inscription_id'),
        l.readNullable<String>('classe_id'),
        l.readNullable<String>('classe_libelle'),
        l.readNullable<String>('etab_id'),
        l.readNullable<String>('etab_nom'),
        visiteId == null ? null : await resumeVisite(visiteId),
      ));
    }
    return resultat;
  }

  Future<List<LigneEleve>> elevesDeClasse(String classeId, AnneeCourante a) =>
      _eleves("i.classe_id = ? AND i.statut = 'inscrit'", [classeId], a);

  /// Recherche rapide par nom, prénoms ou matricule (sans tenir compte des accents ni de la casse
  /// pour le matricule ; le nom est stocké en majuscules).
  Future<List<LigneEleve>> rechercher(String texte, AnneeCourante a) {
    final t = texte.trim();
    if (t.length < 2) return Future.value(const []);
    final motif = '%${t.toUpperCase()}%';
    return _eleves("(UPPER(el.nom) LIKE ? OR UPPER(el.prenoms) LIKE ? OR UPPER(el.nom || ' ' || el.prenoms) LIKE ? "
        'OR el.matricule LIKE ?)', [motif, motif, motif, '%${normaliserMatricule(t) ?? t}%'], a, limite: 50);
  }

  Future<LigneEleve?> eleve(String eleveId, AnneeCourante a) async {
    final r = await _eleves('el.id = ?', [eleveId], a);
    return r.isEmpty ? null : r.first;
  }

  Future<ResumeVisite?> resumeVisite(String visiteId) async {
    final r = await _q(
        'SELECT id, date_visite, statut, sync_status, conclusion, agent_id FROM visite WHERE id = ?', [visiteId]);
    if (r.isEmpty) return null;
    final l = r.first;
    return ResumeVisite(
      l.read<String>('id'),
      l.read<String>('date_visite'),
      StatutVisite.depuisCode(l.read<String>('statut')),
      EtatSync.depuisCode(l.read<String>('sync_status')),
      l.readNullable<String>('conclusion'),
      l.read<String>('agent_id'),
    );
  }

  Future<List<ResumeVisite>> visitesDeEleve(String eleveId) async {
    final r = await _q(
        'SELECT id FROM visite WHERE eleve_id = ? AND deleted_at IS NULL ORDER BY date_visite DESC, updated_at DESC',
        [eleveId]);
    return [for (final l in r) (await resumeVisite(l.read<String>('id')))!];
  }

  /// Visites non transmises (ébauches et visites enregistrées localement).
  Future<List<EbaucheVisite>> ebauches({String? agentId}) async {
    final r = await _q(
      'SELECT v.id, v.date_visite, v.statut, el.id AS eleve_id, el.nom, el.prenoms, c.libelle AS classe '
      'FROM visite v JOIN eleve el ON el.id = v.eleve_id '
      'LEFT JOIN inscription i ON i.id = v.inscription_id LEFT JOIN classe c ON c.id = i.classe_id '
      "WHERE v.deleted_at IS NULL AND v.statut IN ('ebauche', 'enregistre') "
      '${agentId == null ? '' : 'AND v.agent_id = ? '}'
      'ORDER BY v.updated_at DESC',
      [if (agentId != null) agentId],
    );
    return [
      for (final l in r)
        EbaucheVisite(
          l.read<String>('id'),
          l.read<String>('date_visite'),
          StatutVisite.depuisCode(l.read<String>('statut')),
          l.read<String>('eleve_id'),
          '${l.read<String>('nom')} ${l.read<String>('prenoms')}',
          l.readNullable<String>('classe'),
        )
    ];
  }

  Future<List<Pathologie>> pathologies() async {
    final r = await _q('SELECT id, code, libelle, precision_requise FROM pathologie '
        'WHERE deleted_at IS NULL AND active = 1 ORDER BY ordre, libelle');
    return [
      for (final l in r)
        Pathologie(l.read<String>('id'), l.read<String>('code'), l.read<String>('libelle'),
            l.read<int>('precision_requise') != 0)
    ];
  }

  /// Identités de tous les élèves du téléphone (contrôle des doublons à l'importation).
  Future<List<IdentiteEleve>> identitesEleves() async {
    final r = await _q('SELECT id, matricule, nom, prenoms, date_naissance FROM eleve WHERE deleted_at IS NULL');
    return [
      for (final l in r)
        IdentiteEleve(
          id: l.read<String>('id'),
          matricule: l.readNullable<String>('matricule'),
          nom: l.read<String>('nom'),
          prenoms: l.read<String>('prenoms'),
          dateNaissance:
              l.readNullable<String>('date_naissance') == null ? null : lireDate(l.read<String>('date_naissance')),
        )
    ];
  }

  Future<String?> parametre(String cle) async {
    final r = await _q('SELECT valeur FROM parametre WHERE cle = ? AND deleted_at IS NULL', [cle]);
    return r.isEmpty ? null : r.first.readNullable<String>('valeur');
  }

  // ------------------------------------------------------------ statistiques

  Future<List<Map<String, Object?>>> _lignes(String sql, [List<Object?> args = const []]) async =>
      [for (final l in await _q(sql, args)) l.data];

  /// Données de l'appareil pour les statistiques simplifiées : établissements
  /// affectés, classes et élèves de l'année, visites et inspections présentes
  /// sur le téléphone (aucune donnée nominative).
  Future<JeuStatistiques?> jeuStatistiques() async {
    final a = await anneeCourante();
    if (a == null) return null;
    return JeuStatistiques.depuisLignes(
      annee: AnneeStat(a.id, a.libelle, lireDate(a.debut), lireDate(a.fin)),
      etablissements: await _lignes('SELECT id, nom, deleted_at FROM etablissement'),
      classes: await _lignes('SELECT id, libelle, niveau, etablissement_id, annee_scolaire_id, deleted_at FROM classe '
          'WHERE annee_scolaire_id = ?', [a.id]),
      inscriptions: await _lignes('SELECT eleve_id, classe_id, statut, deleted_at FROM inscription '
          'WHERE annee_scolaire_id = ?', [a.id]),
      eleves: await _lignes('SELECT id, sexe, date_naissance, deleted_at FROM eleve'),
      visites: await _lignes('SELECT id, eleve_id, date_visite, statut, conclusion, deleted_at FROM visite '
          'WHERE date_visite BETWEEN ? AND ?', [a.debut, a.fin]),
      visitePathologies: await _lignes('SELECT vp.visite_id, vp.pathologie_id, vp.deleted_at FROM visite_pathologie vp '
          'JOIN visite v ON v.id = vp.visite_id WHERE v.date_visite BETWEEN ? AND ?', [a.debut, a.fin]),
      pathologies: await _lignes('SELECT id, libelle, ordre, deleted_at FROM pathologie'),
      criteres: await _lignes('SELECT id, libelle, deleted_at FROM critere_inspection'),
      inspections: await _lignes(
          'SELECT id, etablissement_id, date_inspection, statut, taux_conformite, niveau, nb_conformes, nb_partiels, '
          'nb_non_conformes, nb_non_applicables, deleted_at FROM inspection WHERE annee_scolaire_id = ?', [a.id]),
      reponsesInspection: await _lignes('SELECT r.inspection_id, r.critere_id, r.resultat, r.deleted_at '
          'FROM inspection_reponse r JOIN inspection i ON i.id = r.inspection_id WHERE i.annee_scolaire_id = ?', [a.id]),
    );
  }
}
