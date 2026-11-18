/// Vaccination : vaccins du PEV et hors PEV (obligatoires ou recommandés,
/// liste modifiable sur le poste central), suivi vaccinal des enfants du
/// préscolaire (fait ou non fait pour chaque vaccin, carnet présenté, parent
/// ou tuteur, observations) et vaccin HPV des filles de 9 à 14 ans lors de la
/// visite médicale systématique.
library;

import 'dart:convert';

import '../commun/chiffrement.dart';
import '../commun/commun.dart';
import '../import/reconnaissance.dart';
import '../modeles/enums.dart';
import '../regles/age.dart';
import '../statistiques/statistiques.dart' show taux;
import '../sync/enregistrement.dart';

/// Code du vaccin HPV dans la liste des vaccins.
const codeVaccinHpv = 'HPV';

/// Âges (en années révolues) des filles concernées par le vaccin HPV.
const ageMinHpv = 9;
const ageMaxHpv = 14;

/// Niveaux du préscolaire (codes de `lireClasse`).
const niveauxPrescolaire = {'PS', 'MS', 'GS'};

/// Classe du préscolaire (petite, moyenne, grande section), d'après son
/// libellé, sinon son niveau ; toutes les classes d'un établissement
/// préscolaire.
bool classePrescolaire(String? libelle, {String? niveau, String? typeEtablissement}) {
  if (typeEtablissement == TypeEtablissement.prescolaire.code) return true;
  final n = (libelle == null ? null : lireClasse(libelle)?.niveau) ??
      (niveau == null ? null : lireClasse(niveau)?.niveau ?? niveau.toUpperCase());
  return niveauxPrescolaire.contains(n);
}

/// Le vaccin HPV est-il à vérifier lors de cette visite ? Visite
/// systématique d'une fille de 9 à 14 ans (âge à la date de la visite).
bool hpvConcerne({required Sexe sexe, required DateTime? dateNaissance, required DateTime dateVisite, TypeVisite type = TypeVisite.systematique}) {
  if (type != TypeVisite.systematique || sexe != Sexe.feminin || dateNaissance == null) return false;
  if (dateNaissance.isAfter(dateVisite)) return false;
  final a = calculerAge(dateNaissance, dateVisite).annees;
  return a >= ageMinHpv && a <= ageMaxHpv;
}

/// Vaccin de la liste (table `vaccin`).
class Vaccin {
  final String id;
  final String code;
  final String libelle;
  final ProgrammeVaccin programme;
  final StatutVaccin statut;

  /// Âge ou population cible (texte libre : « À la naissance », « 9 mois »…).
  final String? cible;

  /// Affiché dans la liste de vaccination du préscolaire.
  final bool prescolaire;
  final bool actif;
  final int ordre;
  const Vaccin({
    required this.id,
    required this.code,
    required this.libelle,
    required this.programme,
    required this.statut,
    this.cible,
    this.prescolaire = true,
    this.actif = true,
    this.ordre = 0,
  });

  factory Vaccin.depuisDonnees(String id, Map<String, Object?> d) => Vaccin(
        id: id,
        code: d['code']! as String,
        libelle: d['libelle']! as String,
        programme: ProgrammeVaccin.depuisCode(d['programme']! as String),
        statut: StatutVaccin.depuisCode(d['statut']! as String),
        cible: d['cible'] as String?,
        prescolaire: _booleen(d['prescolaire'], true),
        actif: _booleen(d['actif'], true),
        ordre: (d['ordre'] as num?)?.toInt() ?? 0,
      );

  factory Vaccin.depuis(Enregistrement e) => Vaccin.depuisDonnees(e.id, e.donnees);

  Map<String, Object?> versDonnees() => {
        'code': code,
        'libelle': libelle,
        'programme': programme.code,
        'statut': statut.code,
        'cible': cible,
        'prescolaire': prescolaire,
        'actif': actif,
        'ordre': ordre,
      };

  bool get estHpv => code == codeVaccinHpv;

  Vaccin copieAvec({
    String? libelle,
    ProgrammeVaccin? programme,
    StatutVaccin? statut,
    String? cible,
    bool? prescolaire,
    bool? actif,
    int? ordre,
  }) =>
      Vaccin(
        id: id,
        code: code,
        libelle: libelle ?? this.libelle,
        programme: programme ?? this.programme,
        statut: statut ?? this.statut,
        cible: cible ?? this.cible,
        prescolaire: prescolaire ?? this.prescolaire,
        actif: actif ?? this.actif,
        ordre: ordre ?? this.ordre,
      );

  /// Ordre d'affichage : PEV puis hors PEV ; obligatoires puis recommandés ;
  /// puis l'ordre et le libellé.
  static int comparer(Vaccin a, Vaccin b) {
    final p = a.programme.index.compareTo(b.programme.index);
    if (p != 0) return p;
    final s = a.statut.index.compareTo(b.statut.index);
    if (s != 0) return s;
    final o = a.ordre.compareTo(b.ordre);
    return o != 0 ? o : a.libelle.compareTo(b.libelle);
  }
}

bool _booleen(Object? v, bool defaut) => switch (v) {
      null => defaut,
      final bool b => b,
      final num n => n != 0,
      _ => v.toString() == 'true' || v.toString() == '1',
    };

/// Vaccins actifs de la liste du préscolaire, dans l'ordre d'affichage.
List<Vaccin> vaccinsPrescolaire(Iterable<Vaccin> vaccins) =>
    [for (final v in vaccins) if (v.actif && v.prescolaire) v]..sort(Vaccin.comparer);

/// Identifiant du suivi vaccinal d'un enfant : le même sur tous les
/// appareils, pour qu'un enfant n'ait qu'une fiche même si deux téléphones la
/// créent avant de se synchroniser (UUID calculé, version 5).
String idSuiviVaccinal(String eleveId) {
  final h = sha256HexTexte('sssu-saj-vms/suivi_vaccinal/$eleveId').substring(0, 32).split('');
  h[12] = '5';
  h[16] = '89ab'[int.parse(h[16], radix: 16) & 3];
  final s = h.join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

/// Suivi vaccinal d'un enfant (table `suivi_vaccinal`) : pour chaque vaccin
/// vérifié, fait (`true`) ou non fait (`false`) ; un vaccin absent n'est pas
/// renseigné.
class SuiviVaccinal {
  final String eleveId;
  String parentTuteur;
  String parentTelephone;

  /// Carnet de vaccination présenté lors de la vérification (`null` : non renseigné).
  bool? carnetPresente;
  String observations;
  DateTime? dateVerification;

  /// Identifiant du vaccin → fait ou non fait.
  final Map<String, bool> vaccins;

  SuiviVaccinal({
    required this.eleveId,
    this.parentTuteur = '',
    this.parentTelephone = '',
    this.carnetPresente,
    this.observations = '',
    this.dateVerification,
    Map<String, bool>? vaccins,
  }) : vaccins = vaccins ?? {};

  String get id => idSuiviVaccinal(eleveId);

  factory SuiviVaccinal.depuisDonnees(Map<String, Object?> d) {
    final brut = d['vaccins'];
    final vaccins = <String, bool>{};
    if (brut is String && brut.trim().isNotEmpty) {
      final j = jsonDecode(brut);
      if (j is Map) {
        j.forEach((k, v) {
          if (v is bool) vaccins[k.toString()] = v;
        });
      }
    }
    final carnet = d['carnet_presente'];
    return SuiviVaccinal(
      eleveId: d['eleve_id']! as String,
      parentTuteur: (d['parent_tuteur'] as String?) ?? '',
      parentTelephone: (d['parent_telephone'] as String?) ?? '',
      carnetPresente: carnet == null ? null : _booleen(carnet, false),
      observations: (d['observations'] as String?) ?? '',
      dateVerification: d['date_verification'] == null ? null : lireDate(d['date_verification']!.toString().substring(0, 10)),
      vaccins: vaccins,
    );
  }

  /// Colonnes de la table `suivi_vaccinal`. Les vaccins sont rangés par
  /// identifiant, pour qu'un même suivi donne toujours le même texte.
  Map<String, Object?> versDonnees() {
    final cles = vaccins.keys.toList()..sort();
    return {
      'eleve_id': eleveId,
      'parent_tuteur': _vide(parentTuteur),
      'parent_telephone': _vide(parentTelephone),
      'carnet_presente': carnetPresente,
      'vaccins': jsonEncode({for (final k in cles) k: vaccins[k]}),
      'observations': _vide(observations),
      'date_verification': dateVerification == null ? null : formaterDate(dateVerification!),
    };
  }

  /// Rien n'est renseigné (fiche vide).
  bool get vide =>
      vaccins.isEmpty &&
      carnetPresente == null &&
      parentTuteur.trim().isEmpty &&
      parentTelephone.trim().isEmpty &&
      observations.trim().isEmpty;

  SuiviVaccinal copie() => SuiviVaccinal(
        eleveId: eleveId,
        parentTuteur: parentTuteur,
        parentTelephone: parentTelephone,
        carnetPresente: carnetPresente,
        observations: observations,
        dateVerification: dateVerification,
        vaccins: {...vaccins},
      );

  static String? _vide(String s) => s.trim().isEmpty ? null : s.trim();
}

/// État vaccinal d'un enfant au regard des vaccins obligatoires de la liste
/// du préscolaire.
enum EtatVaccinal {
  aJour('À jour', 'Tous les vaccins obligatoires sont faits'),
  incomplet('Incomplet', 'Au moins un vaccin obligatoire non fait ou non vérifié'),
  nonRenseigne('Non renseigné', 'Aucun vaccin obligatoire vérifié');

  final String libelle;
  final String description;
  const EtatVaccinal(this.libelle, this.description);
}

EtatVaccinal etatVaccinal(SuiviVaccinal? s, List<Vaccin> vaccins) {
  final obligatoires = [for (final v in vaccins) if (v.actif && v.statut == StatutVaccin.obligatoire) v.id];
  if (s == null || obligatoires.every((id) => !s.vaccins.containsKey(id))) return EtatVaccinal.nonRenseigne;
  return obligatoires.every((id) => s.vaccins[id] == true) ? EtatVaccinal.aJour : EtatVaccinal.incomplet;
}

/// Enfant du préscolaire, avec son suivi vaccinal (liste du poste central).
class EnfantVaccination {
  final String eleveId;
  final String? matricule;
  final String nom;
  final String prenoms;
  final Sexe sexe;
  final DateTime? dateNaissance;
  final String? telephoneContact;
  final String etablissementId;
  final String etablissement;
  final String classeId;
  final String classe;
  final SuiviVaccinal? suivi;
  const EnfantVaccination({
    required this.eleveId,
    this.matricule,
    required this.nom,
    required this.prenoms,
    required this.sexe,
    this.dateNaissance,
    this.telephoneContact,
    required this.etablissementId,
    required this.etablissement,
    required this.classeId,
    required this.classe,
    this.suivi,
  });

  String get nomComplet => '$nom $prenoms';

  /// Fait (`true`), non fait (`false`) ou non renseigné (`null`).
  bool? vaccin(String vaccinId) => suivi?.vaccins[vaccinId];
}

/// Couverture d'un vaccin parmi des enfants.
class CouvertureVaccin {
  final Vaccin vaccin;
  final int enfants;
  final int faits;
  final int nonFaits;
  const CouvertureVaccin(this.vaccin, this.enfants, this.faits, this.nonFaits);
  int get nonRenseignes => enfants - faits - nonFaits;

  /// Enfants vaccinés / enfants × 100.
  double? get tauxCouverture => taux(faits, enfants);
}

List<CouvertureVaccin> couvertureVaccins(List<EnfantVaccination> enfants, List<Vaccin> vaccins) => [
      for (final v in vaccins)
        CouvertureVaccin(
          v,
          enfants.length,
          enfants.where((e) => e.vaccin(v.id) == true).length,
          enfants.where((e) => e.vaccin(v.id) == false).length,
        )
    ];

/// Nombre d'enfants dans chaque état vaccinal.
Map<EtatVaccinal, int> repartitionEtats(List<EnfantVaccination> enfants, List<Vaccin> vaccins) {
  final r = {for (final e in EtatVaccinal.values) e: 0};
  for (final e in enfants) {
    final etat = etatVaccinal(e.suivi, vaccins);
    r[etat] = r[etat]! + 1;
  }
  return r;
}
