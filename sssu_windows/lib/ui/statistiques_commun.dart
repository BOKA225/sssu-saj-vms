/// Éléments communs du tableau de bord, des statistiques et des rapports :
/// chargement des données de l'année, filtres (année scolaire,
/// établissement, classe, sexe, période), mise à jour automatique après
/// chaque synchronisation, graphiques.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:sssu_core/sssu_core.dart';

import '../donnees/requetes_poste.dart';
import '../services.dart';
import 'commun.dart';

class ControleurStatistiques extends ChangeNotifier {
  final ServicesPoste services;

  /// Charger les noms et diagnostics (listes nominatives).
  final bool identite;
  List<Annee> annees = const [];
  Annee? annee;
  JeuStatistiques? jeu;
  String? etablissementId;
  String? classeId;
  Sexe? sexe;
  DateTime? du;
  DateTime? au;

  /// Visite systématique ou d'aptitude : statistiques séparées.
  TypeVisite typeVisite = TypeVisite.systematique;
  Object? erreur;
  bool chargement = false;
  DateTime? misAJourLe;
  int _repere = -1;
  Timer? _minuterie;
  bool _ferme = false;

  ControleurStatistiques(this.services, {this.identite = false});

  FiltreStatistiques get filtre => FiltreStatistiques(
      etablissementId: etablissementId, classeId: classeId, sexe: sexe, du: du, au: au, typeVisite: typeVisite);

  Statistiques? get statistiques => jeu == null ? null : calculerStatistiques(jeu!, filtre);

  /// Charge les années, l'année active, puis surveille les nouvelles données
  /// (toutes les 20 secondes) pour se mettre à jour après une synchronisation.
  Future<void> demarrer() async {
    annees = await services.requetes.annees();
    annee = annees.where((a) => a.active).firstOrNull ?? annees.firstOrNull;
    await recharger();
    _minuterie = Timer.periodic(const Duration(seconds: 20), (_) => _verifier());
  }

  Future<void> _verifier() async {
    if (chargement || _ferme) return;
    try {
      final r = await services.statistiques.repere();
      if (r != _repere) await recharger();
    } catch (_) {
      // Base momentanément indisponible : nouvel essai au prochain passage.
    }
  }

  Future<void> recharger() async {
    final a = annee;
    if (a == null || _ferme) {
      notifyListeners();
      return;
    }
    chargement = true;
    notifyListeners();
    try {
      final repere = await services.statistiques.repere();
      jeu = await services.statistiques.charger(a, identite: identite);
      _repere = repere;
      erreur = null;
      misAJourLe = DateTime.now();
      if (etablissementId != null && !jeu!.etablissements.containsKey(etablissementId)) etablissementId = null;
      if (classeId != null && !jeu!.classes.containsKey(classeId)) classeId = null;
    } catch (e) {
      erreur = e;
    } finally {
      chargement = false;
      if (!_ferme) notifyListeners();
    }
  }

  void changerAnnee(Annee a) {
    annee = a;
    etablissementId = null;
    classeId = null;
    du = null;
    au = null;
    recharger();
  }

  void changer(
      {Object? etablissement = _rien,
      Object? classe = _rien,
      Object? sexe_ = _rien,
      Object? du_ = _rien,
      Object? au_ = _rien,
      TypeVisite? type}) {
    if (type != null) {
      typeVisite = type;
      // Visite d'aptitude : seulement les classes de 3ème et de terminale.
      if (type == TypeVisite.aptitude && classeId != null && !(jeu?.classes[classeId]?.aptitude ?? false)) classeId = null;
    }
    if (etablissement != _rien) {
      etablissementId = etablissement as String?;
      if (classeId != null && jeu?.classes[classeId]?.etablissementId != etablissementId) classeId = null;
    }
    if (classe != _rien) classeId = classe as String?;
    if (sexe_ != _rien) sexe = sexe_ as Sexe?;
    if (du_ != _rien) du = du_ as DateTime?;
    if (au_ != _rien) au = au_ as DateTime?;
    notifyListeners();
  }

  @override
  void dispose() {
    _ferme = true;
    _minuterie?.cancel();
    super.dispose();
  }
}

const Object _rien = Object();

/// Barre de filtres. [classe], [sexe], [periode] et [type] (de visite)
/// peuvent être masqués.
class BarreFiltres extends StatelessWidget {
  final ControleurStatistiques c;
  final bool classe;
  final bool sexe;
  final bool periode;
  final bool type;
  const BarreFiltres(this.c, {super.key, this.classe = true, this.sexe = true, this.periode = true, this.type = true});

  Future<DateTime?> _date(BuildContext context, DateTime? initiale) async {
    final a = c.annee!;
    final debut = lireDate(a.debut);
    final fin = lireDate(a.fin);
    final d = await showDatePicker(
      context: context,
      initialDate: initiale ?? (DateTime.now().isAfter(fin) ? fin : (DateTime.now().isBefore(debut) ? debut : DateTime.now())),
      firstDate: debut,
      lastDate: fin,
    );
    return d == null ? null : DateTime.utc(d.year, d.month, d.day);
  }

  @override
  Widget build(BuildContext context) {
    final jeu = c.jeu;
    final classes = jeu == null
        ? const <ClasseStat>[]
        : (jeu.classes.values
            .where((x) =>
                (c.etablissementId == null || x.etablissementId == c.etablissementId) &&
                (c.typeVisite == TypeVisite.systematique || x.aptitude))
            .toList()
          ..sort((a, b) {
            final e = (jeu.etablissements[a.etablissementId] ?? '').compareTo(jeu.etablissements[b.etablissementId] ?? '');
            return e != 0 ? e : (a.niveau ?? a.libelle).compareTo(b.niveau ?? b.libelle);
          }));
    return Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (type)
        SegmentedButton<TypeVisite>(
          segments: [
            for (final t in TypeVisite.values)
              ButtonSegment(
                  value: t,
                  label: Text(t == TypeVisite.aptitude ? 'Visite d\'aptitude (3ème, Tle)' : 'Visite systématique'),
                  icon: Icon(t == TypeVisite.aptitude ? Icons.directions_run : Icons.medical_services)),
          ],
          selected: {c.typeVisite},
          onSelectionChanged: (v) => c.changer(type: v.first),
        ),
      DropdownButton<Annee>(
        value: c.annee,
        hint: const Text('Année scolaire'),
        items: [for (final a in c.annees) DropdownMenuItem(value: a, child: Text('Année ${a.libelle}'))],
        onChanged: (a) {
          if (a != null) c.changerAnnee(a);
        },
      ),
      if (jeu != null)
        DropdownButton<String?>(
          value: c.etablissementId,
          items: [
            const DropdownMenuItem(value: null, child: Text('Tous les établissements')),
            for (final e in jeu.etablissements.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => c.changer(etablissement: v),
        ),
      if (jeu != null && classe)
        DropdownButton<String?>(
          value: c.classeId,
          items: [
            const DropdownMenuItem(value: null, child: Text('Toutes les classes')),
            for (final x in classes)
              DropdownMenuItem(
                  value: x.id,
                  child: Text(c.etablissementId == null ? '${jeu.etablissements[x.etablissementId] ?? ''} – ${x.libelle}' : x.libelle)),
          ],
          onChanged: (v) => c.changer(classe: v),
        ),
      if (sexe)
        DropdownButton<Sexe?>(
          value: c.sexe,
          items: const [
            DropdownMenuItem(value: null, child: Text('Garçons et filles')),
            DropdownMenuItem(value: Sexe.masculin, child: Text('Garçons')),
            DropdownMenuItem(value: Sexe.feminin, child: Text('Filles')),
          ],
          onChanged: (v) => c.changer(sexe_: v),
        ),
      if (periode && c.annee != null) ...[
        OutlinedButton.icon(
          icon: const Icon(Icons.event, size: 18),
          label: Text(c.du == null ? 'Depuis le début de l\'année' : 'Du ${dateFr(c.du)}'),
          onPressed: () async {
            final d = await _date(context, c.du);
            if (d != null) c.changer(du_: d);
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.event, size: 18),
          label: Text(c.au == null ? 'Jusqu\'à la fin de l\'année' : 'Au ${dateFr(c.au)}'),
          onPressed: () async {
            final d = await _date(context, c.au);
            if (d != null) c.changer(au_: d);
          },
        ),
        if (c.du != null || c.au != null)
          IconButton(
              tooltip: 'Toute l\'année', onPressed: () => c.changer(du_: null, au_: null), icon: const Icon(Icons.clear)),
      ],
      if (c.chargement) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      if (c.misAJourLe != null && !c.chargement)
        Text('Mis à jour à ${c.misAJourLe!.hour.toString().padLeft(2, '0')}:${c.misAJourLe!.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
    ]);
  }
}

// ------------------------------------------------------------------ cartes

class CarteIndicateur extends StatelessWidget {
  final String valeur;
  final String libelle;
  final String? detail;
  final IconData? icone;
  final Color? couleur;
  const CarteIndicateur(this.valeur, this.libelle, {super.key, this.detail, this.icone, this.couleur});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 210,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              if (icone != null) ...[Icon(icone, color: couleur ?? Theme.of(context).colorScheme.primary), const SizedBox(width: 12)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(valeur, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: couleur)),
                  Text(libelle),
                  if (detail != null) Text(detail!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class Panneau extends StatelessWidget {
  final String titre;
  final Widget enfant;
  final double? largeur;
  final double? hauteur;
  const Panneau(this.titre, this.enfant, {super.key, this.largeur, this.hauteur});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: largeur,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(titre, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (hauteur == null) enfant else SizedBox(height: hauteur, child: enfant),
            ]),
          ),
        ),
      );
}

/// Indicateurs de la section 4 du prompt.
List<Widget> cartesGenerales(Statistiques s) {
  final g = s.generale;
  return [
    CarteIndicateur('${s.nbEtablissements}', 'Établissements', icone: Icons.school),
    CarteIndicateur('${s.nbClasses}', 'Classes', icone: Icons.class_),
    CarteIndicateur('${g.effectif}', s.typeVisite == TypeVisite.aptitude ? 'Élèves de 3ème et Tle' : 'Élèves',
        detail: '${g.garcons} garçons · ${g.filles} filles', icone: Icons.groups),
    CarteIndicateur('${g.examines}', 'Élèves examinés',
        detail: '${g.garconsExamines} G · ${g.fillesExamines} F', icone: Icons.medical_services, couleur: Colors.green.shade700),
    CarteIndicateur('${g.nonExamines}', 'Non examinés', icone: Icons.pending_actions, couleur: Colors.orange.shade800),
    CarteIndicateur('${s.nbVisites}', s.typeVisite == TypeVisite.aptitude ? 'Visites d\'aptitude' : 'Visites systématiques',
        icone: Icons.assignment),
    if (s.typeVisite == TypeVisite.aptitude)
      CarteIndicateur('${s.aptitudes[DecisionAptitude.apte] ?? 0}', 'Aptes',
          detail: '${s.aptitudes[DecisionAptitude.aptePartiel] ?? 0} aptitude(s) partielle(s) · '
              '${(s.aptitudes[DecisionAptitude.inapteTemporaire] ?? 0) + (s.aptitudes[DecisionAptitude.inapteDefinitif] ?? 0)} inapte(s)',
          icone: Icons.directions_run,
          couleur: Colors.green.shade700),
    CarteIndicateur('${s.inspections.inspectes}/${s.inspections.etablissements}', 'Établissements inspectés',
        detail: 'Conformité moyenne ${pourcentage(s.inspections.tauxMoyen)}', icone: Icons.fact_check),
    CarteIndicateur(pourcentage(g.tauxCouverture), 'Taux de couverture',
        icone: Icons.donut_large, couleur: Colors.blue.shade800),
  ];
}

// --------------------------------------------------------------- graphiques

const couleursSerie = [
  Color(0xFF1F77B4), Color(0xFFFF7F0E), Color(0xFF2CA02C), Color(0xFFD62728), Color(0xFF9467BD),
  Color(0xFF8C564B), Color(0xFFE377C2), Color(0xFF7F7F7F), Color(0xFFBCBD22), Color(0xFF17BECF),
];
const couleurGarcons = Color(0xFF1F77B4);
const couleurFilles = Color(0xFFE377C2);

String _abrege(String s, int n) => s.length <= n ? s : '${s.substring(0, n - 1)}…';

/// Histogramme des taux de couverture (0 à 100 %).
Widget histogrammeCouverture(List<Couverture> lignes) {
  if (lignes.isEmpty) return const Center(child: Text('Aucune donnée.'));
  return BarChart(BarChartData(
    maxY: 100,
    minY: 0,
    gridData: const FlGridData(drawVerticalLine: false, horizontalInterval: 25),
    borderData: FlBorderData(show: false),
    barTouchData: BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
            '${lignes[g.x].libelle}\n${lignes[g.x].examines}/${lignes[g.x].effectif} · ${pourcentage(lignes[g.x].tauxCouverture)}',
            const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    ),
    titlesData: FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
          sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: 25,
              getTitlesWidget: (v, m) => Text('${v.round()} %', style: const TextStyle(fontSize: 11)))),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 42,
          getTitlesWidget: (v, m) {
            final i = v.round();
            if (i < 0 || i >= lignes.length) return const SizedBox.shrink();
            return SideTitleWidget(
              axisSide: m.axisSide,
              child: Text(_abrege(lignes[i].libelle, lignes.length > 8 ? 8 : 16),
                  style: const TextStyle(fontSize: 10), textAlign: TextAlign.center),
            );
          },
        ),
      ),
    ),
    barGroups: [
      for (var i = 0; i < lignes.length; i++)
        BarChartGroupData(x: i, barRods: [
          BarChartRodData(
            toY: lignes[i].tauxCouverture ?? 0,
            width: math.max(6, math.min(28, 400 / lignes.length)),
            color: couleursSerie[0],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ]),
    ],
  ));
}

/// Diagramme circulaire avec légende.
Widget camembert(List<(String, int, Color)> parts) {
  final total = parts.fold<int>(0, (s, p) => s + p.$2);
  if (total == 0) return const Center(child: Text('Aucune donnée.'));
  return Row(children: [
    Expanded(
      child: PieChart(PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 28,
        sections: [
          for (final (_, n, c) in parts)
            if (n > 0)
              PieChartSectionData(
                value: n.toDouble(),
                color: c,
                radius: 56,
                title: pourcentage(taux(n, total)),
                titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
              ),
        ],
      )),
    ),
    const SizedBox(width: 12),
    Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (l, n, c) in parts)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, color: c),
            const SizedBox(width: 6),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: Text('$l : $n', style: const TextStyle(fontSize: 12))),
          ]),
        ),
    ]),
  ]);
}

/// Courbe d'évolution : visites par mois et couverture cumulée.
Widget courbeEvolution(List<PointEvolution> points) {
  if (points.length < 2) return const Center(child: Text('Pas encore assez de mois pour une courbe.'));
  final maxVisites = points.map((p) => p.visites).fold<int>(1, math.max).toDouble();
  const mois = ['jan', 'fév', 'mars', 'avr', 'mai', 'juin', 'juil', 'août', 'sept', 'oct', 'nov', 'déc'];
  return LineChart(LineChartData(
    minY: 0,
    maxY: 100,
    gridData: const FlGridData(drawVerticalLine: false, horizontalInterval: 25),
    borderData: FlBorderData(show: false),
    lineTouchData: LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        getTooltipItems: (spots) => [
          for (final s in spots)
            LineTooltipItem(
              s.barIndex == 0
                  ? 'Couverture ${pourcentage(points[s.x.round()].couvertureCumulee)}'
                  : '${points[s.x.round()].visites} visite(s)',
              const TextStyle(color: Colors.white, fontSize: 12),
            ),
        ],
      ),
    ),
    titlesData: FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: AxisTitles(
          sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: 25,
              getTitlesWidget: (v, m) =>
                  Text('${(v / 100 * maxVisites).round()}', style: const TextStyle(fontSize: 10, color: Colors.orange)))),
      leftTitles: AxisTitles(
          sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: 25,
              getTitlesWidget: (v, m) => Text('${v.round()} %', style: const TextStyle(fontSize: 11)))),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: 1,
          reservedSize: 28,
          getTitlesWidget: (v, m) {
            final i = v.round();
            if (i < 0 || i >= points.length || v != i.toDouble()) return const SizedBox.shrink();
            return SideTitleWidget(
                axisSide: m.axisSide,
                child: Text(mois[int.parse(points[i].mois.substring(5, 7)) - 1], style: const TextStyle(fontSize: 11)));
          },
        ),
      ),
    ),
    lineBarsData: [
      LineChartBarData(
        spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].couvertureCumulee ?? 0)],
        color: couleursSerie[0],
        barWidth: 3,
        dotData: const FlDotData(show: true),
      ),
      LineChartBarData(
        spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].visites / maxVisites * 100)],
        color: Colors.orange,
        barWidth: 2,
        dashArray: [6, 4],
        dotData: const FlDotData(show: false),
      ),
    ],
  ));
}

/// Barres horizontales (pathologies, insuffisances) : libellé, valeur, texte.
Widget barresHorizontales(List<(String, double, String)> lignes, {Color? couleur, double? maximum}) {
  if (lignes.isEmpty) return const Text('Aucune donnée.');
  final max = maximum ?? lignes.map((l) => l.$2).fold<double>(0, math.max);
  return Column(children: [
    for (final (l, v, t) in lignes)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 230, child: Text(l, overflow: TextOverflow.ellipsis)),
          Expanded(
            child: LinearProgressIndicator(
              value: max == 0 ? 0 : v / max,
              minHeight: 14,
              color: couleur ?? couleursSerie[3],
              backgroundColor: Colors.black12,
            ),
          ),
          SizedBox(width: 150, child: Text('  $t', style: const TextStyle(fontSize: 12))),
        ]),
      ),
  ]);
}

/// Tableau simple (en-têtes + lignes), avec défilement horizontal.
Widget tableau(List<String> entetes, List<List<Object?>> lignes, {List<Object?>? totaux}) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 30,
        dataRowMaxHeight: 36,
        columns: [
          for (var i = 0; i < entetes.length; i++)
            DataColumn(label: Text(entetes[i], style: const TextStyle(fontWeight: FontWeight.bold)), numeric: i > 0),
        ],
        rows: [
          for (final l in lignes) DataRow(cells: [for (final c in l) DataCell(Text(texteCellule(c)))]),
          if (totaux != null)
            DataRow(
              color: const WidgetStatePropertyAll(Color(0xFFE8EEF4)),
              cells: [for (final c in totaux) DataCell(Text(texteCellule(c), style: const TextStyle(fontWeight: FontWeight.bold)))],
            ),
        ],
      ),
    );

/// Élèves par tranche d'âge et par sexe : effectif, examinés, couverture.
Widget tableauTranches(Statistiques s) {
  int somme(int Function(LigneTrancheAge) f) => s.parTrancheAge.fold(0, (t, l) => t + f(l));
  final g = somme((l) => l.garcons), fi = somme((l) => l.filles);
  final gx = somme((l) => l.garconsExamines), fx = somme((l) => l.fillesExamines);
  return tableau([
    'Tranche d\'âge', 'Garçons', 'Filles', 'Effectif', 'Garçons examinés', 'Filles examinées', 'Examinés', 'Couverture'
  ], [
    for (final l in s.parTrancheAge)
      [l.tranche.libelle, l.garcons, l.filles, l.effectif, l.garconsExamines, l.fillesExamines, l.examines,
        pourcentage(l.tauxCouverture)]
  ], totaux: [
    'Total', g, fi, g + fi, gx, fx, gx + fx, pourcentage(taux(gx + fx, g + fi))
  ]);
}

List<Object?> ligneCouverture(Couverture c) =>
    [c.libelle, c.effectif, c.garcons, c.filles, c.examines, c.nonExamines, pourcentage(c.tauxCouverture)];

const entetesCouverture = ['', 'Effectif', 'Garçons', 'Filles', 'Examinés', 'Non examinés', 'Couverture'];
