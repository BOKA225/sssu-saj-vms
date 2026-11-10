/// Enregistrement synchronisable : colonnes communes + données métier
/// au format canonique (voir [TypeColonne]).
library;

import 'package:collection/collection.dart';

import '../commun/commun.dart';
import '../schema/colonnes.dart';
import '../schema/registre.dart';

const _egalite = DeepCollectionEquality();

class Enregistrement {
  final String table;
  final String id;

  /// Version portée par cet enregistrement.
  final int version;

  /// Version du poste central sur laquelle repose cette modification
  /// (0 pour une création sur le téléphone). Côté serveur : égale à [version].
  final int versionBase;

  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;
  final String? updatedBy;
  final String? deviceId;
  final DateTime? deletedAt;

  /// Établissement de rattachement, qui détermine les téléphones destinataires
  /// (`null` pour les référentiels communs).
  final String? etablissementId;

  final Map<String, Object?> donnees;

  const Enregistrement({
    required this.table,
    required this.id,
    required this.version,
    required this.versionBase,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.updatedBy,
    this.deviceId,
    this.deletedAt,
    this.etablissementId,
    required this.donnees,
  });

  TableSpec get spec {
    final s = registreParNom[table];
    if (s == null) throw ArgumentError.value(table, 'table', 'Table inconnue');
    return s;
  }

  bool get supprime => deletedAt != null;

  /// Même contenu métier (données et suppression), quelles que soient les versions.
  bool memeContenu(Enregistrement autre) =>
      _egalite.equals(donnees, autre.donnees) && (deletedAt == null) == (autre.deletedAt == null);

  /// Colonnes inconnues ou obligatoires manquantes, au regard du registre.
  List<String> anomaliesColonnes() {
    final s = spec;
    final anomalies = <String>[];
    for (final k in donnees.keys) {
      if (s.colonne(k) == null) anomalies.add('colonne inconnue : $k');
    }
    for (final c in s.colonnes) {
      if (c.obligatoire && !c.aValeurParDefaut && donnees[c.nom] == null) {
        anomalies.add('colonne obligatoire manquante : ${c.nom}');
      }
    }
    return anomalies;
  }

  Enregistrement copier({
    int? version,
    int? versionBase,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? updatedBy,
    String? deviceId,
    DateTime? deletedAt,
    bool restaurer = false,
    String? etablissementId,
    Map<String, Object?>? donnees,
  }) =>
      Enregistrement(
        table: table,
        id: id,
        version: version ?? this.version,
        versionBase: versionBase ?? this.versionBase,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        createdBy: createdBy,
        updatedBy: updatedBy ?? this.updatedBy,
        deviceId: deviceId ?? this.deviceId,
        deletedAt: restaurer ? null : (deletedAt ?? this.deletedAt),
        etablissementId: etablissementId ?? this.etablissementId,
        donnees: donnees ?? this.donnees,
      );

  Map<String, Object?> versJson() => {
        'table': table,
        'id': id,
        'version': version,
        'version_base': versionBase,
        'created_at': formaterHorodatage(createdAt),
        'updated_at': formaterHorodatage(updatedAt),
        'created_by': createdBy,
        'updated_by': updatedBy,
        'device_id': deviceId,
        'deleted_at': deletedAt == null ? null : formaterHorodatage(deletedAt!),
        'etablissement_id': etablissementId,
        'donnees': donnees,
      };

  factory Enregistrement.depuisJson(Map<String, Object?> j) => Enregistrement(
        table: j['table']! as String,
        id: j['id']! as String,
        version: (j['version']! as num).toInt(),
        versionBase: (j['version_base'] as num?)?.toInt() ?? 0,
        createdAt: lireHorodatage(j['created_at']! as String),
        updatedAt: lireHorodatage(j['updated_at']! as String),
        createdBy: j['created_by'] as String?,
        updatedBy: j['updated_by'] as String?,
        deviceId: j['device_id'] as String?,
        deletedAt: j['deleted_at'] == null ? null : lireHorodatage(j['deleted_at']! as String),
        etablissementId: j['etablissement_id'] as String?,
        donnees: Map<String, Object?>.from(j['donnees']! as Map),
      );

  @override
  String toString() => '$table/$id v$version (base $versionBase)';
}
