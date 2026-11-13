/// Traitement, sur le poste central, des envois et des demandes de réception
/// des téléphones, et résolution des conflits par le Médecin-Chef.
library;

import '../auth/permissions.dart';
import '../commun/commun.dart';
import '../schema/registre.dart';
import 'depot_serveur.dart';
import 'diffusion.dart';
import 'enregistrement.dart';
import 'fichiers.dart';
import 'protocole.dart';
import 'resolution_conflits.dart';

/// Permissions exigées pour envoyer un enregistrement de chaque table
/// (l'une d'elles suffit). `journal_audit` n'exige qu'un compte actif.
const Map<String, Set<Permission>> permissionsEnvoi = {
  'classe': {Permission.etablissementGerer},
  'eleve': {Permission.importExecuter, Permission.visiteSaisir},
  'inscription': {Permission.importExecuter, Permission.visiteSaisir},
  'visite': {Permission.visiteSaisir},
  'antecedent': {Permission.visiteSaisir},
  'examen_appareil': {Permission.visiteSaisir},
  'visite_pathologie': {Permission.visiteSaisir},
  'consentement': {Permission.visiteSaisir, Permission.photoPrendre},
  'photo': {Permission.photoPrendre},
  'inspection': {Permission.inspectionRealiser},
  'inspection_reponse': {Permission.inspectionRealiser},
  'inspection_photo': {Permission.inspectionRealiser},
  'journal_audit': {},
};

class ServiceSynchronisation {
  final DepotServeur depot;
  final Horloge horloge;

  /// Nombre maximal d'enregistrements par envoi (le téléphone envoie par lots de 200).
  final int tailleMaxLot;

  ServiceSynchronisation({required this.depot, this.horloge = const HorlogeSysteme(), this.tailleMaxLot = 500});

  /// Traite un lot envoyé par l'appareil [appareilId] (déjà authentifié).
  /// Tout le lot est enregistré dans une seule transaction.
  Future<ReponseEnvoi> recevoirEnvoi(String appareilId, DemandeEnvoi demande) async {
    if (demande.enregistrements.length > tailleMaxLot) {
      throw ErreurProtocole(413, 'lot_trop_grand', 'Au plus $tailleMaxLot enregistrements par envoi.');
    }
    final debut = horloge.maintenant();
    return depot.transaction((tx) async {
      final etablissements = await _etablissementsAffectes(tx, appareilId);
      final cacheDroits = <String, _DroitsUtilisateur?>{};
      final accuses = <Accuse>[];
      for (final brut in demande.enregistrements) {
        // L'appareil est celui du jeton, quoi qu'en dise l'enregistrement.
        final entrant = brut.copier(deviceId: appareilId);
        accuses.add(await _traiter(tx, appareilId, entrant, etablissements, cacheDroits, reprise: demande.reprise));
      }
      final erreurs = accuses.where((a) => a.statut == StatutAccuse.conflit || a.statut == StatutAccuse.refuse);
      await tx.ecrire(_nouvelEnregistrement('journal_sync', {
        'appareil_id': appareilId,
        'utilisateur_id': demande.enregistrements.isEmpty ? null : demande.enregistrements.first.updatedBy,
        'canal': demande.canal == 'internet' ? 'internet' : 'wifi',
        'debut': formaterHorodatage(debut),
        'fin': formaterHorodatage(horloge.maintenant()),
        'envoyes': demande.enregistrements.length,
        'recus': 0,
        'photos': 0,
        'erreurs': erreurs.length,
        'detail': {
          'type': 'envoi',
          'refus': [for (final a in erreurs) '${a.table}/${a.id} : ${a.motif}'],
          if (demande.reprise) 'reprise': true,
        },
      }));
      return ReponseEnvoi(accuses);
    });
  }

  Future<Accuse> _traiter(
    TransactionServeur tx,
    String appareilId,
    Enregistrement entrant,
    Set<String> etablissements,
    Map<String, _DroitsUtilisateur?> cacheDroits, {
    bool reprise = false,
  }) async {
    Accuse refus(String motif) => Accuse(table: entrant.table, id: entrant.id, statut: StatutAccuse.refuse, motif: motif);

    final spec = registreParNom[entrant.table];
    if (spec == null || !spec.envoiParTelephone) return refus('table_non_autorisee');
    final anomalies = entrant.anomaliesColonnes();
    if (anomalies.isNotEmpty) return refus('donnees_invalides : ${anomalies.join(', ')}');
    if (spec.parEtablissement &&
        (entrant.etablissementId == null || !etablissements.contains(entrant.etablissementId))) {
      return refus('etablissement_non_affecte');
    }

    // Auteur : compte actif, avec les droits nécessaires.
    final auteurId = entrant.updatedBy;
    if (auteurId == null) return refus('auteur_manquant');
    final droits = cacheDroits.containsKey(auteurId)
        ? cacheDroits[auteurId]
        : (cacheDroits[auteurId] = await _droitsDe(tx, auteurId));
    if (droits == null) return refus('utilisateur_inconnu_ou_inactif');
    final requises = permissionsEnvoi[entrant.table] ?? const <Permission>{};
    if (requises.isNotEmpty && !requises.any(droits.permissions.contains)) return refus('droits_insuffisants');

    final existant = await tx.lire(entrant.table, entrant.id);

    if (entrant.table == 'visite') {
      final motif = _controlerVisite(entrant, existant, droits);
      if (motif != null) return refus(motif);
    }

    final decision = decider(entrant, existant, reprise: reprise);
    switch (decision.type) {
      case TypeDecision.dejaRecu:
        return Accuse(table: entrant.table, id: entrant.id, statut: StatutAccuse.dejaRecu, version: existant!.version);
      case TypeDecision.refuser:
        return refus(decision.motif!);
      case TypeDecision.conflit:
        await _noterConflit(tx, decision.typeConflit!, entrant, existant, appareilId);
        return Accuse(table: entrant.table, id: entrant.id, statut: StatutAccuse.conflit, motif: decision.motif);
      case TypeDecision.accepter:
        break;
    }

    // Unicité (inscription unique par année, examen unique par appareil…).
    for (final cle in spec.clesNaturelles) {
      final autres = await tx.chercher(entrant.table, {for (final c in cle) c: entrant.donnees[c]});
      if (autres.any((a) => a.id != entrant.id)) {
        await _noterConflit(tx, TypesConflit.unicite, entrant, autres.firstWhere((a) => a.id != entrant.id), appareilId);
        return Accuse(
            table: entrant.table,
            id: entrant.id,
            statut: StatutAccuse.conflit,
            motif: 'Un enregistrement identique existe déjà (${cle.join(', ')}).');
      }
    }

    // Inscription dans un autre établissement : le dossier de l'élève suit.
    if (entrant.table == 'inscription') {
      await reaffecterEleve(tx, entrant.donnees['eleve_id']! as String, entrant.etablissementId!);
    }

    final version = decision.conserverVersion ? entrant.version : (existant?.version ?? 0) + 1;
    // Fichier déjà reçu et vérifié : une modification ultérieure de la fiche
    // (commentaire…) ne remet pas son statut de transfert en attente.
    final fichierConfirme =
        tablesAvecFichier.contains(entrant.table) && existant?.donnees['statut_transfert'] == 'confirme';
    final ecrit = entrant.copier(
      version: version,
      versionBase: version,
      createdAt: existant?.createdAt ?? entrant.createdAt,
      donnees: fichierConfirme ? {...entrant.donnees, 'statut_transfert': 'confirme'} : null,
    );
    await tx.ecrire(ecrit);

    // Doublons probables : acceptés, mais signalés pour vérification.
    if (existant == null) await _signalerDoublons(tx, ecrit, appareilId);

    return Accuse(table: entrant.table, id: entrant.id, statut: StatutAccuse.accepte, version: version);
  }

  String? _controlerVisite(Enregistrement entrant, Enregistrement? existant, _DroitsUtilisateur droits) {
    final agentId = entrant.donnees['agent_id'];
    if (existant == null) {
      if (agentId != entrant.updatedBy && !droits.peut(Permission.visiteModifierToutes)) {
        return 'agent_different_de_l_auteur';
      }
    } else if (!entrant.memeContenu(existant)) {
      final proprietaire = existant.donnees['agent_id'];
      final autorise = droits.peut(Permission.visiteModifierToutes) ||
          (droits.peut(Permission.visiteModifierSiennes) && proprietaire == droits.id);
      if (!autorise) return 'droits_insuffisants';
    }
    final valideeAvant = existant?.donnees['statut'] == 'valide';
    if (entrant.donnees['statut'] == 'valide' && !valideeAvant && !droits.peut(Permission.visiteValider)) {
      return 'validation_non_autorisee';
    }
    return null;
  }

  Future<void> _signalerDoublons(TransactionServeur tx, Enregistrement e, String appareilId) async {
    if (e.table == 'eleve' && e.donnees['matricule'] != null) {
      final memes = await tx.chercher('eleve', {'matricule': e.donnees['matricule']});
      for (final autre in memes.where((a) => a.id != e.id)) {
        await _noterConflit(tx, TypesConflit.doublonEleve, e, autre, appareilId);
      }
    }
    if (e.table == 'visite') {
      final memes = await tx.chercher('visite', {'eleve_id': e.donnees['eleve_id'], 'date_visite': e.donnees['date_visite']});
      for (final autre in memes.where((a) => a.id != e.id)) {
        await _noterConflit(tx, TypesConflit.doublonVisite, e, autre, appareilId);
      }
    }
  }

  Future<void> _noterConflit(
    TransactionServeur tx,
    String type,
    Enregistrement entrant,
    Enregistrement? serveur,
    String appareilId,
  ) =>
      tx.ecrire(_nouvelEnregistrement('conflit', {
        'table_cible': entrant.table,
        'enregistrement_id': entrant.id,
        'type': type,
        'version_serveur': serveur?.versJson(),
        'version_appareil': entrant.versJson(),
        'appareil_id': appareilId,
        'statut': 'ouvert',
      }));

  /// Changements à transmettre à l'appareil depuis [curseur].
  /// Changements à envoyer au téléphone depuis [curseur]. [protocole] : version
  /// annoncée par le téléphone ; un téléphone plus ancien que le poste reçoit
  /// tout ce que sa base sait enregistrer, puis un refus clair l'invitant à
  /// installer la nouvelle version de l'application (au lieu d'une erreur de
  /// sa base de données à chaque synchronisation).
  Future<ReponseReception> preparerReception(String appareilId, int curseur,
          {int limite = 500, int protocole = protocoleSync}) =>
      depot.transaction((tx) async {
        final etablissements = await _etablissementsAffectes(tx, appareilId);
        final tables = {for (final t in registre) if (t.receptionParTelephone) t.nom};
        var changements =
            await tx.changementsDepuis(curseur, tables: tables, etablissements: etablissements, limite: limite);
        if (protocole < 2) {
          final i = changements.indexWhere((c) => !compatibleProtocole1(c.enregistrement));
          if (i == 0) {
            throw const ErreurProtocole(426, 'mise_a_jour_requise',
                'Le poste central utilise la nouvelle grille d\'inspection (version 1.2) : installez la dernière version '
                'de l\'application SSSU-SAJ VMS sur ce téléphone, puis synchronisez. Les données du téléphone sont '
                'conservées et ont déjà été envoyées.');
          }
          if (i > 0) {
            changements = changements.sublist(0, i);
            return ReponseReception(
              changements: [
                for (final c in changements)
                  ChangementRecu(c.enregistrement, resolutionConflit: c.motif == MotifsChangement.resolutionConflit)
              ],
              curseur: changements.last.seq,
              suite: true,
            );
          }
        }
        // Si un téléphone a un conflit en cours sur un enregistrement, seule la
        // décision du Médecin-Chef (motif « resolution_conflit ») remplace sa version.
        return ReponseReception(
          changements: [
            for (final c in changements)
              ChangementRecu(c.enregistrement, resolutionConflit: c.motif == MotifsChangement.resolutionConflit)
          ],
          curseur: changements.isEmpty ? curseur : changements.last.seq,
          suite: changements.length >= limite,
        );
      });

  /// Enregistrement que la base d'un téléphone antérieur à la version 1.2.0
  /// peut recevoir (critères de l'ancienne grille seulement).
  static bool compatibleProtocole1(Enregistrement e) {
    if (e.table != 'critere_inspection') return true;
    const anciennes = {
      'eau_potable', 'toilettes', 'lavage_mains', 'dechets', 'environnement', 'cantine', 'vendeuses', 'infirmerie', 'securite'
    };
    return anciennes.contains(e.donnees['rubrique']);
  }

  Future<Set<String>> _etablissementsAffectes(TransactionServeur tx, String appareilId) async {
    final liens = await tx.chercher('appareil_etablissement', {'appareil_id': appareilId});
    return {for (final l in liens) l.donnees['etablissement_id']! as String};
  }

  Future<_DroitsUtilisateur?> _droitsDe(TransactionServeur tx, String utilisateurId) async {
    final u = await tx.lire('utilisateur', utilisateurId);
    if (u == null || u.supprime || u.donnees['actif'] == false) return null;
    final liens = await tx.chercher('role_permission', {'role_id': u.donnees['role_id']});
    return _DroitsUtilisateur(utilisateurId, {
      for (final l in liens)
        if (Permission.depuisCode(l.donnees['permission']! as String) case final p?) p
    });
  }

  Enregistrement _nouvelEnregistrement(String table, Map<String, Object?> donnees) {
    final maintenant = horloge.maintenant();
    return Enregistrement(
      table: table,
      id: nouvelId(),
      version: 1,
      versionBase: 1,
      createdAt: maintenant,
      updatedAt: maintenant,
      donnees: donnees,
    );
  }
}

class _DroitsUtilisateur {
  final String id;
  final Set<Permission> permissions;
  _DroitsUtilisateur(this.id, this.permissions);
  bool peut(Permission p) => permissions.contains(p);
}

/// Décision du Médecin-Chef sur un conflit (écran Windows en phase 4).
enum ChoixConflit {
  /// Garder la version du poste central.
  serveur('serveur'),

  /// Retenir la version envoyée par le téléphone.
  appareil('appareil'),

  /// Retenir des données fusionnées champ par champ.
  fusion('fusion');

  final String code;
  const ChoixConflit(this.code);
}

class ServiceConflits {
  final DepotServeur depot;
  final Horloge horloge;

  ServiceConflits({required this.depot, this.horloge = const HorlogeSysteme()});

  Future<List<Enregistrement>> ouverts() =>
      depot.transaction((tx) => tx.chercher('conflit', {'statut': 'ouvert'}));

  /// Tranche le conflit [conflitId]. La version retenue est écrite comme une
  /// nouvelle version et diffusée aux téléphones avec le motif
  /// « resolution_conflit », ce qui remplace la version locale en conflit.
  Future<Enregistrement> resoudre(
    String conflitId, {
    required ChoixConflit choix,
    required Droits acteur,
    Map<String, Object?>? donneesFusion,
  }) async {
    if (!acteur.peut(Permission.conflitResoudre)) {
      throw StateError('Seul un utilisateur autorisé peut résoudre un conflit.');
    }
    return depot.transaction((tx) async {
      final conflit = await tx.lire('conflit', conflitId);
      if (conflit == null || conflit.donnees['statut'] != 'ouvert') throw StateError('Conflit introuvable ou déjà résolu.');
      if (!{TypesConflit.modificationConcurrente, TypesConflit.suppressionModification}.contains(conflit.donnees['type'])) {
        throw StateError('Ce type de conflit se règle par la fusion, l\'archivage ou la clôture.');
      }
      final table = conflit.donnees['table_cible']! as String;
      final id = conflit.donnees['enregistrement_id']! as String;
      final actuel = await tx.lire(table, id);
      final appareil = Enregistrement.depuisJson(
          Map<String, Object?>.from(conflit.donnees['version_appareil']! as Map));
      final base = actuel ?? appareil;
      final Map<String, Object?> donnees;
      switch (choix) {
        case ChoixConflit.serveur:
          donnees = base.donnees;
        case ChoixConflit.appareil:
          donnees = appareil.donnees;
        case ChoixConflit.fusion:
          if (donneesFusion == null) throw ArgumentError('Données fusionnées manquantes.');
          donnees = {...base.donnees, ...donneesFusion};
      }
      final maintenant = horloge.maintenant();
      final version = (actuel?.version ?? 0) + 1;
      final retenu = base.copier(
        version: version,
        versionBase: version,
        updatedAt: maintenant,
        updatedBy: acteur.utilisateurId,
        donnees: donnees,
        deletedAt: choix == ChoixConflit.appareil ? appareil.deletedAt : null,
        restaurer: choix == ChoixConflit.appareil && appareil.deletedAt == null,
      );
      if (choix != ChoixConflit.serveur || actuel == null) {
        await tx.ecrire(retenu, motifChangement: MotifsChangement.resolutionConflit);
      } else {
        // Version serveur gardée : on la rediffuse pour lever le conflit sur le téléphone.
        await tx.ecrire(actuel.copier(version: version, versionBase: version, updatedAt: maintenant),
            motifChangement: MotifsChangement.resolutionConflit);
      }
      await _clore(tx, conflit, acteur, choix.code);
      return (await tx.lire(table, id))!;
    });
  }

  Future<void> _clore(TransactionServeur tx, Enregistrement conflit, Droits acteur, String choix) async {
    final maintenant = horloge.maintenant();
    await tx.ecrire(conflit.copier(
      version: conflit.version + 1,
      versionBase: conflit.version + 1,
      updatedAt: maintenant,
      updatedBy: acteur.utilisateurId,
      donnees: {
        ...conflit.donnees,
        'statut': 'resolu',
        'resolu_par': acteur.utilisateurId,
        'resolu_le': formaterHorodatage(maintenant),
        'choix': choix,
      },
    ));
  }

  void _exiger(Droits acteur) {
    if (!acteur.peut(Permission.conflitResoudre)) {
      throw StateError('Seul un utilisateur autorisé peut résoudre un conflit.');
    }
  }

  Future<Enregistrement> _conflitOuvert(TransactionServeur tx, String conflitId) async {
    final c = await tx.lire('conflit', conflitId);
    if (c == null || c.donnees['statut'] != 'ouvert') throw StateError('Conflit introuvable ou déjà résolu.');
    return c;
  }

  /// Nouvelle version d'un enregistrement, diffusée avec le motif
  /// « resolution_conflit » (elle remplace la version en conflit des téléphones).
  Future<Enregistrement> _maj(TransactionServeur tx, Enregistrement e, Map<String, Object?> changements, Droits acteur,
      {bool supprimer = false, String? etablissementId}) async {
    final m = horloge.maintenant();
    final v = e.version + 1;
    final maj = e.copier(
      version: v,
      versionBase: v,
      updatedAt: m,
      updatedBy: acteur.utilisateurId,
      deletedAt: supprimer ? m : null,
      etablissementId: etablissementId,
      donnees: {...e.donnees, ...changements},
    );
    await tx.ecrire(maj, motifChangement: MotifsChangement.resolutionConflit);
    return maj;
  }

  /// Clôt un conflit sans rien changer : version du poste central conservée
  /// (doublon d'inscription ou de classe, doublon de visite à garder, faux doublon d'élève).
  Future<void> fermer(String conflitId, {required Droits acteur}) async {
    _exiger(acteur);
    return depot.transaction((tx) async {
      final conflit = await _conflitOuvert(tx, conflitId);
      // Modification refusée d'un enregistrement existant : la version du poste
      // est rediffusée pour lever le conflit sur le téléphone.
      if (conflit.donnees['type'] == TypesConflit.unicite) {
        final actuel = await tx.lire(conflit.donnees['table_cible']! as String, conflit.donnees['enregistrement_id']! as String);
        if (actuel != null) await _maj(tx, actuel, const {}, acteur, supprimer: actuel.supprime);
      }
      await _clore(tx, conflit, acteur, 'serveur');
    });
  }

  /// Doublon de visite : la visite indiquée et ses éléments sont archivés
  /// (les photographies restent conservées sur le poste central).
  Future<void> archiverVisite(String conflitId, String visiteId, {required Droits acteur}) async {
    _exiger(acteur);
    return depot.transaction((tx) async {
      final conflit = await _conflitOuvert(tx, conflitId);
      final v = await tx.lire('visite', visiteId);
      if (v == null || v.supprime) throw StateError('Visite introuvable.');
      for (final table in ['photo', 'consentement', 'visite_pathologie', 'examen_appareil', 'antecedent']) {
        for (final e in await tx.chercher(table, {'visite_id': visiteId})) {
          await _maj(tx, e, const {}, acteur, supprimer: true);
        }
      }
      await _maj(tx, v, const {}, acteur, supprimer: true);
      await _clore(tx, conflit, acteur, 'serveur');
    });
  }

  /// Doublon d'élève : le dossier [absorberId] est fusionné dans [garderId].
  /// Identité complétée, inscriptions, visites, antécédents, consentements et
  /// photos rattachés au dossier conservé ; le dossier absorbé est archivé.
  /// Tous les conflits « doublon d'élève » entre ces deux dossiers sont clos.
  Future<Enregistrement> fusionnerEleves(
      {required String garderId, required String absorberId, required Droits acteur}) async {
    _exiger(acteur);
    if (garderId == absorberId) throw ArgumentError('Les deux dossiers sont identiques.');
    return depot.transaction((tx) async {
      final g = await tx.lire('eleve', garderId);
      final a = await tx.lire('eleve', absorberId);
      if (g == null || g.supprime || a == null || a.supprime) throw StateError('Dossier introuvable ou déjà archivé.');
      if (g.etablissementId != a.etablissementId) {
        throw StateError('Les deux dossiers appartiennent à des établissements différents : '
            'changez d\'abord la classe de l\'un des élèves.');
      }
      final completer = {
        for (final k in ['matricule', 'date_naissance', 'telephone_contact'])
          if (g.donnees[k] == null && a.donnees[k] != null) k: a.donnees[k],
      };
      final garde = completer.isEmpty ? g : await _maj(tx, g, completer, acteur);

      final annees = {for (final i in await tx.chercher('inscription', {'eleve_id': garderId})) i.donnees['annee_scolaire_id']};
      for (final i in await tx.chercher('inscription', {'eleve_id': absorberId})) {
        if (annees.contains(i.donnees['annee_scolaire_id'])) {
          await _maj(tx, i, const {}, acteur, supprimer: true);
        } else {
          await _maj(tx, i, {'eleve_id': garderId}, acteur);
        }
      }
      for (final table in ['visite', 'antecedent', 'consentement', 'photo']) {
        for (final e in await tx.chercher(table, {'eleve_id': absorberId})) {
          await _maj(tx, e, {'eleve_id': garderId}, acteur);
        }
      }
      await _maj(tx, a, const {}, acteur, supprimer: true);
      for (final c in await tx.chercher('conflit', {'statut': 'ouvert', 'type': TypesConflit.doublonEleve})) {
        final ids = {c.donnees['enregistrement_id'], (c.donnees['version_serveur'] as Map?)?['id']};
        if (ids.containsAll({garderId, absorberId}) || ids.contains(absorberId)) await _clore(tx, c, acteur, 'fusion');
      }
      return garde;
    });
  }
}
