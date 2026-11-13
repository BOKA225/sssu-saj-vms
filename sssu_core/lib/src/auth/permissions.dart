/// Rôles et permissions (matrice du document de conception).
///
/// La matrice de référence est stockée en base (`role`, `role_permission`) et
/// peut être ajustée sans modifier le code. [matriceParDefaut] sert à
/// initialiser la base et doit rester identique au jeu de données
/// `sql/seed/donnees_test.sql`.
library;

enum RoleCode {
  admin('admin', 'Administrateur'),
  medecinChef('medecin_chef', 'Médecin-Chef'),
  medecin('medecin', 'Médecin'),
  infirmier('infirmier', 'Infirmier'),
  agent('agent', 'Agent de santé');

  final String code;
  final String libelle;
  const RoleCode(this.code, this.libelle);

  static RoleCode depuisCode(String c) =>
      values.firstWhere((r) => r.code == c, orElse: () => throw ArgumentError.value(c, 'code', 'Rôle inconnu'));
}

enum Permission {
  comptesGerer('comptes.gerer'),
  parametresModifier('parametres.modifier'),
  etablissementGerer('etablissement.gerer'),
  etablissementArchiver('etablissement.archiver'),
  importExecuter('import.executer'),
  visiteSaisir('visite.saisir'),
  visiteModifierToutes('visite.modifier_toutes'),
  visiteModifierSiennes('visite.modifier_siennes'),
  visiteValider('visite.valider'),
  visiteRouvrir('visite.rouvrir'),
  photoPrendre('photo.prendre'),
  photoVoirToutes('photo.voir_toutes'),
  photoTelecharger('photo.telecharger'),
  inspectionRealiser('inspection.realiser'),
  statistiquesConsulter('statistiques.consulter'),
  rapportExporterNominatif('rapport.exporter_nominatif'),
  conflitResoudre('conflit.resoudre'),
  sauvegardeGerer('sauvegarde.gerer'),
  auditConsulter('audit.consulter');

  final String code;
  const Permission(this.code);

  static Permission? depuisCode(String c) {
    for (final p in values) {
      if (p.code == c) return p;
    }
    return null;
  }
}

/// Matrice par défaut. L'administrateur gère le système mais n'accède pas aux
/// données médicales (aucune permission « visite » ni « photo »).
const Map<RoleCode, Set<Permission>> matriceParDefaut = {
  RoleCode.admin: {
    Permission.comptesGerer,
    Permission.parametresModifier,
    Permission.etablissementGerer,
    Permission.etablissementArchiver,
    Permission.importExecuter,
    Permission.statistiquesConsulter,
    Permission.sauvegardeGerer,
    Permission.auditConsulter,
  },
  RoleCode.medecinChef: {
    Permission.parametresModifier,
    Permission.etablissementGerer,
    Permission.importExecuter,
    Permission.visiteSaisir,
    Permission.visiteModifierToutes,
    Permission.visiteValider,
    Permission.visiteRouvrir,
    Permission.photoPrendre,
    Permission.photoVoirToutes,
    Permission.photoTelecharger,
    Permission.inspectionRealiser,
    Permission.statistiquesConsulter,
    Permission.rapportExporterNominatif,
    Permission.conflitResoudre,
    Permission.auditConsulter,
  },
  RoleCode.medecin: {
    Permission.importExecuter,
    Permission.visiteSaisir,
    Permission.visiteModifierSiennes,
    Permission.visiteValider,
    Permission.photoPrendre,
    Permission.photoVoirToutes,
    Permission.inspectionRealiser,
    Permission.statistiquesConsulter,
    Permission.rapportExporterNominatif,
  },
  RoleCode.infirmier: {
    Permission.importExecuter,
    Permission.visiteSaisir,
    Permission.visiteModifierSiennes,
    Permission.photoPrendre,
    Permission.inspectionRealiser,
  },
  RoleCode.agent: {
    Permission.visiteSaisir,
    Permission.visiteModifierSiennes,
    Permission.photoPrendre,
    Permission.inspectionRealiser,
  },
};

/// Droits effectifs d'un utilisateur connecté.
class Droits {
  final String utilisateurId;
  final RoleCode role;
  final Set<Permission> permissions;

  const Droits({required this.utilisateurId, required this.role, required this.permissions});

  bool peut(Permission p) => permissions.contains(p);

  /// Modifier une visite non validée : toutes les visites, ou seulement les
  /// siennes selon le rôle. Une visite validée ne se modifie pas (il faut
  /// d'abord la rouvrir, droit `visite.rouvrir`).
  bool peutModifierVisite({required String agentId, required bool validee}) {
    if (validee) return false;
    if (peut(Permission.visiteModifierToutes)) return true;
    return peut(Permission.visiteModifierSiennes) && agentId == utilisateurId;
  }

  /// Ajouter un élève ou modifier son identité et sa classe : ceux qui
  /// importent les listes, gèrent les établissements ou modifient toutes les
  /// visites (médecin-chef, médecin, infirmier, administrateur ; pas l'agent).
  bool get peutGererEleves =>
      peut(Permission.importExecuter) || peut(Permission.etablissementGerer) || peut(Permission.visiteModifierToutes);

  /// Voir une photo : ses propres photos, ou toutes selon le rôle.
  bool peutVoirPhoto({required String auteurId}) =>
      peut(Permission.photoVoirToutes) || (peut(Permission.photoPrendre) && auteurId == utilisateurId);
}
