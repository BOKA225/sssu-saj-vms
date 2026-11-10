/// Comptes stockés dans le dépôt du poste central (PostgreSQL ou mémoire).
/// Toute modification d'un compte est diffusée aux téléphones (connexion hors ligne).
library;

import '../commun/commun.dart';
import '../modeles/modeles.dart';
import '../sync/depot_serveur.dart';
import '../sync/enregistrement.dart';
import 'auth_service.dart';
import 'permissions.dart';

class DepotUtilisateursServeur implements DepotUtilisateurs {
  final DepotServeur depot;
  final Horloge horloge;

  /// Auteur des modifications (utilisateur connecté), pour la traçabilité.
  String? auteurId;

  DepotUtilisateursServeur(this.depot, {this.horloge = const HorlogeSysteme()});

  @override
  Future<Utilisateur?> parIdentifiant(String identifiant) => depot.transaction((tx) async {
        final r = await tx.chercher('utilisateur', {'identifiant': identifiant});
        return r.isEmpty ? null : Utilisateur.depuisDonnees(r.first.id, r.first.donnees);
      });

  @override
  Future<Utilisateur?> parId(String id) => depot.transaction((tx) async {
        final r = await tx.lire('utilisateur', id);
        return r == null || r.supprime ? null : Utilisateur.depuisDonnees(r.id, r.donnees);
      });

  @override
  Future<void> enregistrer(Utilisateur u) => depot.transaction((tx) async {
        final existant = await tx.lire('utilisateur', u.id);
        final maintenant = horloge.maintenant();
        final version = (existant?.version ?? 0) + 1;
        await tx.ecrire(Enregistrement(
          table: 'utilisateur',
          id: u.id,
          version: version,
          versionBase: version,
          createdAt: existant?.createdAt ?? maintenant,
          updatedAt: maintenant,
          createdBy: existant?.createdBy ?? auteurId ?? u.id,
          updatedBy: auteurId ?? u.id,
          donnees: u.versDonnees(),
        ));
      });

  @override
  Future<RoleCode?> roleDe(String roleId) => depot.transaction((tx) async {
        final r = await tx.lire('role', roleId);
        return r == null ? null : RoleCode.depuisCode(r.donnees['code']! as String);
      });

  @override
  Future<String?> roleIdParCode(RoleCode code) => depot.transaction((tx) async {
        final r = await tx.chercher('role', {'code': code.code});
        return r.isEmpty ? null : r.first.id;
      });

  @override
  Future<Set<Permission>> permissionsDuRole(String roleId) => depot.transaction((tx) async {
        final liens = await tx.chercher('role_permission', {'role_id': roleId});
        return {
          for (final l in liens)
            if (Permission.depuisCode(l.donnees['permission']! as String) case final p?) p
        };
      });

  @override
  Future<bool> existeAdministrateurActif() async {
    final adminId = await roleIdParCode(RoleCode.admin);
    if (adminId == null) return false;
    return depot.transaction((tx) async =>
        (await tx.chercher('utilisateur', {'role_id': adminId, 'actif': true})).isNotEmpty);
  }
}

/// Crée les rôles et la matrice par défaut si la base est vide
/// (premier lancement sans le jeu de données de test).
Future<void> initialiserRoles(DepotServeur depot, {Horloge horloge = const HorlogeSysteme()}) =>
    depot.transaction((tx) async {
      final maintenant = horloge.maintenant();
      Enregistrement nouveau(String table, Map<String, Object?> d) => Enregistrement(
          table: table,
          id: nouvelId(),
          version: 1,
          versionBase: 1,
          createdAt: maintenant,
          updatedAt: maintenant,
          donnees: d);
      for (final role in RoleCode.values) {
        if ((await tx.chercher('role', {'code': role.code})).isNotEmpty) continue;
        final r = nouveau('role', {'code': role.code, 'libelle': role.libelle});
        await tx.ecrire(r);
        for (final p in matriceParDefaut[role]!) {
          await tx.ecrire(nouveau('role_permission', {'role_id': r.id, 'permission': p.code}));
        }
      }
    });
