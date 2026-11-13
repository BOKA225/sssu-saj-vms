/// Gestion centralisée sur le poste central : années scolaires,
/// établissements, classes, élèves, importation des listes, validation et
/// réouverture des visites, affectation des téléphones, comptes, et
/// traçabilité (journal d'audit) de chaque action et consultation.
///
/// Chaque écriture passe par le dépôt du poste central : elle incrémente la
/// version de l'enregistrement et le diffuse aux téléphones concernés.
library;

import '../auth/mot_de_passe.dart';
import '../auth/permissions.dart';
import '../commun/commun.dart';
import '../import/analyse.dart';
import '../import/etablissements.dart';
import '../import/reconnaissance.dart';
import '../modeles/enums.dart';
import '../regles/identite.dart';
import '../sync/depot_serveur.dart';
import '../sync/diffusion.dart';
import '../sync/enregistrement.dart';

class ResultatImportEtablissements {
  final int crees;
  final int misAJour;
  final int ignores;
  const ResultatImportEtablissements(this.crees, this.misAJour, this.ignores);
}

class ErreurGestion implements Exception {
  final String message;
  const ErreurGestion(this.message);
  @override
  String toString() => message;
}

class ResultatImportServeur {
  final String lotId;
  final int crees;
  final int rattaches;
  final int ignores;
  final int changementsDeClasse;
  const ResultatImportServeur(this.lotId, this.crees, this.rattaches, this.ignores, this.changementsDeClasse);
}

/// Élèves d'un fichier destinés à une classe (fichier de plusieurs classes :
/// une partie par feuille ou par valeur de la colonne « Classe »).
class PartieImport {
  final String classeId;
  final List<LigneImport> lignes;

  /// Origine dans le fichier (« Feuille « CM2 A » »), notée dans le journal.
  final String? origine;
  const PartieImport(this.classeId, this.lignes, {this.origine});
}

class ServiceGestion {
  final DepotServeur depot;
  final Horloge horloge;
  final HacheurMotDePasse hacheur;

  ServiceGestion({required this.depot, this.horloge = const HorlogeSysteme(), HacheurMotDePasse? hacheur})
      : hacheur = hacheur ?? HacheurMotDePasse();

  // ----------------------------------------------------------------- outils

  static void _exiger(Droits a, Permission p) {
    if (!a.peut(p)) throw const ErreurGestion('Vous n\'êtes pas autorisé à effectuer cette action.');
  }

  Future<Enregistrement> _creer(TransactionServeur tx, String table, Map<String, Object?> donnees, Droits a,
      {String? etablissementId, String? id}) async {
    final m = horloge.maintenant();
    final nouvelId_ = id ?? nouvelId();
    final e = Enregistrement(
      table: table,
      id: nouvelId_,
      version: 1,
      versionBase: 1,
      createdAt: m,
      updatedAt: m,
      createdBy: a.utilisateurId,
      updatedBy: a.utilisateurId,
      etablissementId: table == 'etablissement' ? nouvelId_ : etablissementId,
      donnees: donnees,
    );
    await tx.ecrire(e);
    if (table != 'journal_audit') await _noter(tx, a, 'creation', table: table, id: e.id, apres: donnees);
    return e;
  }

  Future<Enregistrement> _modifier(TransactionServeur tx, Enregistrement e, Map<String, Object?> changements, Droits a,
      {String? etablissementId, bool supprimer = false, String? motif}) async {
    final avant = <String, Object?>{};
    final apres = <String, Object?>{};
    changements.forEach((k, v) {
      if (e.donnees[k] != v) {
        avant[k] = e.donnees[k];
        apres[k] = v;
      }
    });
    final changeEtab = etablissementId != null && etablissementId != e.etablissementId;
    if (apres.isEmpty && !supprimer && !changeEtab) return e;
    final m = horloge.maintenant();
    final maj = e.copier(
      version: e.version + 1,
      versionBase: e.version + 1,
      updatedAt: m,
      updatedBy: a.utilisateurId,
      etablissementId: etablissementId,
      deletedAt: supprimer ? m : null,
      donnees: {...e.donnees, ...changements},
    );
    await tx.ecrire(maj);
    await _noter(tx, a, supprimer ? 'suppression' : 'modification',
        table: e.table, id: e.id, avant: avant, apres: {...apres, if (motif != null) 'motif': motif});
    return maj;
  }

  Future<void> _noter(TransactionServeur tx, Droits? a, String action,
      {String? table, String? id, Map<String, Object?>? avant, Map<String, Object?>? apres}) async {
    final m = horloge.maintenant();
    // Les empreintes de mots de passe ne figurent jamais dans le journal.
    Map<String, Object?>? filtrer(Map<String, Object?>? x) => x == null
        ? null
        : {
            for (final e in x.entries)
              e.key: e.key.startsWith('hash_') && e.value != null ? '(modifié)' : e.value,
          };
    await tx.ecrire(Enregistrement(
      table: 'journal_audit',
      id: nouvelId(),
      version: 1,
      versionBase: 1,
      createdAt: m,
      updatedAt: m,
      createdBy: a?.utilisateurId,
      updatedBy: a?.utilisateurId,
      donnees: {
        'utilisateur_id': a?.utilisateurId,
        'action': action,
        'table_cible': table,
        'enregistrement_id': id,
        'avant': filtrer(avant),
        'apres': filtrer(apres),
        'survenu_le': formaterHorodatage(m),
      },
    ));
  }

  Future<Enregistrement> _lire(TransactionServeur tx, String table, String id) async {
    final e = await tx.lire(table, id);
    if (e == null || e.supprime) throw const ErreurGestion('Élément introuvable ou archivé.');
    return e;
  }

  static String _requis(Map<String, Object?> d, String champ, String libelle) {
    final v = (d[champ] as String?)?.trim() ?? '';
    if (v.isEmpty) throw ErreurGestion('$libelle obligatoire.');
    return v;
  }

  /// Trace une consultation ou un téléchargement (dossier, photo, export).
  Future<void> noterAcces(Droits a, String action, {required String table, required String id}) async {
    if (!['consultation', 'telechargement', 'export'].contains(action)) throw ArgumentError(action);
    return depot.transaction((tx) => _noter(tx, a, action, table: table, id: id));
  }

  // --------------------------------------------------------- années scolaires

  Future<Enregistrement> creerAnnee(Droits a,
      {required String libelle, required DateTime debut, required DateTime fin, bool active = false}) async {
    _exiger(a, Permission.parametresModifier);
    if (!fin.isAfter(debut)) throw const ErreurGestion('La date de fin doit suivre la date de début.');
    return depot.transaction((tx) async {
      if ((await tx.chercher('annee_scolaire', {'libelle': libelle.trim()})).isNotEmpty) {
        throw const ErreurGestion('Cette année scolaire existe déjà.');
      }
      if (active) await _desactiverAnnees(tx, a);
      return _creer(tx, 'annee_scolaire',
          {'libelle': libelle.trim(), 'date_debut': formaterDate(debut), 'date_fin': formaterDate(fin), 'active': active}, a);
    });
  }

  Future<void> activerAnnee(Droits a, String id) async {
    _exiger(a, Permission.parametresModifier);
    return depot.transaction((tx) async {
      await _lire(tx, 'annee_scolaire', id);
      await _desactiverAnnees(tx, a);
      // Relue après la désactivation (elle a pu être modifiée).
      await _modifier(tx, (await tx.lire('annee_scolaire', id))!, {'active': true}, a);
    });
  }

  Future<void> _desactiverAnnees(TransactionServeur tx, Droits a) async {
    for (final x in await tx.chercher('annee_scolaire', {'active': true})) {
      await _modifier(tx, x, {'active': false}, a);
    }
  }

  // ----------------------------------------------------------- établissements

  static const _champsEtablissement = {
    'nom', 'code', 'type', 'statut', 'region', 'district_sanitaire', 'localite', 'responsable', 'telephone'
  };

  void _controlerEtablissement(Map<String, Object?> d) {
    for (final k in d.keys) {
      if (!_champsEtablissement.contains(k)) throw ErreurGestion('Champ inconnu : $k');
    }
    _requis(d, 'nom', 'Le nom');
    _requis(d, 'code', 'Le code');
    TypeEtablissement.depuisCode(_requis(d, 'type', 'Le type'));
    StatutEtablissement.depuisCode(_requis(d, 'statut', 'Le statut'));
  }

  Future<Enregistrement> creerEtablissement(Droits a, Map<String, Object?> donnees) async {
    _exiger(a, Permission.etablissementGerer);
    _controlerEtablissement(donnees);
    return depot.transaction((tx) async {
      final code = (donnees['code']! as String).trim().toUpperCase();
      if ((await tx.chercher('etablissement', {'code': code})).isNotEmpty) {
        throw const ErreurGestion('Un établissement porte déjà ce code.');
      }
      return _creer(tx, 'etablissement', {...donnees, 'code': code}, a);
    });
  }

  /// Importation d'une liste d'établissements validée : créations et mises
  /// à jour (seuls les champs fournis par la liste sont modifiés), en une
  /// seule transaction ; les établissements sont ensuite à affecter aux
  /// téléphones concernés.
  Future<ResultatImportEtablissements> importerEtablissements(Droits a, List<LigneEtablissementImport> lignes) async {
    _exiger(a, Permission.etablissementGerer);
    final b = bilanEtablissements(lignes);
    if (!b.validable) throw const ErreurGestion('La liste contient des lignes en erreur, ou rien à importer.');
    return depot.transaction((tx) async {
      var crees = 0, misAJour = 0;
      for (final l in lignes) {
        if (l.action == ActionEtablissement.ignorer || l.bloquee) continue;
        final d = l.donnees();
        final memeCode = await tx.chercher('etablissement', {'code': d['code']});
        if (l.action == ActionEtablissement.creer) {
          _controlerEtablissement(d);
          if (memeCode.isNotEmpty) throw ErreurGestion('Ligne ${l.numeroSource} : un établissement porte déjà le code ${d['code']}.');
          await _creer(tx, 'etablissement', d, a);
          crees++;
        } else {
          final e = await _lire(tx, 'etablissement', l.existantId!);
          if (memeCode.any((x) => x.id != e.id)) {
            throw ErreurGestion('Ligne ${l.numeroSource} : le code ${d['code']} est déjà celui d\'un autre établissement.');
          }
          final fusion = {for (final k in _champsEtablissement) k: e.donnees[k], ...d};
          _controlerEtablissement(fusion);
          if (_champsEtablissement.any((k) => fusion[k] != e.donnees[k])) {
            await _modifier(tx, e, fusion, a);
            misAJour++;
          }
        }
      }
      return ResultatImportEtablissements(crees, misAJour, b.ignorees);
    });
  }

  Future<Enregistrement> modifierEtablissement(Droits a, String id, Map<String, Object?> changements) async {
    _exiger(a, Permission.etablissementGerer);
    return depot.transaction((tx) async {
      final e = await _lire(tx, 'etablissement', id);
      final fusion = {
        for (final k in _champsEtablissement) k: e.donnees[k],
        ...changements,
        if (changements['code'] != null) 'code': (changements['code']! as String).trim().toUpperCase(),
      };
      _controlerEtablissement(fusion);
      final memeCode = await tx.chercher('etablissement', {'code': fusion['code']});
      if (memeCode.any((x) => x.id != id)) throw const ErreurGestion('Un établissement porte déjà ce code.');
      return _modifier(tx, e, fusion, a);
    });
  }

  /// Archivage (suppression logique). Refusé si des visites médicales sont
  /// rattachées à des élèves inscrits dans l'établissement.
  Future<void> archiverEtablissement(Droits a, String id) async {
    _exiger(a, Permission.etablissementArchiver);
    return depot.transaction((tx) async {
      final e = await _lire(tx, 'etablissement', id);
      final classes = await tx.chercher('classe', {'etablissement_id': id});
      for (final c in classes) {
        for (final i in await tx.chercher('inscription', {'classe_id': c.id})) {
          if ((await tx.chercher('visite', {'eleve_id': i.donnees['eleve_id']})).isNotEmpty) {
            throw const ErreurGestion(
                'Archivage impossible : des dossiers médicaux sont rattachés à des élèves de cet établissement.');
          }
        }
      }
      for (final c in classes) {
        await _modifier(tx, c, const {}, a, supprimer: true);
      }
      await _modifier(tx, e, const {}, a, supprimer: true);
    });
  }

  // ------------------------------------------------------------------ classes

  Future<Enregistrement> creerClasse(Droits a,
      {required String etablissementId, required String anneeScolaireId, required String libelle, String? niveau}) async {
    _exiger(a, Permission.etablissementGerer);
    if (libelle.trim().isEmpty) throw const ErreurGestion('Libellé de la classe obligatoire.');
    return depot.transaction((tx) async {
      await _lire(tx, 'etablissement', etablissementId);
      await _lire(tx, 'annee_scolaire', anneeScolaireId);
      // Même classe à l'écriture près (« 2nd G1 » et « 2nde G1 », « CM2-A » et « CM2 A »).
      final memes = await _classesDeMemeLibelle(tx, etablissementId, anneeScolaireId, libelle);
      if (memes.isNotEmpty) throw ErreurGestion('Cette classe existe déjà pour cette année (« ${memes.first.donnees['libelle']} »).');
      return _creer(
          tx,
          'classe',
          {
            'etablissement_id': etablissementId,
            'annee_scolaire_id': anneeScolaireId,
            'libelle': libelle.trim(),
            'niveau': _niveau(libelle, niveau),
          },
          a,
          etablissementId: etablissementId);
    });
  }

  Future<Enregistrement> modifierClasse(Droits a, String id, {required String libelle, String? niveau}) async {
    _exiger(a, Permission.etablissementGerer);
    return depot.transaction((tx) async {
      final c = await _lire(tx, 'classe', id);
      final memes = await _classesDeMemeLibelle(
          tx, c.donnees['etablissement_id']! as String, c.donnees['annee_scolaire_id']! as String, libelle);
      if (memes.any((x) => x.id != id)) throw const ErreurGestion('Cette classe existe déjà pour cette année.');
      return _modifier(tx, c, {'libelle': libelle.trim(), 'niveau': _niveau(libelle, niveau)}, a);
    });
  }

  Future<List<Enregistrement>> _classesDeMemeLibelle(
      TransactionServeur tx, String etablissementId, String anneeScolaireId, String libelle) async {
    final cle = cleClasse(libelle);
    return [
      for (final c in await tx.chercher('classe', {'etablissement_id': etablissementId, 'annee_scolaire_id': anneeScolaireId}))
        if (cleClasse('${c.donnees['libelle'] ?? ''}') == cle) c
    ];
  }

  /// Niveau saisi, sinon déduit du libellé (« 2nde G1 » → « 2NDE »).
  static String? _niveau(String libelle, String? niveau) =>
      niveau != null && niveau.trim().isNotEmpty ? niveau.trim() : niveauDeClasse(libelle);

  Future<void> archiverClasse(Droits a, String id) async {
    _exiger(a, Permission.etablissementGerer);
    return depot.transaction((tx) async {
      final c = await _lire(tx, 'classe', id);
      final inscrits = (await tx.chercher('inscription', {'classe_id': id})).where((i) => i.donnees['statut'] == 'inscrit');
      if (inscrits.isNotEmpty) throw const ErreurGestion('Archivage impossible : la classe compte des élèves inscrits.');
      await _modifier(tx, c, const {}, a, supprimer: true);
    });
  }

  // ------------------------------------------------------------------- élèves

  /// Nouvel élève ajouté à la main, inscrit dans une classe de l'année.
  /// [identite] : champs préparés par `identiteEleveSaisie`.
  Future<Enregistrement> creerEleve(Droits a, {required Map<String, Object?> identite, required String classeId}) async {
    if (!a.peutGererEleves) throw const ErreurGestion('Vous n\'êtes pas autorisé à ajouter un élève.');
    const champs = {'matricule', 'nom', 'prenoms', 'date_naissance', 'sexe', 'telephone_contact'};
    final donnees = {for (final k in champs) k: identite[k]};
    _requis(donnees, 'nom', 'Le nom');
    _requis(donnees, 'prenoms', 'Les prénoms');
    Sexe.depuisCode(_requis(donnees, 'sexe', 'Le sexe'));
    return depot.transaction((tx) async {
      final classe = await _lire(tx, 'classe', classeId);
      final etab = classe.donnees['etablissement_id']! as String;
      await _matriculeLibre(tx, donnees['matricule'] as String?);
      final e = await _creer(tx, 'eleve', donnees, a, etablissementId: etab);
      await _creer(
          tx,
          'inscription',
          {
            'eleve_id': e.id,
            'classe_id': classeId,
            'annee_scolaire_id': classe.donnees['annee_scolaire_id'],
            'statut': 'inscrit',
          },
          a,
          etablissementId: etab);
      return e;
    });
  }

  /// Inscrit un élève dans une classe pour l'année de cette classe : nouvelle
  /// inscription, ou changement de classe s'il est déjà inscrit cette année-là.
  Future<void> inscrireEleve(Droits a, String eleveId, String classeId) async {
    if (!a.peutGererEleves) throw const ErreurGestion('Vous n\'êtes pas autorisé à inscrire un élève.');
    return depot.transaction((tx) async {
      await _lire(tx, 'eleve', eleveId);
      final c = await _lire(tx, 'classe', classeId);
      final etab = c.donnees['etablissement_id']! as String;
      final annee = c.donnees['annee_scolaire_id']! as String;
      await reaffecterEleve(tx, eleveId, etab);
      final ins = await tx.chercher('inscription', {'eleve_id': eleveId, 'annee_scolaire_id': annee});
      if (ins.isEmpty) {
        await _creer(tx, 'inscription', {'eleve_id': eleveId, 'classe_id': classeId, 'annee_scolaire_id': annee, 'statut': 'inscrit'},
            a, etablissementId: etab);
      } else {
        await _modifier(tx, ins.first, {'classe_id': classeId, 'statut': 'inscrit'}, a, etablissementId: etab);
      }
    });
  }

  /// Un matricule ne peut appartenir qu'à un seul élève.
  Future<void> _matriculeLibre(TransactionServeur tx, String? matricule, {String? sauf}) async {
    if (matricule == null || matricule.isEmpty) return;
    final memes = [for (final e in await tx.chercher('eleve', {'matricule': matricule})) if (e.id != sauf) e];
    if (memes.isNotEmpty) {
      final d = memes.first.donnees;
      throw ErreurGestion('Le matricule $matricule est déjà celui de ${d['nom']} ${d['prenoms']} : ouvrez son dossier.');
    }
  }

  Future<Enregistrement> modifierEleve(Droits a, String id, Map<String, Object?> changements) async {
    if (!a.peutGererEleves) throw const ErreurGestion('Vous n\'êtes pas autorisé à modifier l\'identité d\'un élève.');
    const autorises = {'matricule', 'nom', 'prenoms', 'date_naissance', 'sexe', 'telephone_contact'};
    for (final k in changements.keys) {
      if (!autorises.contains(k)) throw ErreurGestion('Champ inconnu : $k');
    }
    return depot.transaction((tx) async {
      final e = await _lire(tx, 'eleve', id);
      final fusion = {...e.donnees, ...changements};
      _requis(fusion, 'nom', 'Le nom');
      _requis(fusion, 'prenoms', 'Les prénoms');
      Sexe.depuisCode(_requis(fusion, 'sexe', 'Le sexe'));
      final dn = fusion['date_naissance'] as String?;
      if (dn != null) {
        try {
          if (lireDate(dn).isAfter(horloge.maintenant())) throw const ErreurGestion('Date de naissance dans le futur.');
        } on FormatException {
          throw const ErreurGestion('Date de naissance invalide.');
        }
      }
      final normalises = {
        ...changements,
        if (changements.containsKey('nom')) 'nom': (changements['nom']! as String).trim().toUpperCase(),
        if (changements.containsKey('matricule')) 'matricule': normaliserMatricule(changements['matricule'] as String?),
      };
      if (normalises.containsKey('matricule')) await _matriculeLibre(tx, normalises['matricule'] as String?, sauf: id);
      return _modifier(tx, e, normalises, a);
    });
  }

  /// Change l'élève de classe pour l'année de l'inscription (éventuellement
  /// d'établissement : son dossier le suit).
  Future<void> changerClasse(Droits a, String inscriptionId, String nouvelleClasseId) async {
    _exiger(a, Permission.etablissementGerer);
    return depot.transaction((tx) async {
      final i = await _lire(tx, 'inscription', inscriptionId);
      final c = await _lire(tx, 'classe', nouvelleClasseId);
      if (c.donnees['annee_scolaire_id'] != i.donnees['annee_scolaire_id']) {
        throw const ErreurGestion('La nouvelle classe doit être de la même année scolaire.');
      }
      final etab = c.donnees['etablissement_id']! as String;
      await reaffecterEleve(tx, i.donnees['eleve_id']! as String, etab);
      await _modifier(tx, i, {'classe_id': nouvelleClasseId, 'statut': 'inscrit'}, a, etablissementId: etab);
    });
  }

  /// Importation d'une liste validée sur le poste central.
  Future<ResultatImportServeur> importerListe(
    Droits a, {
    required List<LigneImport> lignes,
    required String classeId,
    required String format,
    required String nomFichier,
    required String empreinteSha256,
  }) async =>
      (await importerListes(a,
              parties: [PartieImport(classeId, lignes)],
              format: format,
              nomFichier: nomFichier,
              empreinteSha256: empreinteSha256))
          .single;

  /// Importation d'un fichier de plusieurs classes, en une seule transaction :
  /// tout est importé, ou rien. Un lot d'importation par classe.
  Future<List<ResultatImportServeur>> importerListes(
    Droits a, {
    required List<PartieImport> parties,
    required String format,
    required String nomFichier,
    required String empreinteSha256,
  }) async {
    _exiger(a, Permission.importExecuter);
    if (parties.isEmpty) throw const ErreurGestion('Aucune classe à importer.');
    final b = bilan([for (final p in parties) ...p.lignes]);
    if (!b.validable) throw const ErreurGestion('Corrigez les lignes en erreur avant de valider l\'importation.');
    final classes = {for (final p in parties) p.classeId};
    if (classes.length != parties.length) {
      throw const ErreurGestion('Deux parties du fichier sont dirigées vers la même classe : regroupez-les ou changez de classe.');
    }
    return depot.transaction((tx) async => [
          for (final p in parties)
            await _importerDansClasse(tx, a,
                lignes: p.lignes,
                classeId: p.classeId,
                format: format,
                nomFichier: p.origine == null ? nomFichier : '$nomFichier — ${p.origine}',
                empreinteSha256: empreinteSha256),
        ]);
  }

  Future<ResultatImportServeur> _importerDansClasse(
    TransactionServeur tx,
    Droits a, {
    required List<LigneImport> lignes,
    required String classeId,
    required String format,
    required String nomFichier,
    required String empreinteSha256,
  }) async {
    final classe = await _lire(tx, 'classe', classeId);
    final etab = classe.donnees['etablissement_id']! as String;
    final annee = classe.donnees['annee_scolaire_id']! as String;
    final lot = await _creer(
        tx,
        'import_lot',
        {
          'classe_id': classeId,
          'utilisateur_id': a.utilisateurId,
          'fichier_nom': nomFichier,
          'format': format,
          'empreinte_sha256': empreinteSha256,
          'statut': 'valide',
          'nb_lignes': lignes.length,
        },
        a);
    var crees = 0, rattaches = 0, ignores = 0, changements = 0;
    for (final l in lignes) {
      String? eleveId;
      switch (l.action) {
        case ActionImport.ignorer:
          ignores++;
        case ActionImport.creer:
          eleveId = (await _creer(tx, 'eleve', donneesEleve(l), a, etablissementId: etab)).id;
          crees++;
        case ActionImport.rattacher:
          final e = await _lire(tx, 'eleve', l.eleveExistantId!);
          final nouvelles = donneesEleve(l);
          await _modifier(
              tx,
              e,
              {
                for (final k in ['matricule', 'date_naissance', 'telephone_contact'])
                  if (e.donnees[k] == null && nouvelles[k] != null) k: nouvelles[k],
              },
              a);
          eleveId = e.id;
          rattaches++;
      }
      if (eleveId != null) {
        await reaffecterEleve(tx, eleveId, etab);
        final ins = await tx.chercher('inscription', {'eleve_id': eleveId, 'annee_scolaire_id': annee});
        if (ins.isEmpty) {
          await _creer(tx, 'inscription',
              {'eleve_id': eleveId, 'classe_id': classeId, 'annee_scolaire_id': annee, 'statut': 'inscrit'}, a,
              etablissementId: etab);
        } else if (ins.first.donnees['classe_id'] != classeId || ins.first.donnees['statut'] != 'inscrit') {
          if (ins.first.donnees['classe_id'] != classeId) changements++;
          await _modifier(tx, ins.first, {'classe_id': classeId, 'statut': 'inscrit'}, a, etablissementId: etab);
        }
      }
      await tx.ecrire(Enregistrement(
        table: 'import_ligne',
        id: nouvelId(),
        version: 1,
        versionBase: 1,
        createdAt: horloge.maintenant(),
        updatedAt: horloge.maintenant(),
        createdBy: a.utilisateurId,
        updatedBy: a.utilisateurId,
        donnees: {
          'import_lot_id': lot.id,
          'numero': l.numeroSource,
          'donnees_extraites': {for (final e in l.brut.entries) e.key.name: e.value},
          'anomalies': [for (final x in l.anomalies) x.message, ...l.notes],
          'decision': l.action == ActionImport.ignorer ? 'rejeter' : 'garder',
          'eleve_id': eleveId,
        },
      ));
    }
    return ResultatImportServeur(lot.id, crees, rattaches, ignores, changements);
  }

  // ------------------------------------------------------------------ visites

  Future<Enregistrement> validerVisite(Droits a, String visiteId) async {
    _exiger(a, Permission.visiteValider);
    return depot.transaction((tx) async {
      final v = await _lire(tx, 'visite', visiteId);
      final statut = v.donnees['statut'];
      if (statut == 'valide') throw const ErreurGestion('Cette visite est déjà validée.');
      if (statut == 'ebauche') throw const ErreurGestion('Une ébauche ne peut pas être validée.');
      return _modifier(tx, v, {
        'statut': 'valide',
        'validateur_id': a.utilisateurId,
        'valide_le': formaterHorodatage(horloge.maintenant()),
      }, a);
    });
  }

  /// Rouvre une visite validée pour correction : elle redevient « enregistrée »,
  /// l'agent la corrige sur son téléphone puis la valide de nouveau.
  Future<Enregistrement> rouvrirVisite(Droits a, String visiteId, {required String motif}) async {
    _exiger(a, Permission.visiteRouvrir);
    if (motif.trim().isEmpty) throw const ErreurGestion('Indiquer le motif de la réouverture.');
    return depot.transaction((tx) async {
      final v = await _lire(tx, 'visite', visiteId);
      if (v.donnees['statut'] != 'valide') throw const ErreurGestion('Seule une visite validée peut être rouverte.');
      return _modifier(tx, v, {'statut': 'enregistre', 'validateur_id': null, 'valide_le': null}, a, motif: motif.trim());
    });
  }

  // ---------------------------------------------------------------- appareils

  /// Établissements affectés à un téléphone. Un établissement nouvellement
  /// affecté est rediffusé : le téléphone en reçoit toutes les données.
  Future<void> affecterEtablissements(Droits a, String appareilId, Set<String> etablissementIds) async {
    _exiger(a, Permission.comptesGerer);
    if (etablissementIds.isEmpty) throw const ErreurGestion('Affecter au moins un établissement.');
    return depot.transaction((tx) async {
      await _lire(tx, 'appareil', appareilId);
      final liens = await tx.chercher('appareil_etablissement', {'appareil_id': appareilId});
      final actuels = {for (final l in liens) l.donnees['etablissement_id']! as String};
      for (final l in liens) {
        if (!etablissementIds.contains(l.donnees['etablissement_id'])) await _modifier(tx, l, const {}, a, supprimer: true);
      }
      for (final etab in etablissementIds.difference(actuels)) {
        await _lire(tx, 'etablissement', etab);
        await _creer(tx, 'appareil_etablissement', {'appareil_id': appareilId, 'etablissement_id': etab}, a);
        await rediffuserEtablissement(tx, etab);
      }
    });
  }

  // ------------------------------------------------------------------ comptes

  Future<void> definirActif(Droits a, String utilisateurId, {required bool actif}) async {
    _exiger(a, Permission.comptesGerer);
    if (utilisateurId == a.utilisateurId) throw const ErreurGestion('Vous ne pouvez pas désactiver votre propre compte.');
    return depot.transaction((tx) async => _modifier(tx, await _lire(tx, 'utilisateur', utilisateurId), {'actif': actif}, a));
  }

  /// Suppression d'un compte. La ligne n'est pas effacée physiquement : les
  /// visites, inspections et le journal d'audit gardent leur auteur. Le compte
  /// disparaît des listes, ne permet plus de se connecter (ni sur le poste ni
  /// sur les téléphones, à leur prochaine synchronisation) et son identifiant
  /// est libéré pour un nouveau compte. Irréversible depuis l'application.
  Future<void> supprimerCompte(Droits a, String utilisateurId, {required String motif}) async {
    _exiger(a, Permission.comptesGerer);
    if (utilisateurId == a.utilisateurId) throw const ErreurGestion('Vous ne pouvez pas supprimer votre propre compte.');
    final m = motif.trim();
    if (m.isEmpty) throw const ErreurGestion('Indiquez le motif de la suppression.');
    return depot.transaction((tx) async {
      final u = await _lire(tx, 'utilisateur', utilisateurId);
      final roleAdmin = await tx.chercher('role', {'code': RoleCode.admin.code});
      if (roleAdmin.isNotEmpty && u.donnees['role_id'] == roleAdmin.first.id && u.donnees['actif'] == true) {
        final admins = await tx.chercher('utilisateur', {'role_id': roleAdmin.first.id, 'actif': true});
        if (admins.where((x) => x.id != u.id).isEmpty) {
          throw const ErreurGestion('Impossible de supprimer le dernier administrateur actif.');
        }
      }
      final identifiant = u.donnees['identifiant']! as String;
      await _modifier(
        tx,
        u,
        {
          'identifiant': '$identifiant~supprime~${u.id.substring(u.id.length - 8)}',
          'actif': false,
          'hash_mot_de_passe': null,
          'hash_pin': null,
        },
        a,
        supprimer: true,
        motif: m,
      );
    });
  }

  /// Nouveau mot de passe temporaire (à changer à la prochaine connexion) et
  /// déblocage du compte.
  Future<void> reinitialiserMotDePasse(Droits a, String utilisateurId, String motDePasseTemporaire) async {
    _exiger(a, Permission.comptesGerer);
    final erreur = controlerMotDePasse(motDePasseTemporaire);
    if (erreur != null) throw ErreurGestion(erreur);
    final empreinte = await hacheur.hacher(motDePasseTemporaire);
    await depot.transaction((tx) async => _modifier(
          tx,
          await _lire(tx, 'utilisateur', utilisateurId),
          {'hash_mot_de_passe': empreinte, 'doit_changer_mdp': true, 'echecs_connexion': 0, 'bloque_jusqua': null},
          a,
        ));
  }

  Future<void> changerRole(Droits a, String utilisateurId, RoleCode role) async {
    _exiger(a, Permission.comptesGerer);
    if (utilisateurId == a.utilisateurId) throw const ErreurGestion('Vous ne pouvez pas modifier votre propre rôle.');
    return depot.transaction((tx) async {
      final roles = await tx.chercher('role', {'code': role.code});
      if (roles.isEmpty) throw const ErreurGestion('Rôle introuvable.');
      await _modifier(tx, await _lire(tx, 'utilisateur', utilisateurId), {'role_id': roles.first.id}, a);
    });
  }

  // ------------------------------------------- grille d'inspection sanitaire

  static String _codeCritere(String libelle) {
    const accents = {'à': 'a', 'â': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'ô': 'o',
      'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', 'œ': 'oe'};
    final s = libelle.toLowerCase().split('').map((c) => accents[c] ?? c).join();
    final c = s.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return c.length > 40 ? c.substring(0, 40) : c;
  }

  /// Nouveau critère dans une rubrique (droit `parametres.modifier`). Il est
  /// envoyé aux téléphones et proposé dans les inspections suivantes.
  Future<Enregistrement> creerCritere(Droits a,
      {required RubriqueInspection rubrique, required String libelle, int? ordre}) async {
    _exiger(a, Permission.parametresModifier);
    final l = libelle.trim();
    if (l.isEmpty) throw const ErreurGestion('Libellé du critère obligatoire.');
    return depot.transaction((tx) async {
      final existants = await tx.chercher('critere_inspection', {});
      if (existants.any((c) => !c.supprime && c.donnees['rubrique'] == rubrique.code &&
          (c.donnees['libelle'] as String).trim().toLowerCase() == l.toLowerCase())) {
        throw const ErreurGestion('Ce critère existe déjà dans cette rubrique.');
      }
      final codes = {for (final c in existants) c.donnees['code']};
      final base = '${rubrique.code}_${_codeCritere(l)}';
      var code = base;
      for (var n = 2; codes.contains(code); n++) {
        code = '${base}_$n';
      }
      final ordreMax = existants
          .where((c) => c.donnees['rubrique'] == rubrique.code)
          .fold<int>(0, (m, c) => ((c.donnees['ordre'] as num?)?.toInt() ?? 0) > m ? (c.donnees['ordre'] as num).toInt() : m);
      return _creer(tx, 'critere_inspection',
          {'rubrique': rubrique.code, 'code': code, 'libelle': l, 'ordre': ordre ?? ordreMax + 1, 'actif': true}, a);
    });
  }

  /// Modifie le libellé ou l'ordre d'un critère. Les inspections déjà faites
  /// gardent leurs réponses ; le nouveau libellé s'affiche partout.
  Future<Enregistrement> modifierCritere(Droits a, String id, {String? libelle, int? ordre}) async {
    _exiger(a, Permission.parametresModifier);
    if (libelle != null && libelle.trim().isEmpty) throw const ErreurGestion('Libellé du critère obligatoire.');
    return depot.transaction((tx) async => _modifier(tx, await _lire(tx, 'critere_inspection', id),
        {if (libelle != null) 'libelle': libelle.trim(), if (ordre != null) 'ordre': ordre}, a));
  }

  /// Retire un critère des inspections suivantes (ou le rétablit), sans
  /// toucher aux inspections passées.
  Future<Enregistrement> activerCritere(Droits a, String id, {required bool actif}) async {
    _exiger(a, Permission.parametresModifier);
    return depot.transaction((tx) async {
      if (!actif) {
        final actifs = (await tx.chercher('critere_inspection', {})).where((c) => !c.supprime && c.donnees['actif'] == true);
        if (actifs.length <= 1) throw const ErreurGestion('La grille doit garder au moins un critère actif.');
      }
      return _modifier(tx, await _lire(tx, 'critere_inspection', id), {'actif': actif}, a);
    });
  }

  // --------------------------------------------------------------- paramètres

  /// Clés modifiables depuis l'écran des paramètres, avec leur contrôle.
  static final Map<String, String? Function(String v)> controlesParametres = {
    for (var i = 1; i <= 6; i++) 'entete_ligne_$i': (v) => v.length > 150 ? 'Ligne d\'en-tête trop longue.' : null,
    'nom_medecin_chef': (v) => v.length > 120 ? 'Nom trop long.' : null,
    'logo_png': (v) => v.length > 300000 ? 'Logo trop lourd (200 Ko au plus).' : null,
    'seuil_conformite_satisfaisant': _seuil,
    'seuil_conformite_moyen': _seuil,
    'verrouillage_mobile_minutes': _minutes,
    'verrouillage_windows_minutes': _minutes,
  };

  static String? _seuil(String v) {
    final x = double.tryParse(v.replaceAll(',', '.'));
    return x == null || x < 0 || x > 100 ? 'Seuil : nombre entre 0 et 100.' : null;
  }

  static String? _minutes(String v) {
    final x = int.tryParse(v);
    return x == null || x < 1 || x > 120 ? 'Durée : entre 1 et 120 minutes.' : null;
  }

  /// Enregistre des paramètres (droit `parametres.modifier`). Une valeur vide
  /// efface le paramètre (en-tête par défaut, pas de logo…).
  Future<void> definirParametres(Droits a, Map<String, String?> valeurs) async {
    _exiger(a, Permission.parametresModifier);
    for (final e in valeurs.entries) {
      final controle = controlesParametres[e.key];
      if (controle == null) throw ErreurGestion('Paramètre inconnu : ${e.key}.');
      final v = e.value?.trim() ?? '';
      final erreur = v.isEmpty ? null : controle(v);
      if (erreur != null) throw ErreurGestion(erreur);
    }
    final satisfaisant = valeurs['seuil_conformite_satisfaisant'];
    final moyen = valeurs['seuil_conformite_moyen'];
    await depot.transaction((tx) async {
      final existants = {for (final p in await tx.chercher('parametre', {})) p.donnees['cle'] as String: p};
      double? lire(String cle, String? nouveau) =>
          double.tryParse(((nouveau ?? existants[cle]?.donnees['valeur'] as String?) ?? '').replaceAll(',', '.'));
      if (satisfaisant != null || moyen != null) {
        final s = lire('seuil_conformite_satisfaisant', satisfaisant);
        final m = lire('seuil_conformite_moyen', moyen);
        if (s != null && m != null && m > s) {
          throw const ErreurGestion('Le seuil « moyen » doit être inférieur au seuil « satisfaisant ».');
        }
      }
      for (final e in valeurs.entries) {
        final v = e.value?.trim();
        final valeur = v == null || v.isEmpty ? null : v;
        final p = existants[e.key];
        if (p == null) {
          if (valeur != null) await _creer(tx, 'parametre', {'cle': e.key, 'valeur': valeur}, a);
        } else {
          await _modifier(tx, p, {'valeur': valeur}, a);
        }
      }
    });
  }

  /// Paramètres actuels (clé → valeur).
  Future<Map<String, String?>> parametres() async =>
      parametresDe(await depot.transaction((tx) => tx.chercher('parametre', {})));

  static Map<String, String?> parametresDe(Iterable<Enregistrement> lignes) => {
        for (final p in lignes)
          if (!p.supprime) p.donnees['cle']! as String: p.donnees['valeur'] as String?
      };

  /// Trace l'édition d'un rapport ou d'une liste (journal d'audit, action « export »).
  Future<void> noterExport(Droits a, String rapport, {String? table, String? id, Map<String, Object?>? detail}) =>
      depot.transaction((tx) => _noter(tx, a, 'export', table: table, id: id, apres: {'rapport': rapport, ...?detail}));
}
