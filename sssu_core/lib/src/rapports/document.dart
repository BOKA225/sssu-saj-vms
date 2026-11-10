/// Modèle neutre d'un rapport (en-tête institutionnel, blocs de contenu),
/// rendu ensuite en PDF ([rendrePdf]) ou en Excel ([rendreExcel]).
library;

/// En-tête institutionnel, lu dans les paramètres (section 13) : lignes
/// `entete_ligne_1` à `entete_ligne_6`, `nom_medecin_chef`, logo
/// `logo_png` (image PNG en base64).
class EnteteRapport {
  final List<String> lignes;
  final String? nomMedecinChef;
  final List<int>? logoPng;
  const EnteteRapport({required this.lignes, this.nomMedecinChef, this.logoPng});

  static const lignesParDefaut = [
    'MINISTÈRE EN CHARGE DE LA SANTÉ',
    'DIRECTION RÉGIONALE DE LA SANTÉ DU N\'ZI',
    'DISTRICT SANITAIRE DE KOUASSI-KOUASSIKRO',
    'SERVICE DE SANTÉ SCOLAIRE ET UNIVERSITAIRE – SANTÉ ADOLESCENTS ET JEUNES (SSSU-SAJ)',
  ];

  factory EnteteRapport.depuisParametres(Map<String, String?> p, {List<int>? logoPng}) {
    final lignes = [
      for (var i = 1; i <= 6; i++)
        if ((p['entete_ligne_$i'] ?? '').trim().isNotEmpty) p['entete_ligne_$i']!.trim()
    ];
    final medecin = p['nom_medecin_chef']?.trim();
    return EnteteRapport(
      lignes: lignes.isEmpty ? lignesParDefaut : lignes,
      nomMedecinChef: medecin == null || medecin.isEmpty ? null : medecin,
      logoPng: logoPng,
    );
  }
}

sealed class BlocRapport {
  const BlocRapport();
}

/// Intertitre de section.
class BlocTitre extends BlocRapport {
  final String texte;
  const BlocTitre(this.texte);
}

class BlocParagraphe extends BlocRapport {
  final String texte;
  final bool italique;
  const BlocParagraphe(this.texte, {this.italique = false});
}

/// Couples libellé / valeur (identité, indicateurs clés).
class BlocChamps extends BlocRapport {
  final List<(String, String)> champs;
  const BlocChamps(this.champs);
}

/// Tableau. Les cellules sont des `String`, `int`, `double` ou `null`.
/// [totaux] : dernière ligne mise en évidence.
class BlocTableau extends BlocRapport {
  final String? titre;
  final List<String> entetes;
  final List<List<Object?>> lignes;
  final List<Object?>? totaux;

  /// Largeurs relatives des colonnes (facultatives).
  final List<double>? largeurs;
  const BlocTableau({this.titre, required this.entetes, required this.lignes, this.totaux, this.largeurs});
}

class BlocImage extends BlocRapport {
  final List<int> png;
  final String? legende;

  /// Largeur maximale en points (1 pt = 1/72 pouce).
  final double largeurMax;
  const BlocImage(this.png, {this.legende, this.largeurMax = 220});
}

/// Espace de signature et de cachet du service (Médecin-Chef), ou signature
/// de l'inspecteur ([image] tracée à l'écran).
class BlocSignature extends BlocRapport {
  final String fonction;
  final String? nom;
  final List<int>? image;
  final bool cachet;
  const BlocSignature({required this.fonction, this.nom, this.image, this.cachet = true});
}

class BlocSautDePage extends BlocRapport {
  const BlocSautDePage();
}

class DocumentRapport {
  final String titre;
  final String? sousTitre;
  final EnteteRapport entete;
  final List<BlocRapport> blocs;
  final DateTime genereLe;

  /// Mise en page à l'italienne (tableaux larges).
  final bool paysage;

  /// Mention de confidentialité en pied de page (documents nominatifs).
  final bool confidentiel;

  const DocumentRapport({
    required this.titre,
    this.sousTitre,
    required this.entete,
    required this.blocs,
    required this.genereLe,
    this.paysage = false,
    this.confidentiel = false,
  });
}

/// Texte d'une cellule : nombres à la française (virgule décimale), tiret si vide.
String texteCellule(Object? v) {
  if (v == null) return '—';
  if (v is double) {
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return s.replaceAll('.', ',');
  }
  return v.toString();
}

/// Pourcentage affiché (`45,5 %`), tiret si non calculable.
String pourcentage(double? t) => t == null ? '—' : '${texteCellule(t)} %';
