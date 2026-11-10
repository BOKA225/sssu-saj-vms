/// Statistiques simplifiées du téléphone (section 12) : données présentes sur
/// l'appareil uniquement. Le tableau de bord complet est sur le poste central.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../services.dart';

class EcranStatistiques extends ConsumerStatefulWidget {
  const EcranStatistiques({super.key});
  @override
  ConsumerState<EcranStatistiques> createState() => _EcranStatistiquesState();
}

class _EcranStatistiquesState extends ConsumerState<EcranStatistiques> {
  JeuStatistiques? _jeu;
  bool _charge = false;
  String? _etab;
  Sexe? _sexe;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final j = await ref.read(servicesProvider).requetes.jeuStatistiques();
    if (mounted) {
      setState(() {
        _jeu = j;
        _charge = true;
      });
    }
  }

  Widget _kpi(String valeur, String libelle, {Color? couleur}) => SizedBox(
        width: 150,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(valeur, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: couleur)),
              Text(libelle, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );

  Widget _barre(String libelle, double? valeur, String texte) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(libelle)), Text(texte, style: const TextStyle(fontWeight: FontWeight.bold))]),
          const SizedBox(height: 2),
          LinearProgressIndicator(value: (valeur ?? 0) / 100, minHeight: 6),
        ]),
      );

  Widget _section(String titre, List<Widget> enfants) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ...enfants,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final jeu = _jeu;
    if (!_charge) return Scaffold(appBar: AppBar(title: const Text('Statistiques')), body: const Center(child: CircularProgressIndicator()));
    if (jeu == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Statistiques')),
          body: const Padding(padding: EdgeInsets.all(24), child: Text('Aucune année scolaire : synchronisez le téléphone.')));
    }
    final s = calculerStatistiques(jeu, FiltreStatistiques(etablissementId: _etab, sexe: _sexe));
    final g = s.generale;
    final pathos = s.pathologies.where((p) => p.cas > 0).toList()..sort((a, b) => b.cas.compareTo(a.cas));
    return Scaffold(
      appBar: AppBar(title: Text('Statistiques · ${jeu.annee.libelle}')),
      body: RefreshIndicator(
        onRefresh: _charger,
        child: ListView(padding: const EdgeInsets.all(8), children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text('Données présentes sur ce téléphone uniquement. Le tableau de bord complet du district est '
                'sur le poste central.', style: TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          Wrap(spacing: 8, children: [
            DropdownButton<String?>(
              value: _etab,
              hint: const Text('Tous les établissements'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tous les établissements')),
                for (final e in jeu.etablissements.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _etab = v),
            ),
            DropdownButton<Sexe?>(
              value: _sexe,
              items: const [
                DropdownMenuItem(value: null, child: Text('Garçons et filles')),
                DropdownMenuItem(value: Sexe.masculin, child: Text('Garçons')),
                DropdownMenuItem(value: Sexe.feminin, child: Text('Filles')),
              ],
              onChanged: (v) => setState(() => _sexe = v),
            ),
          ]),
          Wrap(children: [
            _kpi('${g.effectif}', 'élèves (${g.garcons} G · ${g.filles} F)'),
            _kpi('${g.examines}', 'examinés'),
            _kpi('${g.nonExamines}', 'non examinés'),
            _kpi(pourcentage(g.tauxCouverture), 'couverture', couleur: Theme.of(context).colorScheme.primary),
            _kpi('${s.nbVisites}', 'visites'),
            _kpi('${s.inspections.inspectes}/${s.inspections.etablissements}', 'établissements inspectés'),
          ]),
          _section('Couverture par ${_etab == null && s.parEtablissement.length > 1 ? 'établissement' : 'classe'}', [
            for (final c in _etab == null && s.parEtablissement.length > 1 ? s.parEtablissement : s.parClasse)
              _barre(c.libelle, c.tauxCouverture, '${c.examines}/${c.effectif} · ${pourcentage(c.tauxCouverture)}'),
          ]),
          _section('Conclusions des visites', [
            for (final c in ConclusionVisite.values)
              _barre(c.libelle, taux(s.conclusions[c] ?? 0, g.examines), '${s.conclusions[c] ?? 0}'),
          ]),
          _section('Pathologies dépistées', [
            if (pathos.isEmpty) const Text('Aucune pathologie dépistée.'),
            for (final p in pathos.take(10))
              _barre(p.libelle, p.prevalence, '${p.cas} (${p.garcons} G · ${p.filles} F) · ${pourcentage(p.prevalence)}'),
          ]),
          if (s.inspections.inspectes > 0)
            _section('Inspections sanitaires (faites sur ce téléphone)', [
              Text('Taux moyen de conformité : ${pourcentage(s.inspections.tauxMoyen)}'),
              Text('${s.inspections.satisfaisants} satisfaisant(s) · ${s.inspections.moyens} moyen(s) · '
                  '${s.inspections.insuffisants} insuffisant(s)'),
              if (s.inspections.principalesInsuffisances.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Principales insuffisances :'),
                for (final i in s.inspections.principalesInsuffisances.take(5))
                  Text('• ${i.libelle} (${i.nonConformes} NC, ${i.partiels} PC)'),
              ],
            ]),
        ]),
      ),
    );
  }
}
