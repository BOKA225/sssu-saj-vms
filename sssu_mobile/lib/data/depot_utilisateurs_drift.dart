/// Comptes disponibles sur le téléphone (reçus du poste central), pour la
/// connexion hors ligne. Sur le téléphone, seuls le code PIN et les compteurs
/// de tentatives sont modifiables : la création des comptes et le changement
/// de mot de passe se font sur le poste central.
library;

import 'package:drift/drift.dart';
import 'package:sssu_core/sssu_core.dart';

import 'base_locale.dart' hide Utilisateur, Eleve;
import 'conversion_sql.dart';

class DepotUtilisateursDrift implements DepotUtilisateurs {
  final BaseLocale db;

  DepotUtilisateursDrift(this.db);

  Future<List<QueryRow>> _q(String sql, List<Object?> args) =>
      db.customSelect(sql, variables: [for (final a in args) variable(a)]).get();

  Utilisateur _lire(QueryRow r) {
    final e = lireLigne(registreParNom['utilisateur']!, r.data);
    return Utilisateur.depuisDonnees(e.id, e.donnees);
  }

  @override
  Future<Utilisateur?> parIdentifiant(String identifiant) async {
    final r = await _q('SELECT * FROM utilisateur WHERE identifiant = ? AND deleted_at IS NULL', [identifiant]);
    return r.isEmpty ? null : _lire(r.first);
  }

  @override
  Future<Utilisateur?> parId(String id) async {
    final r = await _q('SELECT * FROM utilisateur WHERE id = ? AND deleted_at IS NULL', [id]);
    return r.isEmpty ? null : _lire(r.first);
  }

  /// N'enregistre que les données propres au téléphone (code PIN, tentatives).
  @override
  Future<void> enregistrer(Utilisateur u) => db.customStatement(
        'UPDATE utilisateur SET hash_pin = ?, echecs_connexion = ?, bloque_jusqua = ? WHERE id = ?',
        [
          u.hashPin,
          u.echecsConnexion,
          u.bloqueJusqua == null ? null : formaterHorodatage(u.bloqueJusqua!),
          u.id,
        ],
      );

  @override
  Future<RoleCode?> roleDe(String roleId) async {
    final r = await _q('SELECT code FROM role WHERE id = ?', [roleId]);
    return r.isEmpty ? null : RoleCode.depuisCode(r.first.read<String>('code'));
  }

  @override
  Future<String?> roleIdParCode(RoleCode code) async {
    final r = await _q('SELECT id FROM role WHERE code = ?', [code.code]);
    return r.isEmpty ? null : r.first.read<String>('id');
  }

  @override
  Future<Set<Permission>> permissionsDuRole(String roleId) async {
    final r = await _q('SELECT permission FROM role_permission WHERE role_id = ? AND deleted_at IS NULL', [roleId]);
    return {
      for (final l in r)
        if (Permission.depuisCode(l.read<String>('permission')) case final p?) p
    };
  }

  /// Les administrateurs sont créés sur le poste central uniquement.
  @override
  Future<bool> existeAdministrateurActif() async => true;
}
