/// GESTION DES ÉTABLISSEMENTS : années scolaires, établissements, classes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../donnees/requetes_poste.dart';
import '../services.dart';
import 'commun.dart';
import 'dialogue_etablissement.dart';

class PageEtablissements extends ConsumerStatefulWidget {
  const PageEtablissements({super.key});
  @override
  ConsumerState<PageEtablissements> createState() => _PageEtablissementsState();
}

class _PageEtablissementsState extends ConsumerState<PageEtablissements> {
  List<Annee> _annees = const [];
  Annee? _annee;
  List<LigneEtablissement> _etabs = const [];
  LigneEtablissement? _choisi;
  List<LigneClasse> _classes = const [];

  Droits get _droits => ref.read(sessionProvider)!.droits;
  ServicesPoste get _s => ref.read(servicesProvider);

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final annees = await _s.requetes.annees();
    final annee = _annee == null
        ? (annees.isEmpty ? null : annees.firstWhere((a) => a.active, orElse: () => annees.first))
        : annees.firstWhere((a) => a.id == _annee!.id, orElse: () => annees.first);
    final etabs = annee == null ? <LigneEtablissement>[] : await _s.requetes.etablissements(annee);
    final choisi = _choisi == null ? null : etabs.where((e) => e.id == _choisi!.id).firstOrNull;
    final classes = choisi == null || annee == null ? <LigneClasse>[] : await _s.requetes.classes(choisi.id, annee);
    if (!mounted) return;
    setState(() {
      _annees = annees;
      _annee = annee;
      _etabs = etabs;
      _choisi = choisi;
      _classes = classes;
    });
  }

  // -------------------------------------------------------------- années

  Future<void> _nouvelleAnnee() async {
    final libelle = TextEditingController();
    DateTime? debut, fin;
    var active = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, maj) => AlertDialog(
          title: const Text('Nouvelle année scolaire'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: libelle, decoration: const InputDecoration(labelText: 'Libellé (ex. 2027-2028)')),
              const SizedBox(height: 8),
              for (final (lib, estDebut) in [('Date de rentrée', true), ('Date de fin', false)])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('$lib : ${dateFr(estDebut ? debut : fin)}'),
                  trailing: const Icon(Icons.event),
                  onTap: () async {
                    final d = await showDatePicker(context: c, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) maj(() => estDebut ? debut = d : fin = d);
                  },
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Année active (utilisée par défaut sur les téléphones)'),
                value: active,
                onChanged: (v) => maj(() => active = v ?? false),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Créer')),
          ],
        ),
      ),
    );
    final l = libelle.text;
    libelle.dispose();
    if (ok != true || !mounted) return;
    if (debut == null || fin == null) return message(context, 'Indiquer les dates de début et de fin.');
    await executer(context, () async {
      await _s.gestion.creerAnnee(_droits,
          libelle: l, debut: DateTime.utc(debut!.year, debut!.month, debut!.day), fin: DateTime.utc(fin!.year, fin!.month, fin!.day), active: active);
    }, succes: 'Année scolaire créée.');
    _annee = null;
    await _charger();
  }

  // ------------------------------------------------------- établissements

  Future<void> _editerEtablissement(LigneEtablissement? e) async {
    if (await editerEtablissement(context, ref, e?.donnees)) await _charger();
  }

  Future<void> _archiver(LigneEtablissement e) async {
    if (!await confirmer(context, 'Archiver « ${e.nom} » ?',
        'L\'établissement et ses classes ne seront plus proposés. L\'archivage est refusé si des dossiers médicaux y sont rattachés.')) {
      return;
    }
    if (!mounted) return;
    await executer(context, () => _s.gestion.archiverEtablissement(_droits, e.id), succes: 'Établissement archivé.');
    _choisi = null;
    await _charger();
  }

  // -------------------------------------------------------------- classes

  Future<void> _editerClasse(LigneClasse? c) async {
    final libelle = TextEditingController(text: c?.libelle ?? '');
    final niveau = TextEditingController(text: c?.niveau ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(c == null ? 'Nouvelle classe' : 'Modifier la classe'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: libelle, decoration: const InputDecoration(labelText: 'Libellé (ex. CM2 A)')),
            const SizedBox(height: 8),
            TextField(controller: niveau, decoration: const InputDecoration(labelText: 'Niveau (ex. CM2)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    final l = libelle.text, n = niveau.text;
    libelle.dispose();
    niveau.dispose();
    if (ok != true || !mounted) return;
    await executer(context, () async {
      if (c == null) {
        await _s.gestion.creerClasse(_droits,
            etablissementId: _choisi!.id, anneeScolaireId: _annee!.id, libelle: l, niveau: n);
      } else {
        await _s.gestion.modifierClasse(_droits, c.id, libelle: l, niveau: n);
      }
    });
    await _charger();
  }

  @override
  Widget build(BuildContext context) {
    final gerer = _droits.peut(Permission.etablissementGerer);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        flex: 3,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            Text('Établissements', style: Theme.of(context).textTheme.headlineSmall),
            const Spacer(),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                value: _annee?.id,
                decoration: const InputDecoration(labelText: 'Année scolaire'),
                items: [
                  for (final a in _annees) DropdownMenuItem(value: a.id, child: Text('${a.libelle}${a.active ? ' (active)' : ''}'))
                ],
                onChanged: (id) {
                  _annee = _annees.firstWhere((a) => a.id == id);
                  _charger();
                },
              ),
            ),
            if (_droits.peut(Permission.parametresModifier))
              IconButton(tooltip: 'Nouvelle année scolaire', icon: const Icon(Icons.add_box), onPressed: _nouvelleAnnee),
            if (_annee != null && !_annee!.active && _droits.peut(Permission.parametresModifier))
              TextButton(
                onPressed: () async {
                  await executer(context, () => _s.gestion.activerAnnee(_droits, _annee!.id), succes: 'Année activée.');
                  _charger();
                },
                child: const Text('Rendre active'),
              ),
            const SizedBox(width: 8),
            if (gerer)
              FilledButton.icon(
                  onPressed: () => _editerEtablissement(null), icon: const Icon(Icons.add), label: const Text('Établissement')),
          ]),
          const SizedBox(height: 16),
          DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Nom')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Classes'), numeric: true),
              DataColumn(label: Text('Effectif'), numeric: true),
              DataColumn(label: Text('Examinés'), numeric: true),
              DataColumn(label: Text('Couverture'), numeric: true),
              DataColumn(label: Text('Téléphones'), numeric: true),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final e in _etabs)
                DataRow(
                  selected: _choisi?.id == e.id,
                  onSelectChanged: (_) {
                    _choisi = e;
                    _charger();
                  },
                  cells: [
                    DataCell(Text(e.nom)),
                    DataCell(Text('${TypeEtablissement.depuisCode(e.donnees['type'] as String).libelle} · '
                        '${StatutEtablissement.depuisCode(e.donnees['statut'] as String).libelle}')),
                    DataCell(Text('${e.classes}')),
                    DataCell(Text('${e.effectif}')),
                    DataCell(Text('${e.examines}')),
                    DataCell(Text(e.effectif == 0 ? '—' : '${(e.examines * 100 / e.effectif).round()} %')),
                    DataCell(Text('${e.telephones}')),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      if (gerer) IconButton(tooltip: 'Modifier', icon: const Icon(Icons.edit), onPressed: () => _editerEtablissement(e)),
                      if (_droits.peut(Permission.etablissementArchiver))
                        IconButton(tooltip: 'Archiver', icon: const Icon(Icons.archive_outlined), onPressed: () => _archiver(e)),
                    ])),
                  ],
                ),
            ],
          ),
        ]),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        flex: 2,
        child: _choisi == null
            ? const Center(child: Text('Sélectionnez un établissement pour voir ses classes.'))
            : ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  Expanded(child: Text('Classes · ${_choisi!.nom}', style: Theme.of(context).textTheme.titleLarge)),
                  if (gerer && _annee != null)
                    FilledButton.icon(onPressed: () => _editerClasse(null), icon: const Icon(Icons.add), label: const Text('Classe')),
                ]),
                const SizedBox(height: 8),
                if (_classes.isEmpty) const Text('Aucune classe pour cette année scolaire.'),
                for (final c in _classes)
                  Card(
                    child: ListTile(
                      title: Text(c.libelle),
                      subtitle: Text('${c.effectif} élèves (${c.garcons} G, ${c.filles} F) · ${c.examines} examinés'),
                      trailing: !gerer
                          ? null
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(tooltip: 'Modifier', icon: const Icon(Icons.edit), onPressed: () => _editerClasse(c)),
                              IconButton(
                                tooltip: 'Archiver',
                                icon: const Icon(Icons.archive_outlined),
                                onPressed: () async {
                                  await executer(context, () => _s.gestion.archiverClasse(_droits, c.id), succes: 'Classe archivée.');
                                  _charger();
                                },
                              ),
                            ]),
                    ),
                  ),
              ]),
      ),
    ]);
  }
}
