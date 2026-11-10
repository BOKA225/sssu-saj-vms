/// Indice de masse corporelle (IMC) et son interprétation.
///
/// - De 5 à 19 ans (61 à 228 mois) : références de croissance OMS 2007
///   « IMC pour l'âge », par le score z calculé avec la méthode LMS.
///   Les valeurs L, M, S officielles de l'OMS (une ligne par mois et par sexe)
///   sont lues dans un fichier CSV fourni par le service : elles ne sont pas
///   recopiées dans le code (voir README, section « Tables OMS »).
/// - À partir de 19 ans : seuils adultes de l'OMS (18,5 / 25 / 30).
/// - Avant 5 ans : l'interprétation relève des normes OMS 0-5 ans
///   (poids pour la taille), qui ne sont pas intégrées en phase 1.
library;

import 'dart:math' as math;

import '../modeles/enums.dart';
import 'age.dart';

/// IMC en kg/m², arrondi à une décimale.
double calculerImc({required double poidsKg, required double tailleCm}) {
  if (poidsKg <= 0 || tailleCm <= 0) {
    throw ArgumentError('Le poids et la taille doivent être strictement positifs.');
  }
  final tailleM = tailleCm / 100;
  final imc = poidsKg / (tailleM * tailleM);
  return (imc * 10).roundToDouble() / 10;
}

enum CategorieImc {
  maigreurSevere('maigreur_severe', 'Maigreur sévère'),
  maigreur('maigreur', 'Maigreur'),
  normal('normal', 'Corpulence normale'),
  surpoids('surpoids', 'Surpoids'),
  obesite('obesite', 'Obésité'),
  nonInterpretable('non_interpretable', 'Non interprétable');

  /// Valeur stockée dans `visite.imc_interpretation`.
  final String code;
  final String libelle;
  const CategorieImc(this.code, this.libelle);
}

enum MethodeImc { oms5a19ans, adulte, aucune }

class InterpretationImc {
  final CategorieImc categorie;
  final MethodeImc methode;

  /// Score z IMC pour l'âge (uniquement entre 5 et 19 ans).
  final double? scoreZ;
  final String? message;

  const InterpretationImc(this.categorie, this.methode, {this.scoreZ, this.message});
}

/// Paramètres L, M, S d'une ligne de table OMS.
class Lms {
  final double l;
  final double m;
  final double s;
  const Lms(this.l, this.m, this.s);
}

/// Source des paramètres LMS (IMC pour l'âge) par sexe et âge en mois.
abstract class TableImcOms {
  /// Paramètres pour l'âge en mois révolus, ou `null` si absent de la table.
  Lms? lms(Sexe sexe, int ageMois);
}

/// Table OMS lue depuis deux fichiers CSV (un par sexe) au format :
///
/// ```
/// mois,L,M,S
/// 61,<L>,<M>,<S>
/// 62,<L>,<M>,<S>
/// ```
///
/// (valeurs à recopier des fichiers officiels OMS « BMI-for-age 5-19 years »).
///
/// Les séparateurs `,` ou `;` et la virgule décimale sont acceptés.
class TableImcOmsCsv implements TableImcOms {
  final Map<int, Lms> _garcons;
  final Map<int, Lms> _filles;

  TableImcOmsCsv._(this._garcons, this._filles);

  factory TableImcOmsCsv.depuisCsv({required String garcons, required String filles}) =>
      TableImcOmsCsv._(_lire(garcons), _lire(filles));

  static Map<int, Lms> _lire(String csv) {
    final resultat = <int, Lms>{};
    final lignes = csv.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    for (var i = 0; i < lignes.length; i++) {
      final ligne = lignes[i];
      final sep = ligne.contains(';') ? ';' : ',';
      final champs = ligne.split(sep).map((c) => c.trim()).toList();
      if (i == 0 && int.tryParse(champs.first) == null) continue; // en-tête
      if (champs.length < 4) {
        throw FormatException('Ligne ${i + 1} : 4 colonnes attendues (mois, L, M, S)', ligne);
      }
      double nombre(String c) => double.parse(c.replaceAll(',', '.'));
      resultat[int.parse(champs[0])] = Lms(nombre(champs[1]), nombre(champs[2]), nombre(champs[3]));
    }
    return resultat;
  }

  @override
  Lms? lms(Sexe sexe, int ageMois) => (sexe == Sexe.masculin ? _garcons : _filles)[ageMois];

  int get nombreDeLignes => _garcons.length + _filles.length;
}

/// Score z selon la méthode LMS : z = ((IMC / M)^L − 1) / (L × S).
double scoreZLms(double imc, Lms p) {
  if (p.l.abs() < 1e-9) return math.log(imc / p.m) / p.s;
  return (math.pow(imc / p.m, p.l) - 1) / (p.l * p.s);
}

const int _ageMinOmsMois = 61; // 5 ans et 1 mois
const int _ageMaxOmsMois = 228; // 19 ans

/// Interprète l'IMC d'un élève selon son âge et son sexe.
///
/// Remarque : l'OMS « restreint » les scores z au-delà de ±3 pour leur valeur
/// numérique ; cette correction ne change pas le classement (z < −3 reste
/// z < −3), elle n'est donc pas nécessaire ici.
InterpretationImc interpreterImc({
  required double imc,
  required Sexe sexe,
  required Age age,
  TableImcOms? table,
}) {
  final mois = age.enMois;
  if (mois < _ageMinOmsMois) {
    return const InterpretationImc(CategorieImc.nonInterpretable, MethodeImc.aucune,
        message: 'Moins de 5 ans : se référer aux normes OMS 0-5 ans (poids pour la taille).');
  }
  if (mois > _ageMaxOmsMois) {
    final CategorieImc c;
    if (imc < 16) {
      c = CategorieImc.maigreurSevere;
    } else if (imc < 18.5) {
      c = CategorieImc.maigreur;
    } else if (imc < 25) {
      c = CategorieImc.normal;
    } else if (imc < 30) {
      c = CategorieImc.surpoids;
    } else {
      c = CategorieImc.obesite;
    }
    return InterpretationImc(c, MethodeImc.adulte);
  }
  final p = table?.lms(sexe, mois);
  if (p == null) {
    return const InterpretationImc(CategorieImc.nonInterpretable, MethodeImc.aucune,
        message: 'Table OMS de l\'IMC pour l\'âge non chargée pour cet âge.');
  }
  final z = scoreZLms(imc, p);
  final CategorieImc c;
  if (z < -3) {
    c = CategorieImc.maigreurSevere;
  } else if (z < -2) {
    c = CategorieImc.maigreur;
  } else if (z > 2) {
    c = CategorieImc.obesite;
  } else if (z > 1) {
    c = CategorieImc.surpoids;
  } else {
    c = CategorieImc.normal;
  }
  return InterpretationImc(c, MethodeImc.oms5a19ans, scoreZ: (z * 100).roundToDouble() / 100);
}
