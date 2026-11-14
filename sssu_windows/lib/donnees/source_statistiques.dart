/// Données des statistiques et des rapports, lues dans PostgreSQL (une
/// requête par table, sur l'année choisie), puis calculées en mémoire par
/// `calculerStatistiques` (paquet commun).
library;

import 'package:sssu_core/sssu_core.dart';

import 'depot_postgres.dart';
import 'requetes_poste.dart';

class SourceStatistiquesPoste {
  final DepotPostgres depot;
  SourceStatistiquesPoste(this.depot);

  /// Repère des données : change à chaque écriture (synchronisation d'un
  /// téléphone, saisie sur le poste). Sert à rafraîchir les écrans.
  Future<int> repere() async {
    final r = await depot.requete('SELECT COALESCE(MAX(seq), 0) AS s FROM sync_changement');
    return (r.single['s'] as num).toInt();
  }

  /// [identite] : noms, matricules, diagnostics… (listes nominatives seulement).
  Future<JeuStatistiques> charger(Annee annee, {bool identite = false}) async {
    final p = {'annee': annee.id, 'debut': annee.debut, 'fin': annee.fin};
    Future<List<Map<String, Object?>>> q(String sql, [Map<String, Object?> params = const {}]) async =>
        [for (final l in await depot.requete(sql, params)) Map<String, Object?>.from(l)];
    const periode = 'CAST(@debut AS date) AND CAST(@fin AS date)';
    return JeuStatistiques.depuisLignes(
      annee: AnneeStat(annee.id, annee.libelle, lireDate(annee.debut), lireDate(annee.fin)),
      identite: identite,
      etablissements: await q('SELECT CAST(id AS text) AS id, nom, deleted_at FROM etablissement'),
      classes: await q(
          'SELECT CAST(id AS text) AS id, libelle, niveau, CAST(etablissement_id AS text) AS etablissement_id, '
          'CAST(annee_scolaire_id AS text) AS annee_scolaire_id, deleted_at FROM classe '
          'WHERE annee_scolaire_id = CAST(@annee AS uuid)',
          p),
      inscriptions: await q(
          'SELECT CAST(eleve_id AS text) AS eleve_id, CAST(classe_id AS text) AS classe_id, statut, deleted_at '
          'FROM inscription WHERE annee_scolaire_id = CAST(@annee AS uuid)',
          p),
      eleves: await q(
          'SELECT CAST(el.id AS text) AS id, el.sexe, el.date_naissance, el.deleted_at'
          '${identite ? ', el.nom, el.prenoms, el.matricule, el.telephone_contact' : ''} '
          'FROM eleve el WHERE EXISTS (SELECT 1 FROM inscription i WHERE i.eleve_id = el.id '
          'AND i.annee_scolaire_id = CAST(@annee AS uuid))',
          p),
      visites: await q(
          'SELECT CAST(id AS text) AS id, CAST(eleve_id AS text) AS eleve_id, date_visite, statut, type_visite, conclusion, '
          'aptitude, deleted_at${identite ? ', diagnostic, structure_reference, date_controle, aptitude_restrictions' : ''} '
          'FROM visite WHERE date_visite BETWEEN $periode',
          p),
      visitePathologies: await q(
          'SELECT CAST(vp.visite_id AS text) AS visite_id, CAST(vp.pathologie_id AS text) AS pathologie_id, vp.deleted_at '
          'FROM visite_pathologie vp JOIN visite v ON v.id = vp.visite_id WHERE v.date_visite BETWEEN $periode',
          p),
      pathologies: await q('SELECT CAST(id AS text) AS id, libelle, ordre, deleted_at FROM pathologie'),
      criteres: await q('SELECT CAST(id AS text) AS id, libelle, deleted_at FROM critere_inspection'),
      inspections: await q(
          'SELECT CAST(id AS text) AS id, CAST(etablissement_id AS text) AS etablissement_id, date_inspection, statut, '
          'taux_conformite, niveau, nb_conformes, nb_partiels, nb_non_conformes, nb_non_applicables, deleted_at '
          'FROM inspection WHERE annee_scolaire_id = CAST(@annee AS uuid)',
          p),
      reponsesInspection: await q(
          'SELECT CAST(r.inspection_id AS text) AS inspection_id, CAST(r.critere_id AS text) AS critere_id, r.resultat, '
          'r.deleted_at FROM inspection_reponse r JOIN inspection i ON i.id = r.inspection_id '
          'WHERE i.annee_scolaire_id = CAST(@annee AS uuid)',
          p),
    );
  }

  /// Inspections (non ébauches) pour la page d'historique, la plus récente d'abord.
  Future<List<Map<String, dynamic>>> inspections({String? etablissementId}) => depot.requete(
        'SELECT CAST(i.id AS text) AS id, CAST(i.etablissement_id AS text) AS etablissement_id, e.nom AS etablissement, '
        'i.date_inspection, i.statut, i.taux_conformite, i.niveau, i.nb_conformes, i.nb_partiels, i.nb_non_conformes, '
        'i.nb_non_applicables, a.libelle AS annee, (i.grille IS NOT NULL) AS grille, '
        "COALESCE(u.nom || COALESCE(' ' || u.prenoms, ''), '') AS inspecteur, "
        '(SELECT COUNT(*) FROM inspection_photo p JOIN inspection_reponse r ON r.id = p.inspection_reponse_id '
        'WHERE r.inspection_id = i.id AND p.deleted_at IS NULL) AS photos '
        'FROM inspection i JOIN etablissement e ON e.id = i.etablissement_id '
        'JOIN annee_scolaire a ON a.id = i.annee_scolaire_id LEFT JOIN utilisateur u ON u.id = i.inspecteur_id '
        "WHERE i.deleted_at IS NULL AND i.statut <> 'ebauche' "
        '${etablissementId == null ? '' : 'AND i.etablissement_id = CAST(@etab AS uuid) '}'
        'ORDER BY i.date_inspection DESC, e.nom',
        {if (etablissementId != null) 'etab': etablissementId},
      );

  /// Grille complète (critères actifs et désactivés).
  Future<List<CritereGrille>> grille() async => [
        for (final l in await depot.requete('SELECT CAST(id AS text) AS id, rubrique, code, libelle, ordre, actif '
            'FROM critere_inspection WHERE deleted_at IS NULL ORDER BY rubrique, ordre, libelle'))
          CritereGrille.depuisDonnees(l['id'] as String, Map<String, Object?>.from(l))
      ];

  /// Paramètres (clé → valeur).
  Future<Map<String, String?>> parametres() async => {
        for (final l in await depot.requete('SELECT cle, valeur FROM parametre WHERE deleted_at IS NULL'))
          l['cle'] as String: l['valeur'] as String?
      };
}
