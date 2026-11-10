/// Analyse et contrôle des lignes d'une liste nominative avant importation.
///
/// Aucune ligne n'est enregistrée ici : le résultat est présenté à
/// l'utilisateur, qui corrige, supprime ou complète, puis valide.
library;

import '../commun/commun.dart';
import '../modeles/enums.dart';
import '../regles/age.dart';
import '../regles/identite.dart';
import 'champs.dart';
import 'tableau.dart';

enum GraviteAnomalie { bloquante, avertissement }

class AnomalieImport {
  final ChampListe? champ;
  final GraviteAnomalie gravite;
  final String message;
  const AnomalieImport(this.champ, this.gravite, this.message);

  @override
  String toString() => '${gravite == GraviteAnomalie.bloquante ? 'Erreur' : 'À vérifier'} : $message';
}

enum ActionImport {
  /// Nouvel élève (dossier créé) inscrit dans la classe.
  creer('Nouvel élève'),

  /// Élève déjà connu : son dossier est réutilisé et inscrit dans la classe.
  rattacher('Rattacher au dossier existant'),

  /// Ligne non importée.
  ignorer('Ne pas importer');

  final String libelle;
  const ActionImport(this.libelle);
}

/// Une ligne de la liste, modifiable dans le tableau de contrôle.
class LigneImport {
  /// Numéro de la ligne dans le fichier (à partir de 1).
  final int numeroSource;
  final Map<ChampListe, String> brut;

  String? matricule;
  String nom;
  String prenoms;
  DateTime? dateNaissance;
  Sexe? sexe;
  String? telephone;
  int? ageDeclare;

  /// Remarques de lecture (correction automatique, séparation nom / prénoms).
  final List<String> notes;

  List<AnomalieImport> anomalies = const [];
  ActionImport action = ActionImport.creer;
  String? eleveExistantId;

  /// Vrai si l'utilisateur a choisi l'action lui-même (elle n'est plus recalculée).
  bool actionImposee = false;

  LigneImport({
    required this.numeroSource,
    required this.brut,
    this.matricule,
    required this.nom,
    required this.prenoms,
    this.dateNaissance,
    this.sexe,
    this.telephone,
    this.ageDeclare,
    List<String>? notes,
  }) : notes = notes ?? [];

  bool get bloquee => anomalies.any((a) => a.gravite == GraviteAnomalie.bloquante);
  bool get aVerifier => anomalies.isNotEmpty || notes.isNotEmpty;

  IdentiteEleve get identite =>
      IdentiteEleve(matricule: matricule, nom: nom, prenoms: prenoms, dateNaissance: dateNaissance);

  void imposerAction(ActionImport a, {String? eleveId}) {
    action = a;
    actionImposee = true;
    if (a == ActionImport.rattacher) eleveExistantId = eleveId ?? eleveExistantId;
  }
}

// ------------------------------------------------------------- corrections OCR

const Map<String, String> _confusionsChiffres = {
  'O': '0', 'o': '0', 'Q': '0', 'D': '0',
  'I': '1', 'l': '1', '|': '1', 'i': '1', '!': '1',
  'Z': '2', 'z': '2',
  'S': '5', 's': '5',
  'G': '6', 'b': '6',
  'T': '7',
  'B': '8',
  'g': '9', 'q': '9',
};

/// Remplace les lettres souvent confondues avec des chiffres par l'OCR, dans
/// une chaîne qui ne doit contenir que des chiffres et des séparateurs (date).
String corrigerChiffresOcr(String s) => s.split('').map((c) => _confusionsChiffres[c] ?? c).join();

class MatriculeLu {
  final String? valeur;
  final bool corrige;
  const MatriculeLu(this.valeur, {this.corrige = false});
}

/// Matricule normalisé. Si [format] est donné (expression régulière, par
/// exemple `^\d{8}[A-Z]$`), une valeur non conforme est corrigée lorsque le
/// remplacement des confusions lettre/chiffre sur la partie numérique la rend
/// conforme. Sans format, seules les lettres isolées entre deux chiffres sont
/// corrigées (« 12O45 » → « 12045 »).
MatriculeLu lireMatricule(String? brut, {RegExp? format}) {
  final m = normaliserMatricule(brut);
  if (m == null) return const MatriculeLu(null);
  if (format != null) {
    if (format.hasMatch(m)) return MatriculeLu(m);
    // Essai : toutes les positions sauf la dernière sont numériques.
    for (var finLettres = 0; finLettres <= 2 && finLettres < m.length; finLettres++) {
      final tete = m.substring(0, m.length - finLettres);
      final queue = m.substring(m.length - finLettres);
      final essai = corrigerChiffresOcr(tete) + queue;
      if (format.hasMatch(essai)) return MatriculeLu(essai, corrige: essai != m);
    }
    return MatriculeLu(m);
  }
  final c = m.split('');
  var corrige = false;
  bool chiffre(int i) => i >= 0 && i < c.length && RegExp(r'\d').hasMatch(c[i]);
  for (var i = 1; i < c.length - 1; i++) {
    final rempl = _confusionsChiffres[c[i]];
    if (rempl != null && chiffre(i - 1) && chiffre(i + 1)) {
      c[i] = rempl;
      corrige = true;
    }
  }
  return MatriculeLu(c.join(), corrige: corrige);
}

/// Date de naissance : formats usuels, confusions OCR, et numéro de série
/// Excel (nombre de jours depuis le 30/12/1899) lorsqu'une cellule de date a
/// été lue comme un nombre.
DateTime? lireDateListe(String? brut) {
  if (brut == null || brut.trim().isEmpty) return null;
  final t = brut.trim();
  final serie = double.tryParse(t.replaceAll(',', '.'));
  if (serie != null && serie > 1000 && serie < 80000) {
    return DateTime.utc(1899, 12, 30).add(Duration(days: serie.floor()));
  }
  final direct = lireDateNaissance(t.split(RegExp(r'\s')).first);
  if (direct != null) return direct;
  // Date suivie du lieu (« 12/04/2015 à Bouaké ») ou abîmée par l'OCR.
  final m = RegExp(r'[0-9OoIl|SB]{1,2}\s*[/\-.]\s*[0-9OoIl|SB]{1,2}\s*[/\-.]\s*[0-9OoIl|SB]{4}').firstMatch(t);
  if (m == null) return null;
  return lireDateNaissance(corrigerChiffresOcr(m.group(0)!.replaceAll(' ', '')));
}

String? lireTelephone(String? brut) {
  if (brut == null) return null;
  final chiffres = corrigerChiffresOcr(brut).replaceAll(RegExp(r'[^\d+]'), '');
  return chiffres.length >= 8 ? chiffres : null;
}

/// Sépare « NOM PRÉNOMS » : les premiers mots entièrement en majuscules
/// forment le nom si les suivants ne le sont pas ; sinon le premier mot est
/// le nom. Le résultat est signalé pour vérification.
(String, String) separerNomPrenoms(String texte) {
  final mots = texte.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
  if (mots.isEmpty) return ('', '');
  if (mots.length == 1) return (mots.first, '');
  bool majuscules(String m) => m == m.toUpperCase() && m != m.toLowerCase();
  final nbMaj = mots.takeWhile(majuscules).length;
  if (nbMaj > 0 && nbMaj < mots.length) {
    return (mots.take(nbMaj).join(' '), mots.skip(nbMaj).join(' '));
  }
  return (mots.first, mots.skip(1).join(' '));
}

// ------------------------------------------------------------------ analyse

/// Transforme le tableau brut en lignes d'élèves.
///
/// - Plusieurs colonnes affectées au même champ sont réunies.
/// - Les en-têtes répétés et les lignes sans nom sont écartés.
/// - Une ligne qui ne contient qu'un nom ou des prénoms (texte renvoyé à la
///   ligne dans la cellule) est rattachée à la ligne précédente.
List<LigneImport> analyserTableau(TableauBrut t, {RegExp? formatMatricule}) {
  final debut = t.ligneEntete == null ? 0 : t.ligneEntete! + 1;
  final lignes = <LigneImport>[];
  for (var i = debut; i < t.lignes.length; i++) {
    final cellules = t.lignes[i];
    if (estEnteteRepete(cellules)) continue;
    final brut = <ChampListe, String>{};
    t.correspondance.forEach((col, champ) {
      if (champ == ChampListe.ignorer || col >= cellules.length) return;
      final v = cellules[col].trim();
      if (v.isEmpty) return;
      brut[champ] = brut[champ] == null ? v : '${brut[champ]} $v';
    });
    final aNom = brut.keys.any((c) => c.estNom);
    if (!aNom) continue;

    // Suite de la ligne précédente (nom ou prénoms sur deux lignes).
    final seulementNoms = brut.keys.every((c) => c.estNom);
    if (seulementNoms && lignes.isNotEmpty && !_semblePersonne(brut)) {
      final prec = lignes.last;
      brut.forEach((champ, v) {
        prec.brut[champ] = '${prec.brut[champ] ?? ''} $v'.trim();
      });
      _remplirIdentite(prec, formatMatricule);
      prec.notes.add('Texte de la ligne ${i + 1} rattaché à cette ligne.');
      continue;
    }

    final l = LigneImport(numeroSource: i + 1, brut: brut, nom: '', prenoms: '');
    _remplirIdentite(l, formatMatricule);
    lignes.add(l);
  }
  return lignes;
}

/// Une ligne qui n'a que des noms est-elle un élève à part entière (liste
/// sans matricule ni date) ? Oui si la liste entière est de ce type : on le
/// reconnaît à la présence simultanée du nom et des prénoms.
bool _semblePersonne(Map<ChampListe, String> brut) =>
    brut.containsKey(ChampListe.nomPrenoms) && brut[ChampListe.nomPrenoms]!.trim().contains(' ') ||
    (brut.containsKey(ChampListe.nom) && brut.containsKey(ChampListe.prenoms));

void _remplirIdentite(LigneImport l, RegExp? formatMatricule) {
  final b = l.brut;
  l.notes.removeWhere((n) => n.startsWith('Matricule corrigé') || n.startsWith('Nom et prénoms séparés'));
  final mat = lireMatricule(b[ChampListe.matricule], format: formatMatricule);
  l.matricule = mat.valeur;
  if (mat.corrige) l.notes.add('Matricule corrigé automatiquement (lu « ${b[ChampListe.matricule]} »).');

  if (b.containsKey(ChampListe.nom) && b.containsKey(ChampListe.prenoms)) {
    l.nom = b[ChampListe.nom]!.trim();
    l.prenoms = b[ChampListe.prenoms]!.trim();
  } else {
    final texte = [b[ChampListe.nomPrenoms], b[ChampListe.nom], b[ChampListe.prenoms]].whereType<String>().join(' ');
    final (nom, prenoms) = separerNomPrenoms(texte);
    l.nom = nom;
    l.prenoms = prenoms;
    if (prenoms.isNotEmpty) l.notes.add('Nom et prénoms séparés automatiquement.');
  }
  l.nom = l.nom.toUpperCase();
  l.prenoms = _majusculeInitiale(l.prenoms);
  l.dateNaissance = lireDateListe(b[ChampListe.dateNaissance]);
  l.sexe = lireSexe(b[ChampListe.sexe]);
  l.telephone = lireTelephone(b[ChampListe.telephone]);
  final age = b[ChampListe.age] == null ? null : RegExp(r'\d+').firstMatch(corrigerChiffresOcr(b[ChampListe.age]!));
  l.ageDeclare = age == null ? null : int.parse(age.group(0)!);
}

String _majusculeInitiale(String s) => s
    .split(' ')
    .where((m) => m.isNotEmpty)
    .map((m) => m.split('-').map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1).toLowerCase()).join('-'))
    .join(' ');

/// (Re)calcule les anomalies et les actions par défaut, après lecture ou
/// après une correction de l'utilisateur.
///
/// [existants] : élèves déjà présents sur le téléphone (avec leur `id`).
/// [dateReference] : date de la visite ou du jour, pour la vraisemblance de l'âge.
void controlerLignes(
  List<LigneImport> lignes, {
  List<IdentiteEleve> existants = const [],
  required DateTime dateReference,
  RegExp? formatMatricule,
  int ageMin = 2,
  int ageMax = 40,
}) {
  final candidats = [for (final l in lignes) l.identite];
  final doublons = detecterDoublons(candidats, existants);
  final parCandidat = <int, Doublon>{};
  for (final d in doublons) {
    final i = candidats.indexWhere((c) => identical(c, d.candidat));
    if (i >= 0) parCandidat[i] = d;
  }

  for (var i = 0; i < lignes.length; i++) {
    final l = lignes[i];
    final a = <AnomalieImport>[];
    if (l.nom.trim().isEmpty) a.add(const AnomalieImport(ChampListe.nom, GraviteAnomalie.bloquante, 'Nom manquant.'));
    if (l.prenoms.trim().isEmpty) {
      a.add(const AnomalieImport(ChampListe.prenoms, GraviteAnomalie.bloquante, 'Prénoms manquants.'));
    }
    if (l.sexe == null) {
      a.add(AnomalieImport(ChampListe.sexe, GraviteAnomalie.bloquante,
          l.brut[ChampListe.sexe] == null ? 'Sexe manquant.' : 'Sexe illisible (« ${l.brut[ChampListe.sexe]} »).'));
    }
    if (l.dateNaissance == null) {
      a.add(AnomalieImport(ChampListe.dateNaissance, GraviteAnomalie.avertissement,
          l.brut[ChampListe.dateNaissance] == null
              ? 'Date de naissance manquante.'
              : 'Date de naissance illisible (« ${l.brut[ChampListe.dateNaissance]} »).'));
    } else if (l.dateNaissance!.isAfter(dateReference)) {
      a.add(const AnomalieImport(ChampListe.dateNaissance, GraviteAnomalie.bloquante, 'Date de naissance dans le futur.'));
    } else {
      final age = calculerAge(l.dateNaissance!, dateReference).annees;
      if (age < ageMin || age > ageMax) {
        a.add(AnomalieImport(ChampListe.dateNaissance, GraviteAnomalie.bloquante,
            'Âge invraisemblable ($age ans) : vérifier la date de naissance.'));
      } else if (l.ageDeclare != null && (l.ageDeclare! - age).abs() > 1) {
        a.add(AnomalieImport(ChampListe.age, GraviteAnomalie.avertissement,
            'Âge indiqué (${l.ageDeclare} ans) différent de l\'âge calculé ($age ans).'));
      }
    }
    if (l.matricule == null) {
      a.add(const AnomalieImport(ChampListe.matricule, GraviteAnomalie.avertissement, 'Matricule manquant.'));
    } else if (formatMatricule != null && !formatMatricule.hasMatch(l.matricule!)) {
      a.add(AnomalieImport(
          ChampListe.matricule, GraviteAnomalie.avertissement, 'Matricule au format inhabituel (${l.matricule}).'));
    }

    final d = parCandidat[i];
    if (d != null) {
      final dansFichier = d.existant.id == null;
      final numero = dansFichier ? lignes[candidats.indexWhere((c) => identical(c, d.existant))].numeroSource : null;
      final motif = d.motif == MotifDoublon.memeMatricule ? 'même matricule' : 'mêmes nom, prénoms et date de naissance';
      a.add(AnomalieImport(
        d.motif == MotifDoublon.memeMatricule ? ChampListe.matricule : ChampListe.nom,
        GraviteAnomalie.avertissement,
        dansFichier ? 'Doublon de la ligne $numero ($motif).' : 'Élève déjà enregistré ($motif).',
      ));
      if (!l.actionImposee) {
        if (dansFichier) {
          l.action = ActionImport.ignorer;
        } else {
          l.action = ActionImport.rattacher;
          l.eleveExistantId = d.existant.id;
        }
      }
    } else if (!l.actionImposee) {
      l.action = ActionImport.creer;
      l.eleveExistantId = null;
    }
    if (l.action == ActionImport.rattacher && l.eleveExistantId == null) {
      a.add(const AnomalieImport(null, GraviteAnomalie.bloquante, 'Aucun dossier existant choisi pour le rattachement.'));
    }
    l.anomalies = a;
  }
}

/// Bilan avant validation.
class BilanImport {
  final int aCreer;
  final int aRattacher;
  final int ignorees;
  final int bloquees;
  final int aVerifier;
  const BilanImport(this.aCreer, this.aRattacher, this.ignorees, this.bloquees, this.aVerifier);

  bool get validable => bloquees == 0 && aCreer + aRattacher > 0;
}

BilanImport bilan(List<LigneImport> lignes) {
  var creer = 0, rattacher = 0, ignorees = 0, bloquees = 0, verifier = 0;
  for (final l in lignes) {
    if (l.action == ActionImport.ignorer) {
      ignorees++;
      continue;
    }
    if (l.bloquee) bloquees++;
    if (l.aVerifier) verifier++;
    if (l.action == ActionImport.creer) creer++;
    if (l.action == ActionImport.rattacher) rattacher++;
  }
  return BilanImport(creer, rattacher, ignorees, bloquees, verifier);
}

/// Identité canonique d'une ligne validée, prête à être enregistrée.
Map<String, Object?> donneesEleve(LigneImport l) => {
      'matricule': l.matricule,
      'nom': l.nom.trim(),
      'prenoms': l.prenoms.trim(),
      'date_naissance': l.dateNaissance == null ? null : formaterDate(l.dateNaissance!),
      'sexe': l.sexe!.code,
      'telephone_contact': l.telephone,
    };
