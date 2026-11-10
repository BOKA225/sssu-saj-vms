/// Description des tables utilisée par la synchronisation générique.
library;

/// Types logiques des colonnes. La valeur canonique (celle qui circule en JSON
/// entre téléphones et poste central) est indiquée pour chaque type.
enum TypeColonne {
  /// Chaîne UUID.
  uuid,

  /// Chaîne.
  text,

  /// Entier.
  entier,

  /// Nombre décimal.
  reel,

  /// Booléen.
  booleen,

  /// Chaîne ISO 8601 en UTC, par exemple `2026-11-10T08:00:00.000Z`.
  horodatage,

  /// Chaîne `AAAA-MM-JJ`.
  date,

  /// Objet ou liste JSON.
  json,

  /// Chaîne base64.
  binaire,
}

class Colonne {
  final String nom;
  final TypeColonne type;
  final bool obligatoire;

  /// La base fournit une valeur par défaut : la colonne peut être omise à la création.
  final bool aValeurParDefaut;

  const Colonne(this.nom, this.type, {this.obligatoire = false, this.aValeurParDefaut = false});
}

class TableSpec {
  final String nom;
  final bool surMobile;
  final bool surServeur;

  /// Le téléphone peut créer ou modifier des enregistrements de cette table.
  final bool envoiParTelephone;

  /// Le téléphone reçoit les enregistrements de cette table.
  final bool receptionParTelephone;

  /// Les enregistrements appartiennent à un établissement (diffusion limitée
  /// aux téléphones affectés à cet établissement).
  final bool parEtablissement;

  /// Ordre d'envoi : un parent est toujours envoyé avant ses enfants.
  final int ordreEnvoi;

  /// Combinaisons de colonnes qui doivent rester uniques sur le poste central.
  final List<List<String>> clesNaturelles;

  /// Colonnes métier (hors colonnes communes de synchronisation).
  final List<Colonne> colonnes;

  const TableSpec({
    required this.nom,
    required this.surMobile,
    required this.surServeur,
    required this.envoiParTelephone,
    required this.receptionParTelephone,
    required this.parEtablissement,
    required this.ordreEnvoi,
    required this.clesNaturelles,
    required this.colonnes,
  });

  Colonne? colonne(String nom) {
    for (final c in colonnes) {
      if (c.nom == nom) return c;
    }
    return null;
  }

  Set<String> get nomsColonnes => {for (final c in colonnes) c.nom};
}

/// Colonnes communes à toutes les tables (voir le document de conception).
const List<String> colonnesCommunes = [
  'id',
  'version',
  'created_at',
  'updated_at',
  'created_by',
  'updated_by',
  'device_id',
  'deleted_at',
];
