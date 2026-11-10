import '../commun/commun.dart';
import '../modeles/modeles.dart';
import 'auth_service.dart';
import 'permissions.dart';

/// Dépôt des comptes en mémoire (tests). Les rôles sont initialisés avec
/// la matrice par défaut.
class DepotUtilisateursMemoire implements DepotUtilisateurs {
  final Map<String, Utilisateur> utilisateurs = {};
  final Map<String, RoleCode> roles = {};
  final Map<String, Set<Permission>> permissions = {};

  DepotUtilisateursMemoire() {
    for (final entree in matriceParDefaut.entries) {
      final id = nouvelId();
      roles[id] = entree.key;
      permissions[id] = Set.of(entree.value);
    }
  }

  @override
  Future<Utilisateur?> parIdentifiant(String identifiant) async {
    for (final u in utilisateurs.values) {
      if (u.identifiant == identifiant) return u;
    }
    return null;
  }

  @override
  Future<Utilisateur?> parId(String id) async => utilisateurs[id];

  @override
  Future<void> enregistrer(Utilisateur u) async => utilisateurs[u.id] = u;

  @override
  Future<RoleCode?> roleDe(String roleId) async => roles[roleId];

  @override
  Future<String?> roleIdParCode(RoleCode code) async {
    for (final e in roles.entries) {
      if (e.value == code) return e.key;
    }
    return null;
  }

  @override
  Future<Set<Permission>> permissionsDuRole(String roleId) async => permissions[roleId] ?? const {};

  @override
  Future<bool> existeAdministrateurActif() async {
    final adminId = await roleIdParCode(RoleCode.admin);
    return utilisateurs.values.any((u) => u.roleId == adminId && u.actif);
  }
}
