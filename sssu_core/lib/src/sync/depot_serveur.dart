/// Accès aux données du poste central. Deux implémentations :
/// PostgreSQL (application Windows) et mémoire (tests automatiques).
/// La logique de synchronisation ne dépend que de cette interface.
library;

import 'enregistrement.dart';

/// Motif d'un changement diffusé aux téléphones (`sync_changement.motif`).
abstract final class MotifsChangement {
  static const resolutionConflit = 'resolution_conflit';
}

class Changement {
  final int seq;
  final Enregistrement enregistrement;
  final String? motif;
  const Changement(this.seq, this.enregistrement, {this.motif});
}

abstract class TransactionServeur {
  Future<Enregistrement?> lire(String table, String id);

  /// Crée ou remplace l'enregistrement. Si la table est diffusée aux
  /// téléphones ou rattachée à un établissement, un changement est ajouté au
  /// journal (`sync_changement`) avec l'établissement comme portée ; seules
  /// les tables demandées sont ensuite transmises aux téléphones.
  Future<void> ecrire(Enregistrement e, {String? motifChangement});

  /// Enregistrements non supprimés dont les colonnes valent les valeurs données.
  Future<List<Enregistrement>> chercher(String table, Map<String, Object?> egalites);

  /// Enregistrements non supprimés de [table] rattachés à l'établissement
  /// (dernière portée connue), pour rediffuser ses données à un téléphone
  /// nouvellement affecté.
  Future<List<Enregistrement>> parPortee(String table, String etablissementId);

  /// Changements postérieurs à [curseur], pour les [tables] demandées,
  /// limités aux référentiels communs et aux [etablissements] indiqués.
  Future<List<Changement>> changementsDepuis(
    int curseur, {
    required Set<String> tables,
    required Set<String> etablissements,
    required int limite,
  });
}

abstract class DepotServeur {
  /// Exécute [action] dans une transaction : tout est enregistré, ou rien.
  Future<T> transaction<T>(Future<T> Function(TransactionServeur tx) action);

  /// Génération des données, renouvelée à chaque restauration de sauvegarde
  /// (voir `ReponseJeton.generation`).
  Future<String> generation();
}
