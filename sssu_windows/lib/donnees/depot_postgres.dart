/// Dépôt du poste central sur PostgreSQL. Générique : les requêtes sont
/// construites à partir du registre des tables du paquet commun, lui-même
/// identique au schéma `sql/postgres/001_schema.sql`.
///
/// Toutes les valeurs sont transmises en texte puis converties par
/// PostgreSQL (`CAST(@p AS type)`), ce qui évite toute ambiguïté de typage.
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:sssu_core/sssu_core.dart';

class ConfigPostgres {
  final String hote;
  final int port;
  final String base;
  final String utilisateur;
  final String motDePasse;

  const ConfigPostgres({
    this.hote = 'localhost',
    this.port = 5432,
    this.base = 'sssu_saj',
    this.utilisateur = 'sssu',
    required this.motDePasse,
  });

  /// Lecture d'une URL `postgres://utilisateur:motdepasse@hote:port/base`.
  factory ConfigPostgres.depuisUrl(String url) {
    final u = Uri.parse(url);
    final info = u.userInfo.split(':');
    return ConfigPostgres(
      hote: u.host,
      port: u.hasPort ? u.port : 5432,
      base: u.pathSegments.isEmpty ? 'sssu_saj' : u.pathSegments.first,
      utilisateur: Uri.decodeComponent(info.first),
      motDePasse: info.length > 1 ? Uri.decodeComponent(info[1]) : '',
    );
  }
}

class DepotPostgres implements DepotServeur {
  final Pool<void> _pool;

  DepotPostgres._(this._pool);

  static Future<DepotPostgres> ouvrir(ConfigPostgres c) async {
    final pool = Pool<void>.withEndpoints(
      [Endpoint(host: c.hote, port: c.port, database: c.base, username: c.utilisateur, password: c.motDePasse)],
      // Base locale du poste central : connexion sur la machine elle-même.
      settings: const PoolSettings(maxConnectionCount: 4, sslMode: SslMode.disable),
    );
    final depot = DepotPostgres._(pool);
    await pool.execute('SELECT 1');
    return depot;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(TransactionServeur tx) action) =>
      _pool.runTx((session) => action(_TxPostgres(session)));

  /// Requête de consultation hors transaction (écrans du poste central).
  /// Les paramètres sont passés en texte et convertis dans la requête
  /// (`CAST(@x AS uuid)`…).
  Future<List<Map<String, dynamic>>> requete(String sql, [Map<String, Object?> params = const {}]) async {
    final r = await _pool.execute(Sql.named(sql),
        parameters: {for (final e in params.entries) e.key: TypedValue(Type.text, e.value?.toString())});
    return [for (final l in r) l.toColumnMap()];
  }

  /// Exécute un script SQL de plusieurs instructions (migrations).
  Future<void> executerScript(String sql) async {
    await _pool.execute(sql, queryMode: QueryMode.simple);
  }

  @override
  Future<String> generation() async {
    try {
      final r = await requete('SELECT CAST(generation AS text) AS g FROM sync_generation WHERE id = 1');
      return r.isEmpty ? 'initiale' : r.single['g'] as String;
    } on ServerException {
      return 'initiale'; // base antérieure à 020_phase6.sql
    }
  }

  /// Après une restauration : nouvelle génération, que les téléphones
  /// détectent à leur synchronisation suivante (reprise).
  Future<void> renouvelerGeneration() => executerScript(
      'INSERT INTO sync_generation (id, generation) VALUES (1, gen_random_uuid()) '
      'ON CONFLICT (id) DO UPDATE SET generation = excluded.generation, depuis = now()');

  Future<void> fermer() => _pool.close();
}

String _cast(TypeColonne t, String param) {
  switch (t) {
    case TypeColonne.uuid:
      return 'CAST(@$param AS uuid)';
    case TypeColonne.text:
      return 'CAST(@$param AS text)';
    case TypeColonne.entier:
      return 'CAST(@$param AS integer)';
    case TypeColonne.reel:
      return 'CAST(@$param AS double precision)';
    case TypeColonne.booleen:
      return 'CAST(@$param AS boolean)';
    case TypeColonne.horodatage:
      return 'CAST(@$param AS timestamptz)';
    case TypeColonne.date:
      return 'CAST(@$param AS date)';
    case TypeColonne.json:
      return 'CAST(@$param AS jsonb)';
    case TypeColonne.binaire:
      return "decode(@$param, 'base64')";
  }
}

String? _texte(TypeColonne t, Object? v) {
  if (v == null) return null;
  if (t == TypeColonne.json) return jsonEncode(v);
  return v.toString();
}

TypedValue _p(String? texte) => TypedValue(Type.text, texte);

Object? _depuisPg(TypeColonne t, Object? v) {
  if (v == null) return null;
  switch (t) {
    case TypeColonne.date:
      return v is DateTime ? formaterDate(v) : (v as String).substring(0, 10);
    case TypeColonne.horodatage:
      return v is DateTime ? formaterHorodatage(v) : formaterHorodatage(lireHorodatage(v as String));
    case TypeColonne.json:
      return v is String ? jsonDecode(v) : v;
    case TypeColonne.binaire:
      return base64.encode(v as List<int>);
    case TypeColonne.reel:
      return (v as num).toDouble();
    case TypeColonne.entier:
      return (v as num).toInt();
    case TypeColonne.booleen:
      return v as bool;
    case TypeColonne.uuid:
    case TypeColonne.text:
      return v.toString();
  }
}

DateTime? _ts(Object? v) => v == null ? null : (v is DateTime ? v.toUtc() : lireHorodatage(v as String));

const _communes = <String, TypeColonne>{
  'id': TypeColonne.uuid,
  'version': TypeColonne.entier,
  'created_at': TypeColonne.horodatage,
  'updated_at': TypeColonne.horodatage,
  'created_by': TypeColonne.uuid,
  'updated_by': TypeColonne.uuid,
  'device_id': TypeColonne.uuid,
  'deleted_at': TypeColonne.horodatage,
};

class _TxPostgres implements TransactionServeur {
  final TxSession s;
  _TxPostgres(this.s);

  TableSpec _spec(String table) {
    final spec = registreParNom[table];
    if (spec == null || !spec.surServeur) throw ArgumentError('Table inconnue du poste central : $table');
    return spec;
  }

  Future<List<Map<String, dynamic>>> _q(String sql, Map<String, Object?> params) async {
    final r = await s.execute(Sql.named(sql), parameters: params);
    return [for (final ligne in r) ligne.toColumnMap()];
  }

  Enregistrement _versEnregistrement(TableSpec spec, Map<String, dynamic> r, String? portee) => Enregistrement(
        table: spec.nom,
        id: r['id'].toString(),
        version: (r['version'] as num).toInt(),
        versionBase: (r['version'] as num).toInt(),
        createdAt: _ts(r['created_at'])!,
        updatedAt: _ts(r['updated_at'])!,
        createdBy: r['created_by']?.toString(),
        updatedBy: r['updated_by']?.toString(),
        deviceId: r['device_id']?.toString(),
        deletedAt: _ts(r['deleted_at']),
        etablissementId: portee,
        donnees: {for (final c in spec.colonnes) c.nom: _depuisPg(c.type, r[c.nom])},
      );

  /// Établissement de rattachement : dernière portée connue dans le journal.
  Future<String?> _portee(TableSpec spec, String id) async {
    if (spec.nom == 'etablissement') return id;
    if (!spec.parEtablissement || !spec.receptionParTelephone && !spec.envoiParTelephone) return null;
    final r = await _q(
        'SELECT CAST(scope AS text) AS scope FROM sync_changement '
        'WHERE table_name = @t AND record_id = CAST(@id AS uuid) ORDER BY seq DESC LIMIT 1',
        {'t': _p(spec.nom), 'id': _p(id)});
    return r.isEmpty ? null : r.first['scope'] as String?;
  }

  @override
  Future<Enregistrement?> lire(String table, String id) async {
    final spec = _spec(table);
    // FOR UPDATE : deux téléphones modifiant le même enregistrement en même
    // temps sont traités l'un après l'autre (pas de modification perdue).
    final r = await _q('SELECT * FROM ${spec.nom} WHERE id = CAST(@id AS uuid) FOR UPDATE', {'id': _p(id)});
    if (r.isEmpty) return null;
    return _versEnregistrement(spec, r.first, await _portee(spec, id));
  }

  @override
  Future<void> ecrire(Enregistrement e, {String? motifChangement}) async {
    final spec = _spec(e.table);
    final anomalies = e.anomaliesColonnes();
    if (anomalies.isNotEmpty) throw ArgumentError('${e.table}/${e.id} : ${anomalies.join(', ')}');
    final colonnes = <String>[];
    final expressions = <String>[];
    final params = <String, Object?>{};
    void ajouter(String col, TypeColonne type, Object? valeur) {
      final p = 'p${colonnes.length}';
      colonnes.add(col);
      expressions.add(_cast(type, p));
      params[p] = _p(_texte(type, valeur));
    }

    final communes = <String, Object?>{
      'id': e.id,
      'version': e.version,
      'created_at': formaterHorodatage(e.createdAt),
      'updated_at': formaterHorodatage(e.updatedAt),
      'created_by': e.createdBy,
      'updated_by': e.updatedBy,
      'device_id': e.deviceId,
      'deleted_at': e.deletedAt == null ? null : formaterHorodatage(e.deletedAt!),
    };
    communes.forEach((c, v) => ajouter(c, _communes[c]!, v));
    for (final c in spec.colonnes) {
      final v = e.donnees[c.nom];
      // Valeur absente avec défaut en base : on laisse la base la fournir.
      if (v == null && c.aValeurParDefaut) continue;
      ajouter(c.nom, c.type, v);
    }
    final miseAJour = colonnes.where((c) => c != 'id' && c != 'created_at').map((c) => '$c = EXCLUDED.$c');
    await _q(
      'INSERT INTO ${spec.nom} (${colonnes.join(', ')}) VALUES (${expressions.join(', ')}) '
      'ON CONFLICT (id) DO UPDATE SET ${miseAJour.join(', ')}',
      params,
    );
    // Journal : changements diffusés aux téléphones, et rattachement à un
    // établissement des enregistrements qui en dépendent (contrôle d'accès).
    if (spec.receptionParTelephone || spec.parEtablissement) {
      await _q(
        'INSERT INTO sync_changement (table_name, record_id, scope, version, motif) '
        'VALUES (@t, CAST(@id AS uuid), CAST(@s AS uuid), CAST(@v AS integer), @m)',
        {
          't': _p(spec.nom),
          'id': _p(e.id),
          's': _p(spec.nom == 'etablissement' ? e.id : e.etablissementId),
          'v': _p('${e.version}'),
          'm': _p(motifChangement),
        },
      );
    }
  }

  @override
  Future<List<Enregistrement>> chercher(String table, Map<String, Object?> egalites) async {
    final spec = _spec(table);
    final conditions = <String>['deleted_at IS NULL'];
    final params = <String, Object?>{};
    var i = 0;
    egalites.forEach((col, valeur) {
      final c = spec.colonne(col);
      final type = c?.type ?? _communes[col];
      if (type == null) throw ArgumentError('Colonne inconnue : $table.$col');
      if (valeur == null) {
        conditions.add('$col IS NULL');
      } else {
        final p = 'w${i++}';
        conditions.add('$col = ${_cast(type, p)}');
        params[p] = _p(_texte(type, valeur));
      }
    });
    final r = await _q('SELECT * FROM ${spec.nom} WHERE ${conditions.join(' AND ')} ORDER BY created_at, id', params);
    return [for (final ligne in r) _versEnregistrement(spec, ligne, await _portee(spec, ligne['id'].toString()))];
  }

  @override
  Future<List<Enregistrement>> parPortee(String table, String etablissementId) async {
    final spec = _spec(table);
    final r = spec.nom == 'etablissement'
        ? await _q('SELECT * FROM etablissement WHERE id = CAST(@s AS uuid) AND deleted_at IS NULL', {'s': _p(etablissementId)})
        : await _q(
            'SELECT t.* FROM ${spec.nom} t WHERE t.deleted_at IS NULL AND ('
            'SELECT sc.scope FROM sync_changement sc WHERE sc.table_name = @t AND sc.record_id = t.id '
            'ORDER BY sc.seq DESC LIMIT 1) = CAST(@s AS uuid) ORDER BY t.created_at, t.id',
            {'t': _p(spec.nom), 's': _p(etablissementId)});
    return [for (final l in r) _versEnregistrement(spec, l, etablissementId)];
  }

  @override
  Future<List<Changement>> changementsDepuis(
    int curseur, {
    required Set<String> tables,
    required Set<String> etablissements,
    required int limite,
  }) async {
    String tableau(Iterable<String> v) => '{${v.join(',')}}';
    final journal = await _q(
      'SELECT seq, table_name, CAST(record_id AS text) AS record_id, CAST(scope AS text) AS scope, motif '
      'FROM sync_changement '
      'WHERE seq > CAST(@c AS bigint) AND table_name = ANY(CAST(@t AS text[])) '
      'AND (scope IS NULL OR scope = ANY(CAST(@s AS uuid[]))) '
      'ORDER BY seq LIMIT CAST(@l AS integer)',
      {'c': _p('$curseur'), 't': _p(tableau(tables)), 's': _p(tableau(etablissements)), 'l': _p('$limite')},
    );
    final resultat = <Changement>[];
    for (final j in journal) {
      final spec = _spec(j['table_name'] as String);
      final r = await _q('SELECT * FROM ${spec.nom} WHERE id = CAST(@id AS uuid)', {'id': _p(j['record_id'] as String)});
      if (r.isEmpty) continue;
      resultat.add(Changement(
        (j['seq'] as num).toInt(),
        _versEnregistrement(spec, r.first, j['scope'] as String?),
        motif: j['motif'] as String?,
      ));
    }
    return resultat;
  }
}
