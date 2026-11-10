/// Conversion entre les valeurs SQLite du téléphone et le format canonique
/// des enregistrements synchronisés (voir `TypeColonne`).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:sssu_core/sssu_core.dart';

Object? versSqlite(TypeColonne type, Object? v) {
  if (v == null) return null;
  switch (type) {
    case TypeColonne.booleen:
      return (v as bool) ? 1 : 0;
    case TypeColonne.json:
      return jsonEncode(v);
    case TypeColonne.binaire:
      return base64.decode(v as String);
    case TypeColonne.entier:
      return (v as num).toInt();
    case TypeColonne.reel:
      return (v as num).toDouble();
    case TypeColonne.horodatage:
      return formaterHorodatage(lireHorodatage(v as String));
    case TypeColonne.date:
      return formaterDate(lireDate(v as String));
    case TypeColonne.uuid:
    case TypeColonne.text:
      return v as String;
  }
}

Object? depuisSqlite(TypeColonne type, Object? v) {
  if (v == null) return null;
  switch (type) {
    case TypeColonne.booleen:
      return v is bool ? v : (v as num) != 0;
    case TypeColonne.json:
      return v is String ? jsonDecode(v) : v;
    case TypeColonne.binaire:
      return base64.encode(v as List<int>);
    case TypeColonne.entier:
      return (v as num).toInt();
    case TypeColonne.reel:
      return (v as num).toDouble();
    case TypeColonne.horodatage:
      return formaterHorodatage(lireHorodatage(v as String));
    case TypeColonne.date:
      return (v as String).substring(0, 10);
    case TypeColonne.uuid:
    case TypeColonne.text:
      return v as String;
  }
}

/// Variable drift pour une valeur SQLite déjà convertie.
Variable<Object> variable(Object? v) {
  if (v == null) return const Variable<String>(null);
  if (v is int) return Variable.withInt(v);
  if (v is double) return Variable.withReal(v);
  if (v is String) return Variable.withString(v);
  if (v is bool) return Variable.withBool(v);
  if (v is Uint8List) return Variable.withBlob(v);
  throw ArgumentError('Type non pris en charge : ${v.runtimeType}');
}

DateTime? _ts(Object? v) => v == null ? null : lireHorodatage(v as String);

/// Ligne SQLite → enregistrement synchronisable.
Enregistrement lireLigne(TableSpec spec, Map<String, Object?> r) => Enregistrement(
      table: spec.nom,
      id: r['id']! as String,
      version: (r['version']! as num).toInt(),
      versionBase: (r['base_version']! as num).toInt(),
      createdAt: _ts(r['created_at'])!,
      updatedAt: _ts(r['updated_at'])!,
      createdBy: r['created_by'] as String?,
      updatedBy: r['updated_by'] as String?,
      deviceId: r['device_id'] as String?,
      deletedAt: _ts(r['deleted_at']),
      etablissementId: r['portee_etablissement_id'] as String?,
      donnees: {for (final c in spec.colonnes) c.nom: depuisSqlite(c.type, r[c.nom])},
    );
