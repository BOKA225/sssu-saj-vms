/// Inspections sanitaires sur le poste central : historique par
/// établissement, détail d'une inspection (grille, observations,
/// recommandations, photos des insuffisances, signature), rapport PDF ou
/// Excel ; paramétrage de la grille (droit `parametres.modifier`).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../rapports/service_rapports.dart';
import '../services.dart';
import 'commun.dart';
import 'page_rapports.dart';

Color _couleurNiveau(String? n) => switch (n) {
      'satisfaisant' => Colors.green.shade700,
      'moyen' => Colors.orange.shade800,
      'insuffisant' => Colors.red.shade700,
      _ => Colors.grey,
    };

Color _couleurClassement(ClassementGrille? c) => switch (c) {
      ClassementGrille.satisfaisant => Colors.green.shade700,
      ClassementGrille.acceptable => Colors.amber.shade800,
      ClassementGrille.insuffisant => Colors.orange.shade800,
      ClassementGrille.critique => Colors.red.shade700,
      null => Colors.grey,
    };

/// Niveau affiché : classement de la grille nationale (4 niveaux) ou niveau
/// de l'ancienne grille.
(String, Color) _niveauAffiche(Map<String, dynamic> i) {
  final niveau = i['niveau'] as String?;
  if (i['grille'] == true) {
    final c = classementEnregistre(niveau, (i['taux_conformite'] as num?)?.toDouble());
    return (c?.libelle ?? '—', _couleurClassement(c));
  }
  return (niveau == null ? '—' : NiveauConformite.depuisCode(niveau).libelle, _couleurNiveau(niveau));
}

class PageInspections extends ConsumerWidget {
  const PageInspections({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grille = ref.read(sessionProvider)!.droits.peut(Permission.parametresModifier);
    return DefaultTabController(
      length: grille ? 2 : 1,
      child: Column(children: [
        TabBar(isScrollable: true, tabs: [
          const Tab(text: 'Historique des inspections'),
          if (grille) const Tab(text: 'Grille d\'inspection'),
        ]),
        Expanded(child: TabBarView(children: [const _Historique(), if (grille) const _Grille()])),
      ]),
    );
  }
}

// --------------------------------------------------------------- historique

class _Historique extends ConsumerStatefulWidget {
  const _Historique();
  @override
  ConsumerState<_Historique> createState() => _HistoriqueState();
}

class _HistoriqueState extends ConsumerState<_Historique> {
  List<Map<String, dynamic>>? _liste;
  Map<String, String> _etablissements = const {};
  String? _etab;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final s = ref.read(servicesProvider);
    final l = await s.statistiques.inspections(etablissementId: _etab);
    final e = await s.depot.requete('SELECT CAST(id AS text) AS id, nom FROM etablissement WHERE deleted_at IS NULL ORDER BY nom');
    if (mounted) {
      setState(() {
        _liste = l;
        _etablissements = {for (final x in e) x['id'] as String: x['nom'] as String};
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(children: [
            DropdownButton<String?>(
              value: _etab,
              items: [
                const DropdownMenuItem(value: null, child: Text('Tous les établissements')),
                for (final e in _etablissements.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) {
                setState(() => _etab = v);
                _charger();
              },
            ),
            const SizedBox(width: 12),
            IconButton(onPressed: _charger, icon: const Icon(Icons.refresh), tooltip: 'Actualiser'),
            const Spacer(),
            Text(_liste == null ? '' : '${_liste!.length} inspection(s) reçue(s)'),
          ]),
        ),
        Expanded(
          child: _liste == null
              ? const Center(child: CircularProgressIndicator())
              : _liste!.isEmpty
                  ? const Center(child: Text('Aucune inspection reçue des téléphones.'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: DataTable(
                        showCheckboxColumn: false,
                        columns: const [
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Établissement')),
                          DataColumn(label: Text('Inspecteur')),
                          DataColumn(label: Text('C'), numeric: true),
                          DataColumn(label: Text('PC'), numeric: true),
                          DataColumn(label: Text('NC'), numeric: true),
                          DataColumn(label: Text('NA'), numeric: true),
                          DataColumn(label: Text('Score'), numeric: true),
                          DataColumn(label: Text('Classement')),
                          DataColumn(label: Text('Photos'), numeric: true),
                        ],
                        rows: [
                          for (final i in _liste!)
                            DataRow(
                              onSelectChanged: (_) => showDialog<void>(
                                  context: context, builder: (_) => _DetailInspection(inspectionId: i['id'] as String)),
                              cells: [
                                DataCell(Text(dateFr(i['date_inspection']))),
                                DataCell(Text('${i['etablissement']}')),
                                DataCell(Text('${i['inspecteur']}')),
                                DataCell(Text('${i['nb_conformes']}')),
                                DataCell(Text('${i['nb_partiels']}')),
                                DataCell(Text('${i['nb_non_conformes']}')),
                                DataCell(Text('${i['nb_non_applicables']}')),
                                DataCell(Text(pourcentage((i['taux_conformite'] as num?)?.toDouble()))),
                                DataCell(Text(_niveauAffiche(i).$1,
                                    style: TextStyle(color: _niveauAffiche(i).$2, fontWeight: FontWeight.bold))),
                                DataCell(Text('${i['photos']}')),
                              ],
                            ),
                        ],
                      ),
                    ),
        ),
      ]);
}

class _DetailInspection extends ConsumerStatefulWidget {
  final String inspectionId;
  const _DetailInspection({required this.inspectionId});
  @override
  ConsumerState<_DetailInspection> createState() => _DetailInspectionState();
}

class _DetailInspectionState extends ConsumerState<_DetailInspection> {
  FicheInspection? _fiche;
  Map<String, List<int>> _photos = const {};
  Object? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final s = ref.read(servicesProvider);
    try {
      final f = await s.depot.transaction((tx) => FicheInspection.charger(tx, widget.inspectionId));
      final p = await s.rapports.photosInspection(f);
      if (mounted) {
        setState(() {
          _fiche = f;
          _photos = p;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erreur = e);
    }
  }

  Future<void> _exporter(FormatRapport format) async {
    final s = ref.read(servicesProvider);
    final droits = ref.read(sessionProvider)!.droits;
    final entete = await s.rapports.entete();
    if (!mounted) return;
    await exporterRapport(
      context,
      s,
      droits,
      () => rapportInspection(_fiche!, entete: entete, acteur: droits, genereLe: DateTime.now().toUtc(), photos: _photos),
      format,
      table: 'inspection',
      id: widget.inspectionId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = _fiche;
    return Dialog(
      child: SizedBox(
        width: 960,
        height: 720,
        child: _erreur != null
            ? Center(child: Text('$_erreur'))
            : f == null
                ? const Center(child: CircularProgressIndicator())
                : Column(children: [
                    ListTile(
                      title: Text('Inspection du ${dateFr(f.inspection.donnees['date_inspection'])} · ${f.etablissement}',
                          style: Theme.of(context).textTheme.titleLarge),
                      subtitle: Text('Inspecteur : ${f.inspecteur ?? ''} · Année ${f.annee ?? ''}'),
                      trailing: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                    ),
                    const Divider(height: 1),
                    Expanded(child: _contenu(f)),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        OutlinedButton.icon(
                            onPressed: () => _exporter(FormatRapport.excel),
                            icon: const Icon(Icons.table_chart),
                            label: const Text('Excel')),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                            onPressed: () => _exporter(FormatRapport.word),
                            icon: const Icon(Icons.description),
                            label: const Text('Rapport Word')),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                            onPressed: () => _exporter(FormatRapport.pdf),
                            icon: const Icon(Icons.picture_as_pdf),
                            label: const Text('Rapport PDF')),
                      ]),
                    ),
                  ]),
      ),
    );
  }

  Widget _contenu(FicheInspection f) {
    final d = f.inspection.donnees;
    final parRubrique = grilleParRubrique(f.reponses.map((r) => r.critere));
    final reponse = {for (final r in f.reponses) r.critere.id: r};
    final signature = d['signature'] as String?;
    final ev = f.nationale ? f.evaluation() : null;
    final cl = ev?.classement;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (ev != null) ...[
        Text('Score global : ${pourcentage(ev.scoreGlobal)} · ${cl?.libelle ?? '—'}${cl == null ? '' : ' (${cl.couleur})'}',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _couleurClassement(cl))),
        if (ev.plafonne)
          const Text('Classement plafonné à « Insuffisant » : critère ★ non conforme.', style: TextStyle(color: Colors.red)),
        if (ev.critiquesNonConformes.isNotEmpty)
          Text('Critère(s) ★ non conforme(s) : ${ev.critiquesNonConformes.map((c) => '${c.code} ${c.libelle}').join(' ; ')}'),
        if (cl != null) Text('Conduite à tenir : ${cl.conduite}'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final x in ev.domaines)
            Chip(
              label: Text('${x.rubrique.lettre} · ${pourcentage(x.score)}'),
              backgroundColor: x.score == null ? null : _couleurClassement(ClassementGrille.depuisScore(x.score!)).withOpacity(0.15),
            ),
        ]),
        const SizedBox(height: 4),
        Text('Le rapport Word ou PDF reprend la grille complète (identification, structure et effectifs, ratios, '
            'critères cotés, récapitulatif, niveaux de service, plan d\'action) pour signature et cachet.',
            style: Theme.of(context).textTheme.bodySmall),
        const Divider(height: 24),
      ] else
      Wrap(spacing: 24, runSpacing: 8, children: [
        Text('Taux de conformité : ${pourcentage((d['taux_conformite'] as num?)?.toDouble())}',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _couleurNiveau(d['niveau'] as String?))),
        Text('Niveau : ${d['niveau'] == null ? '—' : NiveauConformite.depuisCode(d['niveau'] as String).libelle}'),
        Text('${d['nb_conformes']} conformes · ${d['nb_partiels']} partiels · ${d['nb_non_conformes']} non conformes · '
            '${d['nb_non_applicables']} non applicables'),
      ]),
      const SizedBox(height: 12),
      for (final MapEntry(key: rub, value: criteres) in parRubrique.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text('${rub.libelle} — ${rub.elements}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final c in criteres)
          ListTile(
            dense: true,
            leading: Icon(
              switch (reponse[c.id]!.resultat) {
                ResultatInspection.conforme => Icons.check_circle,
                ResultatInspection.partiel => Icons.adjust,
                ResultatInspection.nonConforme => Icons.cancel,
                ResultatInspection.nonApplicable => Icons.remove_circle_outline,
              },
              color: switch (reponse[c.id]!.resultat) {
                ResultatInspection.conforme => Colors.green,
                ResultatInspection.partiel => Colors.orange,
                ResultatInspection.nonConforme => Colors.red,
                ResultatInspection.nonApplicable => Colors.grey,
              },
            ),
            title: Text(c.libelleNumerote + (c.actif ? '' : '  (critère retiré depuis)')),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(reponse[c.id]!.resultat.libelle + (reponse[c.id]!.observation == null ? '' : ' · ${reponse[c.id]!.observation}')),
              if (reponse[c.id]!.photos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(spacing: 6, children: [
                    for (final p in reponse[c.id]!.photos)
                      _photos[p] == null
                          ? const Chip(label: Text('Photo en attente du téléphone', style: TextStyle(fontSize: 11)))
                          : GestureDetector(
                              onTap: () => showDialog<void>(
                                  context: context,
                                  builder: (_) => Dialog(
                                      child: InteractiveViewer(
                                          child: Image.memory(Uint8List.fromList(_photos[p]!), fit: BoxFit.contain)))),
                              child: Image.memory(Uint8List.fromList(_photos[p]!), width: 96, height: 72, fit: BoxFit.cover),
                            ),
                  ]),
                ),
            ]),
          ),
      ],
      const Divider(height: 32),
      Text('Observations', style: Theme.of(context).textTheme.titleSmall),
      Text((d['observations'] as String?) ?? 'Néant.'),
      const SizedBox(height: 12),
      Text('Recommandations', style: Theme.of(context).textTheme.titleSmall),
      Text((d['recommandations'] as String?) ?? 'Néant.'),
      const SizedBox(height: 12),
      Text('Signature de l\'inspecteur', style: Theme.of(context).textTheme.titleSmall),
      if (signature == null)
        const Text('Aucune.')
      else
        Align(alignment: Alignment.centerLeft, child: Image.memory(base64.decode(signature), height: 90)),
    ]);
  }
}

// ------------------------------------------------------------------- grille

class _Grille extends ConsumerStatefulWidget {
  const _Grille();
  @override
  ConsumerState<_Grille> createState() => _GrilleState();
}

class _GrilleState extends ConsumerState<_Grille> {
  List<CritereGrille>? _criteres;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final l = await ref.read(servicesProvider).statistiques.grille();
    if (mounted) setState(() => _criteres = l);
  }

  Future<void> _editer({CritereGrille? critere, RubriqueInspection? rubrique}) async {
    final libelle = TextEditingController(text: critere?.libelle ?? '');
    final ordre = TextEditingController(text: critere == null ? '' : '${critere.ordre}');
    var rub = critere?.rubrique ?? rubrique ?? RubriqueInspection.eauBoisson;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: Text(critere == null ? 'Nouveau critère' : 'Modifier le critère'),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<RubriqueInspection>(
                value: rub,
                decoration: const InputDecoration(labelText: 'Rubrique'),
                items: [
                  for (final r in RubriqueInspection.values)
                    if (!r.ancienne || r == rub) DropdownMenuItem(value: r, child: Text(r.libelle))
                ],
                onChanged: critere == null ? (v) => setD(() => rub = v!) : null,
              ),
              TextField(controller: libelle, decoration: const InputDecoration(labelText: 'Critère à inspecter'), autofocus: true),
              TextField(
                  controller: ordre,
                  decoration: const InputDecoration(labelText: 'Ordre d\'affichage (facultatif)'),
                  keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              const Text('Les inspections déjà faites gardent leurs réponses. Le critère est envoyé aux téléphones à leur '
                  'prochaine synchronisation.', style: TextStyle(fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final s = ref.read(servicesProvider);
    final droits = ref.read(sessionProvider)!.droits;
    final o = int.tryParse(ordre.text.trim());
    await executer(
      context,
      () async {
        if (critere == null) {
          await s.gestion.creerCritere(droits, rubrique: rub, libelle: libelle.text, ordre: o);
        } else {
          await s.gestion.modifierCritere(droits, critere.id, libelle: libelle.text, ordre: o);
        }
      },
      succes: 'Grille mise à jour.',
    );
    _charger();
  }

  Future<void> _activer(CritereGrille c, bool actif) async {
    final s = ref.read(servicesProvider);
    await executer(context, () => s.gestion.activerCritere(ref.read(sessionProvider)!.droits, c.id, actif: actif),
        succes: actif ? 'Critère rétabli.' : 'Critère retiré des inspections suivantes.');
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    final l = _criteres;
    if (l == null) return const Center(child: CircularProgressIndicator());
    final grille = grilleParRubrique(l);
    // Grille nationale (B à J), puis rubriques de l'ancienne grille qui ont
    // encore des critères (désactivés en 1.2.0, réactivables).
    final parRubrique = {
      for (final r in RubriqueInspection.values)
        if (!r.ancienne || (grille[r]?.isNotEmpty ?? false)) r: grille[r] ?? const <CritereGrille>[]
    };
    return ListView(padding: const EdgeInsets.all(24), children: [
      Row(children: [
        Expanded(
          child: Text('${l.where((c) => c.actif).length} critères actifs sur ${l.length}. '
              'Grille nationale : chaque critère se cote C (conforme), NC (non conforme) ou NA (non applicable) ; '
              'les critères ★ sont critiques. Les rubriques de l\'ancienne grille sont repliées en bas.'),
        ),
        FilledButton.icon(onPressed: () => _editer(), icon: const Icon(Icons.add), label: const Text('Ajouter un critère')),
      ]),
      const SizedBox(height: 12),
      for (final MapEntry(key: rub, value: criteres) in parRubrique.entries)
        Card(
          child: ExpansionTile(
            initiallyExpanded: !rub.ancienne,
            title: Text(rub.ancienne ? '${rub.libelle} (ancienne grille)' : rub.libelle),
            subtitle: Text('${rub.elements} · ${criteres.where((c) => c.actif).length} critère(s) actif(s)'),
            trailing: IconButton(
                tooltip: 'Ajouter un critère à cette rubrique',
                onPressed: () => _editer(rubrique: rub),
                icon: const Icon(Icons.add)),
            children: [
              for (final c in criteres)
                ListTile(
                  dense: true,
                  leading: Text('${c.ordre}'),
                  title: Text(c.libelleNumerote,
                      style: TextStyle(
                          color: c.actif ? null : Colors.black38, decoration: c.actif ? null : TextDecoration.lineThrough)),
                  subtitle: Text(c.code, style: const TextStyle(fontSize: 11)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(tooltip: 'Modifier', onPressed: () => _editer(critere: c), icon: const Icon(Icons.edit)),
                    Switch(value: c.actif, onChanged: (v) => _activer(c, v)),
                  ]),
                ),
              if (criteres.isEmpty) const ListTile(title: Text('Aucun critère.')),
            ],
          ),
        ),
    ]);
  }
}
