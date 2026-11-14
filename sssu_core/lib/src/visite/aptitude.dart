/// Visite médicale d'aptitude : elle concerne les classes d'examen, la 3ème
/// (BEPC) et la terminale (baccalauréat), de l'enseignement général comme de
/// l'enseignement technique (Tle D, Tle G2…).
library;

import '../import/reconnaissance.dart';

/// Niveaux concernés (codes de `lireClasse`).
const niveauxAptitude = {'3EME', 'TLE'};

/// La classe est-elle concernée par la visite d'aptitude ? D'après son
/// libellé (« 3ème 2 », « Terminale D », « Tle G1 »), sinon son niveau.
bool classeConcerneeParAptitude(String libelle, {String? niveau}) {
  final n = lireClasse(libelle)?.niveau ?? (niveau == null ? null : lireClasse(niveau)?.niveau ?? niveau.toUpperCase());
  return niveauxAptitude.contains(n);
}
