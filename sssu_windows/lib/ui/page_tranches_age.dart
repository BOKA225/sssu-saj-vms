/// TRANCHES D'ÂGE PAR ÉTABLISSEMENT : élèves de chaque établissement par
/// tranche d'âge (0–4, 5–9, 10–14, 15–19, 20–24, 25–49 ans, 50 ans et plus)
/// et par sexe — inscrits, examinés ou couverture —, pour la visite
/// systématique ou la visite d'aptitude ; détail d'un établissement ;
/// exportation en PDF, Word ou Excel. Mis à jour après chaque
/// synchronisation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../rapports/service_rapports.dart';
import '../services.dart';
import 'commun.dart';
import 'page_rapports.dart' show exporterRapport;
import 'statistiques_commun.dart';

enum _Mesure {
  inscrits('Élèves inscrits', Icons.groups),
  examines('Élèves examinés', Icons.medical_services),
  couverture('Couverture', Icons.donut_large);

  final String libelle;
  final IconData icone;
  const _Mesure(this.libelle, this.icone);
}

/// Lignes de chaque établissement.
enum _Sexe {
  garcons('Garçons'),
  filles('Filles'),
  total('Total');

  final String libelle;
  const _Sexe(this.libelle);
}

class PageTranchesAge extends ConsumerStatefulWidget {
  const PageTranchesAge({super.key});
  @override
  ConsumerState<PageTranchesAge> createState() => _PageTranchesAgeState();
}

class _PageTranchesAgeState extends ConsumerState<PageTranchesAge> {
  late final Droits _droits = ref.read(sessionProvider)!.droits;
  late final ControleurStatistiques _c = ControleurStatistiques(ref.read(servicesProvider));
  _Mesure _mesure = _Mesure.inscrits;
  bool _occupe = false;

  @override
  void initState() {
    super.initState();
    _c.demarrer();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Les sexes sont des lignes du tableau : ni filtre de sexe, ni de classe.
  FiltreStatistiques get _filtre =>
      FiltreStatistiques(etablissementId: _c.etablissementId, du: _c.du, au: _c.au, typeVisite: _c.typeVisite);

  Future<void> _exporter(FormatRapport format) async {
    final s = ref.read(servicesProvider);
    setState(() => _occupe = true);
    try {
      final entete = await s.rapports.entete();
      if (!mounted) return;
      await exporterRapport(
          context,
          s,
          _droits,
          () => rapportTranchesAge(_c.jeu!, _filtre, entete: entete, acteur: _droits, genereLe: DateTime.now().toUtc()),
          format,
          table: _c.etablissementId == null ? 'annee_scolaire' : 'etablissement',
          id: _c.etablissementId ?? _c.annee?.id);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Object? _valeur(int garcons, int filles, int garconsExamines, int fillesExamines, _Sexe s) {
    final (n, x) = switch (s) {
      _Sexe.garcons => (garcons, garconsExamines),
      _Sexe.filles => (filles, fillesExamines),
      _Sexe.total => (garcons + filles, garconsExamines + fillesExamines),
    };
    return switch (_mesure) {
      _Mesure.inscrits => n,
      _Mesure.examines => x,
      _Mesure.couverture => pourcentage(taux(x, n)),
    };
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final jeu = _c.jeu;
          final t = jeu == null ? null : tranchesParEtablissement(jeu, _filtre);
          return ListView(padding: const EdgeInsets.all(24), children: [
            Text('Tranches d\'âge par établissement', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text('Élèves de chaque établissement par tranche d\'âge et par sexe. Les visites systématiques et les '
                'visites d\'aptitude (3ème et Tle) sont comptées séparément. Cliquez sur un établissement pour voir '
                'son détail.'),
            const SizedBox(height: 12),
            BarreFiltres(_c, classe: false, sexe: false),
            const SizedBox(height: 12),
            if (_c.erreur != null)
              Text('Lecture impossible : ${_c.erreur}')
            else if (t == null)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                    child: _c.annee == null && !_c.chargement
                        ? const Text('Aucune année scolaire.')
                        : const CircularProgressIndicator()),
              )
            else
              ..._contenu(t),
          ]);
        },
      );

  List<Widget> _contenu(TranchesParEtablissement t) {
    final e = t.ensemble;
    final aptitude = _c.typeVisite == TypeVisite.aptitude;
    final un = _c.etablissementId == null ? null : t.etablissements.firstOrNull;
    return [
      Wrap(children: [
        CarteIndicateur('${t.etablissements.length}', 'Établissements', icone: Icons.school),
        CarteIndicateur('${e.effectif}', aptitude ? 'Élèves de 3ème et Tle' : 'Élèves inscrits',
            detail: '${e.garcons} garçons · ${e.filles} filles', icone: Icons.groups),
        CarteIndicateur('${e.examines}', 'Élèves examinés',
            detail: '${e.garconsExamines} G · ${e.fillesExamines} F',
            icone: Icons.medical_services,
            couleur: Colors.green.shade700),
        CarteIndicateur(pourcentage(e.tauxCouverture), 'Taux de couverture',
            icone: Icons.donut_large, couleur: Colors.blue.shade800),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SegmentedButton<_Mesure>(
          segments: [
            for (final m in _Mesure.values) ButtonSegment(value: m, label: Text(m.libelle), icon: Icon(m.icone)),
          ],
          selected: {_mesure},
          onSelectionChanged: (v) => setState(() => _mesure = v.first),
        ),
        Text('Âge au ${dateFr(t.dateAge)}', style: const TextStyle(color: Colors.black54)),
        const SizedBox(width: 16),
        for (final f in FormatRapport.values)
          OutlinedButton.icon(
            onPressed: _occupe || _c.chargement ? null : () => _exporter(f),
            icon: Icon(switch (f) {
              FormatRapport.pdf => Icons.picture_as_pdf,
              FormatRapport.word => Icons.description,
              FormatRapport.excel => Icons.table_chart,
            }),
            label: Text('Exporter en ${f.libelle}'),
          ),
        if (_occupe) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      const SizedBox(height: 8),
      Panneau(
        '${_mesure.libelle} par tranche d\'âge et par sexe${aptitude ? ' (visite d\'aptitude)' : ''}',
        t.etablissements.isEmpty
            ? Text(aptitude ? 'Aucun établissement n\'a de classe de 3ème ou de terminale.' : 'Aucun établissement.')
            : _tableau(t),
      ),
      Panneau('${un?.libelle ?? 'Ensemble des établissements'} : effectif, examinés et couverture par tranche d\'âge',
          tableauRepartition(e)),
    ];
  }

  Widget _tableau(TranchesParEtablissement t) {
    const gras = TextStyle(fontWeight: FontWeight.bold);
    final plusieurs = t.etablissements.length > 1;
    DataRow ligne(RepartitionAges r, _Sexe s, {bool ensemble = false}) {
      final total = s == _Sexe.total;
      final style = total || ensemble ? gras : null;
      return DataRow(
        color: total ? WidgetStatePropertyAll(ensemble ? const Color(0xFFD3E0EF) : const Color(0xFFEDF2F8)) : null,
        onSelectChanged: plusieurs && !ensemble ? (_) => _c.changer(etablissement: r.id) : null,
        cells: [
          DataCell(s == _Sexe.garcons
              ? ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Text(r.libelle, style: gras, overflow: TextOverflow.ellipsis))
              : const SizedBox.shrink()),
          DataCell(Text(s.libelle, style: style)),
          for (final l in r.lignes)
            DataCell(Text(texteCellule(_valeur(l.garcons, l.filles, l.garconsExamines, l.fillesExamines, s)), style: style)),
          DataCell(Text(texteCellule(_valeur(r.garcons, r.filles, r.garconsExamines, r.fillesExamines, s)), style: gras)),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        headingRowHeight: 40,
        dataRowMinHeight: 28,
        dataRowMaxHeight: 34,
        columnSpacing: 22,
        columns: [
          const DataColumn(label: Text('Établissement', style: gras)),
          const DataColumn(label: Text('Sexe', style: gras)),
          for (final x in t.tranches) DataColumn(label: Text(x.abrege, style: gras), numeric: true),
          const DataColumn(label: Text('Total', style: gras), numeric: true),
        ],
        rows: [
          for (final r in t.etablissements)
            for (final s in _Sexe.values) ligne(r, s),
          if (plusieurs)
            for (final s in _Sexe.values) ligne(t.ensemble, s, ensemble: true),
        ],
      ),
    );
  }
}
