/// Connexion, verrouillage après échecs, codes PIN et création des comptes.
library;

import '../commun/commun.dart';
import '../modeles/modeles.dart';
import 'mot_de_passe.dart';
import 'permissions.dart';

/// Accès aux comptes. Implémenté sur SQLite (téléphone), sur le dépôt du
/// poste central (PostgreSQL) et en mémoire (tests).
abstract class DepotUtilisateurs {
  Future<Utilisateur?> parIdentifiant(String identifiant);
  Future<Utilisateur?> parId(String id);

  /// Crée ou met à jour le compte.
  Future<void> enregistrer(Utilisateur u);

  Future<RoleCode?> roleDe(String roleId);
  Future<String?> roleIdParCode(RoleCode code);
  Future<Set<Permission>> permissionsDuRole(String roleId);
  Future<bool> existeAdministrateurActif();
}

/// Trace des évènements de connexion (table `journal_audit`).
abstract class JournalAuth {
  Future<void> noter(String action, {String? utilisateurId, Map<String, Object?>? details});
}

class JournalAuthMuet implements JournalAuth {
  const JournalAuthMuet();
  @override
  Future<void> noter(String action, {String? utilisateurId, Map<String, Object?>? details}) async {}
}

class PolitiqueConnexion {
  final int echecsMax;
  final Duration dureeBlocage;
  const PolitiqueConnexion({this.echecsMax = 5, this.dureeBlocage = const Duration(minutes: 15)});
}

class Session {
  final Utilisateur utilisateur;
  final Droits droits;
  final DateTime ouverteLe;

  const Session({required this.utilisateur, required this.droits, required this.ouverteLe});

  bool get doitChangerMotDePasse => utilisateur.doitChangerMotDePasse;
}

enum MotifEchec { identifiantsInvalides, compteInactif, compteBloque, pinNonDefini }

class ResultatConnexion {
  final Session? session;
  final MotifEchec? motif;
  final DateTime? bloqueJusqua;

  const ResultatConnexion.reussie(Session s)
      : session = s,
        motif = null,
        bloqueJusqua = null;
  const ResultatConnexion.echec(MotifEchec m, {this.bloqueJusqua})
      : session = null,
        motif = m;

  bool get reussie => session != null;

  String get message {
    switch (motif) {
      case null:
        return 'Connexion réussie.';
      case MotifEchec.identifiantsInvalides:
        return 'Identifiant ou mot de passe incorrect.';
      case MotifEchec.compteInactif:
        return 'Ce compte est désactivé. Contactez l\'administrateur.';
      case MotifEchec.compteBloque:
        final h = bloqueJusqua!.toLocal();
        return 'Trop de tentatives. Compte bloqué jusqu\'à '
            '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}.';
      case MotifEchec.pinNonDefini:
        return 'Aucun code PIN défini : connectez-vous avec votre mot de passe.';
    }
  }
}

class ErreurAutorisation implements Exception {
  final String message;
  const ErreurAutorisation(this.message);
  @override
  String toString() => message;
}

class ErreurSaisie implements Exception {
  final String message;
  const ErreurSaisie(this.message);
  @override
  String toString() => message;
}

class ServiceAuthentification {
  final DepotUtilisateurs depot;
  final HacheurMotDePasse hacheur;
  final Horloge horloge;
  final PolitiqueConnexion politique;
  final JournalAuth journal;

  /// Empreinte factice vérifiée quand l'identifiant est inconnu, pour que la
  /// durée de réponse ne révèle pas l'existence d'un compte.
  String? _empreinteFactice;

  ServiceAuthentification({
    required this.depot,
    HacheurMotDePasse? hacheur,
    this.horloge = const HorlogeSysteme(),
    this.politique = const PolitiqueConnexion(),
    this.journal = const JournalAuthMuet(),
  }) : hacheur = hacheur ?? HacheurMotDePasse();

  Future<ResultatConnexion> connecter(String identifiant, String motDePasse) async {
    final u = await depot.parIdentifiant(identifiant.trim().toLowerCase());
    if (u == null || u.hashMotDePasse == null) {
      _empreinteFactice ??= await hacheur.hacher('factice-${nouvelId()}');
      await hacheur.verifier(motDePasse, _empreinteFactice);
      await journal.noter('echec_connexion', details: {'identifiant': identifiant});
      return const ResultatConnexion.echec(MotifEchec.identifiantsInvalides);
    }
    return _verifierSecret(u, motDePasse, u.hashMotDePasse);
  }

  /// Déverrouillage rapide du téléphone par code PIN.
  Future<ResultatConnexion> connecterParPin(String utilisateurId, String pin) async {
    final u = await depot.parId(utilisateurId);
    if (u == null) return const ResultatConnexion.echec(MotifEchec.identifiantsInvalides);
    if (u.hashPin == null) return const ResultatConnexion.echec(MotifEchec.pinNonDefini);
    return _verifierSecret(u, pin, u.hashPin);
  }

  Future<ResultatConnexion> _verifierSecret(Utilisateur u, String secret, String? empreinte) async {
    final maintenant = horloge.maintenant();
    if (!u.actif) return const ResultatConnexion.echec(MotifEchec.compteInactif);
    if (u.bloqueJusqua != null && u.bloqueJusqua!.isAfter(maintenant)) {
      return ResultatConnexion.echec(MotifEchec.compteBloque, bloqueJusqua: u.bloqueJusqua);
    }
    if (!await hacheur.verifier(secret, empreinte)) {
      final echecs = u.echecsConnexion + 1;
      if (echecs >= politique.echecsMax) {
        final jusqua = maintenant.add(politique.dureeBlocage);
        await depot.enregistrer(u.copier(echecsConnexion: 0, bloqueJusqua: jusqua));
        await journal.noter('echec_connexion', utilisateurId: u.id, details: {'blocage_jusqua': formaterHorodatage(jusqua)});
        return ResultatConnexion.echec(MotifEchec.compteBloque, bloqueJusqua: jusqua);
      }
      await depot.enregistrer(u.copier(echecsConnexion: echecs, effacerBlocage: true));
      await journal.noter('echec_connexion', utilisateurId: u.id);
      return const ResultatConnexion.echec(MotifEchec.identifiantsInvalides);
    }
    final aJour = u.copier(echecsConnexion: 0, effacerBlocage: true);
    if (u.echecsConnexion != 0 || u.bloqueJusqua != null) await depot.enregistrer(aJour);
    await journal.noter('connexion', utilisateurId: u.id);
    return ResultatConnexion.reussie(Session(utilisateur: aJour, droits: await droitsDe(aJour), ouverteLe: maintenant));
  }

  Future<Droits> droitsDe(Utilisateur u) async {
    final role = await depot.roleDe(u.roleId);
    if (role == null) throw StateError('Rôle introuvable pour ${u.identifiant}');
    return Droits(utilisateurId: u.id, role: role, permissions: await depot.permissionsDuRole(u.roleId));
  }

  Future<Session> changerMotDePasse(Session session, {required String ancien, required String nouveau}) async {
    final u = await depot.parId(session.utilisateur.id);
    if (u == null || !await hacheur.verifier(ancien, u.hashMotDePasse)) {
      throw const ErreurSaisie('Mot de passe actuel incorrect.');
    }
    final erreur = controlerMotDePasse(nouveau);
    if (erreur != null) throw ErreurSaisie(erreur);
    if (ancien == nouveau) throw const ErreurSaisie('Le nouveau mot de passe doit être différent de l\'ancien.');
    final maj = u.copier(hashMotDePasse: await hacheur.hacher(nouveau), doitChangerMotDePasse: false);
    await depot.enregistrer(maj);
    await journal.noter('modification', utilisateurId: u.id, details: {'objet': 'mot_de_passe'});
    return Session(utilisateur: maj, droits: session.droits, ouverteLe: session.ouverteLe);
  }

  Future<Session> definirPin(Session session, String pin) async {
    final erreur = controlerPin(pin);
    if (erreur != null) throw ErreurSaisie(erreur);
    final u = (await depot.parId(session.utilisateur.id))!;
    final maj = u.copier(hashPin: await hacheur.hacher(pin));
    await depot.enregistrer(maj);
    return Session(utilisateur: maj, droits: session.droits, ouverteLe: session.ouverteLe);
  }

  /// Création d'un compte par un utilisateur autorisé (`comptes.gerer`).
  /// Le titulaire devra changer le mot de passe temporaire à sa première connexion.
  Future<Utilisateur> creerUtilisateur(
    Droits acteur, {
    required String identifiant,
    required String nom,
    String? prenoms,
    String? fonction,
    String? structure,
    required RoleCode role,
    required String motDePasseTemporaire,
  }) async {
    if (!acteur.peut(Permission.comptesGerer)) {
      throw const ErreurAutorisation('Vous n\'êtes pas autorisé à créer des comptes.');
    }
    return _creer(
        identifiant: identifiant,
        nom: nom,
        prenoms: prenoms,
        fonction: fonction,
        structure: structure,
        role: role,
        motDePasse: motDePasseTemporaire,
        doitChanger: true);
  }

  /// Premier lancement du poste central : création du compte administrateur.
  /// Refusé dès qu'un administrateur actif existe.
  Future<Utilisateur> creerPremierAdministrateur({
    required String identifiant,
    required String nom,
    String? prenoms,
    required String motDePasse,
  }) async {
    if (await depot.existeAdministrateurActif()) {
      throw const ErreurAutorisation('Un administrateur existe déjà.');
    }
    return _creer(
        identifiant: identifiant,
        nom: nom,
        prenoms: prenoms,
        fonction: 'Administrateur',
        role: RoleCode.admin,
        motDePasse: motDePasse,
        doitChanger: false);
  }

  Future<Utilisateur> _creer({
    required String identifiant,
    required String nom,
    String? prenoms,
    String? fonction,
    String? structure,
    required RoleCode role,
    required String motDePasse,
    required bool doitChanger,
  }) async {
    final ident = identifiant.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9._-]{3,40}$').hasMatch(ident)) {
      throw const ErreurSaisie('Identifiant : 3 à 40 caractères parmi lettres, chiffres, point, tiret.');
    }
    if (await depot.parIdentifiant(ident) != null) throw const ErreurSaisie('Cet identifiant est déjà utilisé.');
    final erreur = controlerMotDePasse(motDePasse);
    if (erreur != null) throw ErreurSaisie(erreur);
    final roleId = await depot.roleIdParCode(role);
    if (roleId == null) throw StateError('Rôle ${role.code} absent de la base.');
    final u = Utilisateur(
      id: nouvelId(),
      identifiant: ident,
      nom: nom.trim(),
      prenoms: prenoms?.trim(),
      fonction: fonction,
      structure: structure,
      roleId: roleId,
      hashMotDePasse: await hacheur.hacher(motDePasse),
      doitChangerMotDePasse: doitChanger,
    );
    await depot.enregistrer(u);
    await journal.noter('creation', utilisateurId: u.id, details: {'objet': 'utilisateur', 'role': role.code});
    return u;
  }
}
