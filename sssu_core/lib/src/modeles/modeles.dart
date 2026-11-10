/// Modèles métier principaux. Chaque modèle se convertit vers et depuis les
/// « données » d'un [Enregistrement] (colonnes métier au format canonique),
/// ce qui permet de les stocker localement et de les synchroniser.
///
/// Sur le téléphone, drift génère en plus une classe de ligne pour chacune des
/// tables (`EleveRow`, `VisiteRow`…). Les tables qui n'ont pas encore d'écran
/// (photos, inspections…) sont manipulées sous forme d'[Enregistrement] en phase 1.
library;

import '../commun/commun.dart';
import 'enums.dart';

typedef Donnees = Map<String, Object?>;

String? _s(Donnees d, String k) => d[k] as String?;
int? _i(Donnees d, String k) => (d[k] as num?)?.toInt();
double? _r(Donnees d, String k) => (d[k] as num?)?.toDouble();
bool _b(Donnees d, String k, {bool defaut = false}) => (d[k] as bool?) ?? defaut;
DateTime? _date(Donnees d, String k) => d[k] == null ? null : lireDate(d[k] as String);
DateTime? _ts(Donnees d, String k) => d[k] == null ? null : lireHorodatage(d[k] as String);

class AnneeScolaire {
  final String id;
  final String libelle;
  final DateTime dateDebut;
  final DateTime dateFin;
  final bool active;

  const AnneeScolaire({
    required this.id,
    required this.libelle,
    required this.dateDebut,
    required this.dateFin,
    this.active = false,
  });

  factory AnneeScolaire.depuisDonnees(String id, Donnees d) => AnneeScolaire(
        id: id,
        libelle: _s(d, 'libelle')!,
        dateDebut: _date(d, 'date_debut')!,
        dateFin: _date(d, 'date_fin')!,
        active: _b(d, 'active'),
      );

  Donnees versDonnees() => {
        'libelle': libelle,
        'date_debut': formaterDate(dateDebut),
        'date_fin': formaterDate(dateFin),
        'active': active,
      };
}

class Etablissement {
  final String id;
  final String nom;
  final String code;
  final TypeEtablissement type;
  final StatutEtablissement statut;
  final String? region;
  final String? districtSanitaire;
  final String? localite;
  final String? responsable;
  final String? telephone;

  const Etablissement({
    required this.id,
    required this.nom,
    required this.code,
    required this.type,
    required this.statut,
    this.region,
    this.districtSanitaire,
    this.localite,
    this.responsable,
    this.telephone,
  });

  factory Etablissement.depuisDonnees(String id, Donnees d) => Etablissement(
        id: id,
        nom: _s(d, 'nom')!,
        code: _s(d, 'code')!,
        type: TypeEtablissement.depuisCode(_s(d, 'type')!),
        statut: StatutEtablissement.depuisCode(_s(d, 'statut')!),
        region: _s(d, 'region'),
        districtSanitaire: _s(d, 'district_sanitaire'),
        localite: _s(d, 'localite'),
        responsable: _s(d, 'responsable'),
        telephone: _s(d, 'telephone'),
      );

  Donnees versDonnees() => {
        'nom': nom,
        'code': code,
        'type': type.code,
        'statut': statut.code,
        'region': region,
        'district_sanitaire': districtSanitaire,
        'localite': localite,
        'responsable': responsable,
        'telephone': telephone,
      };
}

class Classe {
  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String libelle;
  final String? niveau;

  const Classe({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    required this.libelle,
    this.niveau,
  });

  factory Classe.depuisDonnees(String id, Donnees d) => Classe(
        id: id,
        etablissementId: _s(d, 'etablissement_id')!,
        anneeScolaireId: _s(d, 'annee_scolaire_id')!,
        libelle: _s(d, 'libelle')!,
        niveau: _s(d, 'niveau'),
      );

  Donnees versDonnees() => {
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'libelle': libelle,
        'niveau': niveau,
      };
}

/// Dossier permanent de l'élève : il ne dépend ni de la classe ni de l'année.
class Eleve {
  final String id;
  final String? matricule;
  final String nom;
  final String prenoms;
  final DateTime? dateNaissance;
  final Sexe sexe;
  final String? telephoneContact;

  const Eleve({
    required this.id,
    this.matricule,
    required this.nom,
    required this.prenoms,
    this.dateNaissance,
    required this.sexe,
    this.telephoneContact,
  });

  factory Eleve.depuisDonnees(String id, Donnees d) => Eleve(
        id: id,
        matricule: _s(d, 'matricule'),
        nom: _s(d, 'nom')!,
        prenoms: _s(d, 'prenoms')!,
        dateNaissance: _date(d, 'date_naissance'),
        sexe: Sexe.depuisCode(_s(d, 'sexe')!),
        telephoneContact: _s(d, 'telephone_contact'),
      );

  Donnees versDonnees() => {
        'matricule': matricule,
        'nom': nom,
        'prenoms': prenoms,
        'date_naissance': dateNaissance == null ? null : formaterDate(dateNaissance!),
        'sexe': sexe.code,
        'telephone_contact': telephoneContact,
      };

  String get nomComplet => '$nom $prenoms';
}

/// Inscription annuelle d'un élève dans une classe.
class Inscription {
  final String id;
  final String eleveId;
  final String classeId;
  final String anneeScolaireId;
  final StatutInscription statut;

  const Inscription({
    required this.id,
    required this.eleveId,
    required this.classeId,
    required this.anneeScolaireId,
    this.statut = StatutInscription.inscrit,
  });

  factory Inscription.depuisDonnees(String id, Donnees d) => Inscription(
        id: id,
        eleveId: _s(d, 'eleve_id')!,
        classeId: _s(d, 'classe_id')!,
        anneeScolaireId: _s(d, 'annee_scolaire_id')!,
        statut: StatutInscription.depuisCode(_s(d, 'statut') ?? 'inscrit'),
      );

  Donnees versDonnees() => {
        'eleve_id': eleveId,
        'classe_id': classeId,
        'annee_scolaire_id': anneeScolaireId,
        'statut': statut.code,
      };
}

class Utilisateur {
  final String id;
  final String identifiant;
  final String nom;
  final String? prenoms;
  final String? fonction;
  final String? structure;
  final String roleId;
  final String? hashMotDePasse;
  final String? hashPin;
  final bool actif;
  final bool doitChangerMotDePasse;
  final int echecsConnexion;
  final DateTime? bloqueJusqua;

  const Utilisateur({
    required this.id,
    required this.identifiant,
    required this.nom,
    this.prenoms,
    this.fonction,
    this.structure,
    required this.roleId,
    this.hashMotDePasse,
    this.hashPin,
    this.actif = true,
    this.doitChangerMotDePasse = true,
    this.echecsConnexion = 0,
    this.bloqueJusqua,
  });

  factory Utilisateur.depuisDonnees(String id, Donnees d) => Utilisateur(
        id: id,
        identifiant: _s(d, 'identifiant')!,
        nom: _s(d, 'nom')!,
        prenoms: _s(d, 'prenoms'),
        fonction: _s(d, 'fonction'),
        structure: _s(d, 'structure'),
        roleId: _s(d, 'role_id')!,
        hashMotDePasse: _s(d, 'hash_mot_de_passe'),
        hashPin: _s(d, 'hash_pin'),
        actif: _b(d, 'actif', defaut: true),
        doitChangerMotDePasse: _b(d, 'doit_changer_mdp', defaut: true),
        echecsConnexion: _i(d, 'echecs_connexion') ?? 0,
        bloqueJusqua: _ts(d, 'bloque_jusqua'),
      );

  Donnees versDonnees() => {
        'identifiant': identifiant,
        'nom': nom,
        'prenoms': prenoms,
        'fonction': fonction,
        'structure': structure,
        'role_id': roleId,
        'hash_mot_de_passe': hashMotDePasse,
        'hash_pin': hashPin,
        'actif': actif,
        'doit_changer_mdp': doitChangerMotDePasse,
        'echecs_connexion': echecsConnexion,
        'bloque_jusqua': bloqueJusqua == null ? null : formaterHorodatage(bloqueJusqua!),
      };

  Utilisateur copier({
    String? hashMotDePasse,
    String? hashPin,
    bool? actif,
    bool? doitChangerMotDePasse,
    int? echecsConnexion,
    DateTime? bloqueJusqua,
    bool effacerBlocage = false,
  }) =>
      Utilisateur(
        id: id,
        identifiant: identifiant,
        nom: nom,
        prenoms: prenoms,
        fonction: fonction,
        structure: structure,
        roleId: roleId,
        hashMotDePasse: hashMotDePasse ?? this.hashMotDePasse,
        hashPin: hashPin ?? this.hashPin,
        actif: actif ?? this.actif,
        doitChangerMotDePasse: doitChangerMotDePasse ?? this.doitChangerMotDePasse,
        echecsConnexion: echecsConnexion ?? this.echecsConnexion,
        bloqueJusqua: effacerBlocage ? null : (bloqueJusqua ?? this.bloqueJusqua),
      );

  String get nomAffiche => prenoms == null ? nom : '$prenoms $nom';
}

/// Visite médicale (en-tête, constantes et conclusion). Les antécédents,
/// examens par appareil et pathologies sont dans leurs propres tables.
class Visite {
  final String id;
  final String eleveId;
  final String? inscriptionId;
  final String agentId;
  final String? appareilId;
  final String? validateurId;
  final DateTime dateVisite;
  final String? structureOrigine;
  final StatutVisite statut;
  final double? poidsKg;
  final double? tailleCm;
  final double? imc;
  final String? imcInterpretation;
  final int? taSys;
  final int? taDia;
  final double? temperatureC;
  final int? fc;
  final int? fr;
  final ConclusionVisite? conclusion;
  final String? diagnostic;
  final String? conduiteATenir;
  final String? traitementConseils;
  final String? structureReference;
  final DateTime? dateControle;
  final String? observations;
  final DateTime? valideLe;

  const Visite({
    required this.id,
    required this.eleveId,
    this.inscriptionId,
    required this.agentId,
    this.appareilId,
    this.validateurId,
    required this.dateVisite,
    this.structureOrigine,
    this.statut = StatutVisite.ebauche,
    this.poidsKg,
    this.tailleCm,
    this.imc,
    this.imcInterpretation,
    this.taSys,
    this.taDia,
    this.temperatureC,
    this.fc,
    this.fr,
    this.conclusion,
    this.diagnostic,
    this.conduiteATenir,
    this.traitementConseils,
    this.structureReference,
    this.dateControle,
    this.observations,
    this.valideLe,
  });

  factory Visite.depuisDonnees(String id, Donnees d) => Visite(
        id: id,
        eleveId: _s(d, 'eleve_id')!,
        inscriptionId: _s(d, 'inscription_id'),
        agentId: _s(d, 'agent_id')!,
        appareilId: _s(d, 'appareil_id'),
        validateurId: _s(d, 'validateur_id'),
        dateVisite: _date(d, 'date_visite')!,
        structureOrigine: _s(d, 'structure_origine'),
        statut: StatutVisite.depuisCode(_s(d, 'statut') ?? 'ebauche'),
        poidsKg: _r(d, 'poids_kg'),
        tailleCm: _r(d, 'taille_cm'),
        imc: _r(d, 'imc'),
        imcInterpretation: _s(d, 'imc_interpretation'),
        taSys: _i(d, 'ta_sys'),
        taDia: _i(d, 'ta_dia'),
        temperatureC: _r(d, 'temperature_c'),
        fc: _i(d, 'fc'),
        fr: _i(d, 'fr'),
        conclusion: _s(d, 'conclusion') == null ? null : ConclusionVisite.depuisCode(_s(d, 'conclusion')!),
        diagnostic: _s(d, 'diagnostic'),
        conduiteATenir: _s(d, 'conduite_a_tenir'),
        traitementConseils: _s(d, 'traitement_conseils'),
        structureReference: _s(d, 'structure_reference'),
        dateControle: _date(d, 'date_controle'),
        observations: _s(d, 'observations'),
        valideLe: _ts(d, 'valide_le'),
      );

  Donnees versDonnees() => {
        'eleve_id': eleveId,
        'inscription_id': inscriptionId,
        'agent_id': agentId,
        'appareil_id': appareilId,
        'validateur_id': validateurId,
        'date_visite': formaterDate(dateVisite),
        'structure_origine': structureOrigine,
        'statut': statut.code,
        'poids_kg': poidsKg,
        'taille_cm': tailleCm,
        'imc': imc,
        'imc_interpretation': imcInterpretation,
        'ta_sys': taSys,
        'ta_dia': taDia,
        'temperature_c': temperatureC,
        'fc': fc,
        'fr': fr,
        'conclusion': conclusion?.code,
        'diagnostic': diagnostic,
        'conduite_a_tenir': conduiteATenir,
        'traitement_conseils': traitementConseils,
        'structure_reference': structureReference,
        'date_controle': dateControle == null ? null : formaterDate(dateControle!),
        'observations': observations,
        'valide_le': valideLe == null ? null : formaterHorodatage(valideLe!),
      };
}
