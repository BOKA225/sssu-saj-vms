/// Enregistrement du dossier de visite dans la base du téléphone : visite,
/// antécédents, examens par appareil et pathologies dépistées.
library;

import 'package:collection/collection.dart';
import 'package:sssu_core/sssu_core.dart';

import '../data/base_locale.dart';
import '../data/depot_local_drift.dart';

const _egal = DeepCollectionEquality();

/// Formulaire + identifiants des enregistrements déjà créés pour lui.
class DossierVisite {
  final FormulaireVisite formulaire;

  /// Établissement de rattachement (diffusion et contrôle sur le poste central).
  final String? etablissementId;
  final Map<TypeAntecedent, String> idsAntecedents = {};
  final Map<AppareilExamen, String> idsExamens = {};

  /// Pathologie → identifiant de la ligne `visite_pathologie`.
  final Map<String, String> idsPathologies = {};

  /// Statut de synchronisation de la visite elle-même.
  EtatSync etat = EtatSync.local;

  DossierVisite(this.formulaire, this.etablissementId);

  bool get transmise => !formulaire.modifiable;
}

class DepotVisite {
  final BaseLocale db;
  final DepotLocalDrift depot;
  DepotVisite(this.db, this.depot);

  /// Nouvelle visite pour l'élève, avec les antécédents repris de sa visite
  /// précédente (ils restent modifiables).
  Future<DossierVisite> nouvelle({
    required String eleveId,
    required String? inscriptionId,
    required String? etablissementId,
    required Utilisateur agent,
    required DateTime date,
  }) async {
    final f = FormulaireVisite(
      eleveId: eleveId,
      inscriptionId: inscriptionId,
      agentId: agent.id,
      appareilId: depot.appareilId,
      dateVisite: date,
      structureOrigine: agent.structure,
    );
    final precedentes = await depot.chercher('antecedent', {'eleve_id': eleveId});
    if (precedentes.isNotEmpty) {
      // Antécédents de la visite la plus récente.
      final derniereVisite = precedentes.last.donnees['visite_id'];
      for (final a in precedentes.where((a) => a.donnees['visite_id'] == derniereVisite)) {
        final type = TypeAntecedent.depuisCode(a.donnees['type']! as String);
        f.antecedents[type] = ReponseAntecedent(
          coche: a.donnees['coche'] == true,
          commentaire: (a.donnees['commentaire'] as String?) ?? '',
        );
      }
    }
    return DossierVisite(f, etablissementId);
  }

  Future<DossierVisite> charger(String visiteId) async {
    final v = await depot.lire('visite', visiteId);
    if (v == null || v.supprime) throw StateError('Visite introuvable.');
    final f = FormulaireVisite(
      id: v.id,
      eleveId: v.donnees['eleve_id']! as String,
      inscriptionId: v.donnees['inscription_id'] as String?,
      agentId: v.donnees['agent_id']! as String,
      appareilId: v.donnees['appareil_id'] as String?,
      dateVisite: lireDate(v.donnees['date_visite']! as String),
    )..chargerVisite(v.donnees);
    final d = DossierVisite(f, v.etablissementId)..etat = (await depot.etat('visite', visiteId))!;
    for (final a in await depot.chercher('antecedent', {'visite_id': visiteId})) {
      final t = TypeAntecedent.depuisCode(a.donnees['type']! as String);
      f.antecedents[t] = ReponseAntecedent(
          coche: a.donnees['coche'] == true, commentaire: (a.donnees['commentaire'] as String?) ?? '');
      d.idsAntecedents[t] = a.id;
    }
    for (final e in await depot.chercher('examen_appareil', {'visite_id': visiteId})) {
      final ap = AppareilExamen.depuisCode(e.donnees['appareil']! as String);
      f.examens[ap] = ReponseExamen(
        resultat: ResultatExamen.depuisCode(e.donnees['resultat']! as String),
        observation: (e.donnees['observation'] as String?) ?? '',
      );
      d.idsExamens[ap] = e.id;
    }
    for (final p in await depot.chercher('visite_pathologie', {'visite_id': visiteId})) {
      final pid = p.donnees['pathologie_id']! as String;
      f.pathologies[pid] = (p.donnees['precision'] as String?) ?? '';
      d.idsPathologies[pid] = p.id;
    }
    return d;
  }

  /// Enregistre le dossier. Tant que la visite est une ébauche ou est
  /// « enregistrée localement », rien n'est transmis ; ensuite chaque
  /// modification est mise en attente de synchronisation.
  Future<void> enregistrer(
    DossierVisite d, {
    required String utilisateurId,
    InterpretationImc? interpretation,
    String? validateurId,
    DateTime? valideLe,
  }) async {
    final f = d.formulaire;
    final aTransmettre = !f.modifiable;
    await db.transaction(() async {
      final donnees = f.donneesVisite(interpretation: interpretation, validateurId: validateurId, valideLe: valideLe);
      if (f.id == null) {
        final v = await depot.creer('visite', donnees,
            utilisateurId: utilisateurId, etablissementId: d.etablissementId, aTransmettre: aTransmettre);
        f.id = v.id;
      } else {
        await _majSiChange('visite', f.id!, donnees, utilisateurId, aTransmettre);
      }
      final visiteId = f.id!;

      for (final t in TypeAntecedent.values) {
        final r = f.antecedents[t]!;
        await _synchroniserEnfant(
          table: 'antecedent',
          ids: d.idsAntecedents,
          cle: t,
          present: r.renseigne,
          donnees: {
            'visite_id': visiteId,
            'eleve_id': f.eleveId,
            'type': t.code,
            'coche': r.coche,
            'commentaire': r.commentaire.trim().isEmpty ? null : r.commentaire.trim(),
          },
          d: d,
          utilisateurId: utilisateurId,
          aTransmettre: aTransmettre,
        );
      }
      for (final a in AppareilExamen.values) {
        final r = f.examens[a]!;
        await _synchroniserEnfant(
          table: 'examen_appareil',
          ids: d.idsExamens,
          cle: a,
          present: r.resultat != ResultatExamen.nonExamine || r.observation.trim().isNotEmpty,
          donnees: {
            'visite_id': visiteId,
            'appareil': a.code,
            'resultat': r.resultat.code,
            'observation': r.observation.trim().isEmpty ? null : r.observation.trim(),
          },
          d: d,
          utilisateurId: utilisateurId,
          aTransmettre: aTransmettre,
        );
      }
      final toutes = {...d.idsPathologies.keys, ...f.pathologies.keys};
      for (final pid in toutes) {
        final present = f.pathologies.containsKey(pid);
        if (!present && d.idsPathologies[pid] != null) {
          // Les photos liées à cette pathologie restent dans le dossier, sans lien.
          for (final ph in await depot.chercher('photo', {'visite_pathologie_id': d.idsPathologies[pid]})) {
            await _majSiChange('photo', ph.id, {...ph.donnees, 'visite_pathologie_id': null}, utilisateurId,
                aTransmettre);
          }
        }
        final precision = f.pathologies[pid]?.trim() ?? '';
        await _synchroniserEnfant(
          table: 'visite_pathologie',
          ids: d.idsPathologies,
          cle: pid,
          present: present,
          donnees: {'visite_id': visiteId, 'pathologie_id': pid, 'precision': precision.isEmpty ? null : precision},
          d: d,
          utilisateurId: utilisateurId,
          aTransmettre: aTransmettre,
        );
      }
    });
    d.etat = (await depot.etat('visite', f.id!))!;
  }

  Future<void> _synchroniserEnfant<K>({
    required String table,
    required Map<K, String> ids,
    required K cle,
    required bool present,
    required Map<String, Object?> donnees,
    required DossierVisite d,
    required String utilisateurId,
    required bool aTransmettre,
  }) async {
    final id = ids[cle];
    if (present) {
      if (id == null) {
        final e = await depot.creer(table, donnees,
            utilisateurId: utilisateurId, etablissementId: d.etablissementId, aTransmettre: aTransmettre);
        ids[cle] = e.id;
      } else {
        await _majSiChange(table, id, donnees, utilisateurId, aTransmettre);
      }
    } else if (id != null) {
      await depot.supprimer(table, id, utilisateurId: utilisateurId);
      ids.remove(cle);
    }
  }

  Future<void> _majSiChange(
      String table, String id, Map<String, Object?> donnees, String utilisateurId, bool aTransmettre) async {
    final actuel = await depot.lire(table, id);
    if (actuel == null) return;
    final fusion = {...actuel.donnees, ...donnees};
    final etat = await depot.etat(table, id);
    final dejaATransmettre = etat == EtatSync.local && aTransmettre;
    if (_egal.equals(fusion, actuel.donnees) && !dejaATransmettre) return;
    await depot.modifier(table, id, donnees, utilisateurId: utilisateurId, aTransmettre: aTransmettre);
  }

  /// « Valider et synchroniser » : la visite passe « en attente » avec tous
  /// ses éléments (antécédents, examens, pathologies, consentement, photos).
  Future<void> transmettre(DossierVisite d, {required String utilisateurId, InterpretationImc? interpretation}) async {
    d.formulaire.statut = StatutVisite.enAttente;
    await enregistrer(d, utilisateurId: utilisateurId, interpretation: interpretation);
    await _rendreTransmissibles(d.formulaire.id!);
    d.etat = (await depot.etat('visite', d.formulaire.id!))!;
  }

  /// Validation médicale depuis le téléphone (droit `visite.valider`).
  Future<void> valider(DossierVisite d, {required String medecinId, InterpretationImc? interpretation}) async {
    d.formulaire.statut = StatutVisite.valide;
    await enregistrer(d,
        utilisateurId: medecinId,
        interpretation: interpretation,
        validateurId: medecinId,
        valideLe: DateTime.now().toUtc());
    await _rendreTransmissibles(d.formulaire.id!);
  }

  Future<void> _rendreTransmissibles(String visiteId) async {
    await depot.rendreTransmissible('visite', visiteId);
    for (final table in ['antecedent', 'examen_appareil', 'visite_pathologie', 'consentement', 'photo']) {
      for (final e in await depot.chercher(table, {'visite_id': visiteId})) {
        await depot.rendreTransmissible(table, e.id);
      }
    }
  }

  /// Supprime une ébauche jamais transmise (et ses éléments).
  Future<void> supprimerEbauche(
    DossierVisite d, {
    required String utilisateurId,
    Future<void> Function(String chemin)? supprimerFichier,
  }) async {
    final id = d.formulaire.id;
    if (id == null) return;
    if (!d.formulaire.modifiable) throw StateError('Une visite transmise ne peut pas être supprimée ici.');
    await db.transaction(() async {
      for (final table in ['photo', 'consentement', 'visite_pathologie', 'examen_appareil', 'antecedent']) {
        for (final e in await depot.chercher(table, {'visite_id': id})) {
          if (table == 'photo' && supprimerFichier != null) await supprimerFichier(e.donnees['chemin_chiffre']! as String);
          await depot.supprimer(table, e.id, utilisateurId: utilisateurId);
        }
      }
      await depot.supprimer('visite', id, utilisateurId: utilisateurId);
    });
  }
}
