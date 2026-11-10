/// Tableau de bord statistique (section 12) : statistiques générales, par
/// sexe, par établissement et par classe, profil des pathologies,
/// inspections sanitaires, évolution. Filtrable par année scolaire,
/// établissement, classe, sexe et période ; mis à jour automatiquement après
/// chaque synchronisation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../services.dart';
import 'statistiques_commun.dart';

class PageStatistiques extends ConsumerStatefulWidget {
  const PageStatistiques({super.key});
  @override
  ConsumerState<PageStatistiques> createState() => _PageStatistiquesState();
}

class _PageStatistiquesState extends ConsumerState<PageStatistiques> with SingleTickerProviderStateMixin {
  late final ControleurStatistiques _c = ControleurStatistiques(ref.read(servicesProvider));
  late final TabController _onglets = TabController(length: 4, vsync: this);

  @override
  void initState() {
    super.initState();
    _c.demarrer();
  }

  @override
  void dispose() {
    _c.dispose();
    _onglets.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final s = _c.statistiques;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.fromLTRB(24, 16, 24, 0), child: BarreFiltres(_c)),
            TabBar(controller: _onglets, isScrollable: true, tabs: const [
              Tab(text: 'Couverture'),
              Tab(text: 'Pathologies'),
              Tab(text: 'Inspections sanitaires'),
              Tab(text: 'Évolution'),
            ]),
            Expanded(
              child: _c.erreur != null
                  ? Center(child: Text('Lecture impossible : ${_c.erreur}'))
                  : s == null
                      ? Center(
                          child: _c.annee == null && !_c.chargement
                              ? const Text('Aucune année scolaire.')
                              : const CircularProgressIndicator())
                      : TabBarView(controller: _onglets, children: [
                          _couverture(s),
                          _pathologies(s),
                          _inspections(s),
                          _evolution(s),
                        ]),
            ),
          ]);
        },
      );

  Widget _liste(List<Widget> enfants) => ListView(padding: const EdgeInsets.all(20), children: enfants);

  Widget _couverture(Statistiques s) {
    final g = s.generale;
    final parEtab = _c.etablissementId == null && _c.classeId == null && s.parEtablissement.length > 1;
    final lignes = parEtab ? s.parEtablissement : s.parClasse;
    return _liste([
      Wrap(children: cartesGenerales(s)),
      Wrap(children: [
        Panneau('Couverture par ${parEtab ? 'établissement' : 'classe'}', histogrammeCouverture(lignes),
            largeur: 640, hauteur: 260),
        Panneau(
            'Élèves examinés par sexe',
            camembert([
              ('Garçons', g.garconsExamines, couleurGarcons),
              ('Filles', g.fillesExamines, couleurFilles),
            ]),
            largeur: 380,
            hauteur: 200),
        Panneau(
            'Conclusions (dernière visite)',
            camembert([
              for (final (i, c) in ConclusionVisite.values.indexed)
                (c.libelle.replaceFirst('Élève ', ''), s.conclusions[c] ?? 0, couleursSerie[[2, 1, 4, 3][i]])
            ]),
            largeur: 520,
            hauteur: 200),
      ]),
      Panneau(
        'Par sexe',
        tableau(['Sexe', 'Effectif', 'Examinés', 'Couverture', 'Part des examinés'], [
          ['Garçons', g.garcons, g.garconsExamines, pourcentage(g.tauxGarcons), pourcentage(g.partGarconsExamines)],
          ['Filles', g.filles, g.fillesExamines, pourcentage(g.tauxFilles), pourcentage(g.partFillesExamines)],
        ], totaux: [
          'Total', g.effectif, g.examines, pourcentage(g.tauxCouverture), g.examines == 0 ? '—' : '100 %'
        ]),
      ),
      if (s.parEtablissement.length > 1)
        Panneau(
            'Par établissement',
            tableau(['Établissement', ...entetesCouverture.skip(1)], [for (final c in s.parEtablissement) ligneCouverture(c)],
                totaux: ligneCouverture(g)..[0] = 'Total')),
      Panneau('Par classe',
          tableau(['Classe', ...entetesCouverture.skip(1)], [for (final c in s.parClasse) ligneCouverture(c)],
              totaux: ligneCouverture(g)..[0] = 'Total')),
    ]);
  }

  Widget _pathologies(Statistiques s) {
    final avecCas = s.pathologies.where((p) => p.cas > 0).toList()..sort((a, b) => b.cas.compareTo(a.cas));
    final tranches = TrancheAge.values.where((t) => avecCas.any((p) => (p.parTranche[t] ?? 0) > 0)).toList();
    final jeu = _c.jeu!;
    return _liste([
      Wrap(children: [
        CarteIndicateur('${s.generale.examines}', 'Élèves examinés'),
        CarteIndicateur('${s.elevesAvecPathologie}', 'Porteurs d\'au moins une pathologie',
            detail: pourcentage(taux(s.elevesAvecPathologie, s.generale.examines)), couleur: Colors.red.shade700),
        CarteIndicateur('${avecCas.length}', 'Pathologies dépistées'),
      ]),
      Panneau(
        'Prévalence par pathologie',
        barresHorizontales([
          for (final p in avecCas) (p.libelle, p.prevalence ?? 0, '${p.cas} cas · ${pourcentage(p.prevalence)}')
        ]),
      ),
      Panneau(
        'Cas par pathologie et par sexe',
        tableau(['Pathologie', 'Cas', 'Garçons', 'Filles', 'Prévalence'], [
          for (final p in s.pathologies) [p.libelle, p.cas, p.garcons, p.filles, pourcentage(p.prevalence)]
        ]),
      ),
      if (avecCas.isNotEmpty)
        Panneau(
          'Par tranche d\'âge',
          tableau(['Pathologie', for (final t in tranches) t.libelle], [
            for (final p in avecCas) [p.libelle, for (final t in tranches) p.parTranche[t] ?? 0]
          ]),
        ),
      if (avecCas.isNotEmpty && s.parEtablissement.length > 1)
        Panneau(
          'Par établissement',
          tableau(['Pathologie', for (final e in s.parEtablissement) e.libelle], [
            for (final p in avecCas) [p.libelle, for (final e in s.parEtablissement) p.parEtablissement[e.id] ?? 0]
          ]),
        ),
      if (avecCas.isNotEmpty && s.parClasse.length > 1)
        Panneau(
          'Par classe',
          tableau(['Pathologie', for (final c in s.parClasse) jeu.classes[c.id]?.libelle ?? c.libelle], [
            for (final p in avecCas) [p.libelle, for (final c in s.parClasse) p.parClasse[c.id] ?? 0]
          ]),
        ),
    ]);
  }

  Widget _inspections(Statistiques s) {
    final x = s.inspections;
    final jeu = _c.jeu!;
    return _liste([
      Wrap(children: [
        CarteIndicateur('${x.inspectes}/${x.etablissements}', 'Établissements inspectés', icone: Icons.fact_check),
        CarteIndicateur('${x.satisfaisants}', 'Conformes (satisfaisant)', couleur: Colors.green.shade700),
        CarteIndicateur('${x.nonConformes}', 'Non conformes', detail: '${x.moyens} moyen(s) · ${x.insuffisants} insuffisant(s)',
            couleur: Colors.red.shade700),
        CarteIndicateur(pourcentage(x.tauxMoyen), 'Taux moyen de conformité'),
      ]),
      if (_c.sexe != null || _c.classeId != null)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Les filtres de sexe et de classe ne s\'appliquent pas aux inspections.',
              style: TextStyle(fontStyle: FontStyle.italic)),
        ),
      Wrap(children: [
        Panneau(
            'Niveau des établissements inspectés',
            camembert([
              ('Satisfaisant', x.satisfaisants, Colors.green.shade600),
              ('Moyen', x.moyens, Colors.orange.shade700),
              ('Insuffisant', x.insuffisants, Colors.red.shade600),
              ('Non inspectés', x.etablissements - x.inspectes, Colors.grey.shade400),
            ]),
            largeur: 440,
            hauteur: 200),
        Panneau(
          'Principales insuffisances',
          barresHorizontales([
            for (final i in x.principalesInsuffisances.take(12))
              (i.libelle, i.total.toDouble(), '${i.nonConformes} non conf. · ${i.partiels} partiel(s)')
          ], couleur: Colors.orange.shade800),
          largeur: 720,
        ),
      ]),
      Panneau(
        'Dernière inspection par établissement',
        tableau(['Établissement', 'Date', 'Conformes', 'Partiels', 'Non conformes', 'Non applicables', 'Taux', 'Niveau'], [
          for (final e in jeu.etablissements.keys)
            if (x.dernieres[e] case final i?)
              [jeu.etablissements[e], _date(i.date), i.conformes, i.partiels, i.nonConformes, i.nonApplicables,
                pourcentage(i.taux), i.niveau?.libelle ?? '—']
        ]),
      ),
    ]);
  }

  Widget _evolution(Statistiques s) => _liste([
        Panneau(
          'Évolution mensuelle (bleu : couverture cumulée ; orange : visites du mois)',
          courbeEvolution(s.evolution),
          hauteur: 320,
        ),
        Panneau(
          'Détail par mois',
          tableau(['Mois', 'Visites', 'Nouveaux examinés', 'Couverture cumulée'], [
            for (final e in s.evolution) [e.mois, e.visites, e.nouveauxExamines, pourcentage(e.couvertureCumulee)]
          ]),
        ),
      ]);

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
