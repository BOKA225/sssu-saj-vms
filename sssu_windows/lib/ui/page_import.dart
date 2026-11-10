/// IMPORTATION DES LISTES D'ÉLÈVES sur le poste central : même analyse et
/// mêmes contrôles que sur le téléphone, validation explicite obligatoire.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sssu_core/sssu_core.dart';

import '../donnees/requetes_poste.dart';
import '../import/lecteurs_poste.dart';
import '../services.dart';
import 'commun.dart';

class PageImport extends ConsumerStatefulWidget {
  const PageImport({super.key});
  @override
  ConsumerState<PageImport> createState() => _PageImportState();
}

class _PageImportState extends ConsumerState<PageImport> {
  Annee? _annee;
  List<LigneEtablissement> _etabs = const [];
  String? _etab;
  List<LigneClasse> _classes = const [];
  String? _classe;
  String? _chemin;
  TableauBrut? _tableau;
  Map<int, ChampListe> _correspondance = {};
  List<LigneImport>? _lignes;
  List<IdentiteEleve> _existants = const [];
  String? _progression;
  String? _erreur;

  ServicesPoste get _s => ref.read(servicesProvider);
  Droits get _droits => ref.read(sessionProvider)!.droits;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final a = await _s.requetes.anneeCourante();
    if (a == null) return;
    final e = await _s.requetes.etablissements(a);
    if (mounted) {
      setState(() {
        _annee = a;
        _etabs = e;
      });
    }
  }

  Future<void> _choisirEtab(String? id) async {
    setState(() {
      _etab = id;
      _classe = null;
      _classes = const [];
    });
    if (id == null) return;
    final c = await _s.requetes.classes(id, _annee!);
    if (mounted) setState(() => _classes = c);
  }

  Future<void> _choisirFichier() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: extensionsListes);
    final chemin = r?.files.single.path;
    if (chemin == null) return;
    setState(() {
      _erreur = null;
      _progression = 'Lecture du fichier…';
      _lignes = null;
    });
    try {
      final t = await _s.lecteur.lire(chemin, progression: (etape) {
        if (mounted) setState(() => _progression = etape);
      });
      final existants = await _s.depot.transaction((tx) => tx.chercher('eleve', const {}));
      setState(() {
        _chemin = chemin;
        _tableau = t;
        _correspondance = Map.of(t.correspondance);
        _existants = [
          for (final e in existants)
            IdentiteEleve(
              id: e.id,
              matricule: e.donnees['matricule'] as String?,
              nom: e.donnees['nom']! as String,
              prenoms: e.donnees['prenoms']! as String,
              dateNaissance: e.donnees['date_naissance'] == null ? null : lireDate(e.donnees['date_naissance']! as String),
            ),
        ];
        _progression = null;
      });
    } on ErreurLecture catch (e) {
      setState(() {
        _erreur = e.message;
        _progression = null;
      });
    }
  }

  void _analyser() {
    final l = analyserTableau(_tableau!.avecCorrespondance(_correspondance));
    _controler(l);
    setState(() => _lignes = l);
  }

  void _controler([List<LigneImport>? l]) =>
      controlerLignes(l ?? _lignes!, existants: _existants, dateReference: DateTime.now().toUtc());

  Future<void> _corriger(LigneImport l) async {
    final c = {
      'matricule': TextEditingController(text: l.matricule ?? ''),
      'nom': TextEditingController(text: l.nom),
      'prenoms': TextEditingController(text: l.prenoms),
      'date': TextEditingController(text: l.dateNaissance == null ? '' : dateFr(l.dateNaissance)),
      'sexe': TextEditingController(text: l.sexe?.code ?? ''),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Ligne ${l.numeroSource}'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Lu : ${l.brut.values.join(' | ')}', style: const TextStyle(fontSize: 12)),
            for (final (k, lib) in [
              ('matricule', 'Matricule'),
              ('nom', 'Nom'),
              ('prenoms', 'Prénoms'),
              ('date', 'Date de naissance (JJ/MM/AAAA)'),
              ('sexe', 'Sexe (M ou F)'),
            ])
              TextField(controller: c[k], decoration: InputDecoration(labelText: lib)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok == true) {
      l
        ..matricule = normaliserMatricule(c['matricule']!.text)
        ..nom = c['nom']!.text.trim().toUpperCase()
        ..prenoms = c['prenoms']!.text.trim()
        ..dateNaissance = lireDateListe(c['date']!.text)
        ..sexe = lireSexe(c['sexe']!.text);
      _controler();
      setState(() {});
    }
    for (final t in c.values) {
      t.dispose();
    }
  }

  Future<void> _valider() async {
    final b = bilan(_lignes!);
    if (!await confirmer(context, 'Confirmer l\'importation',
        '${b.aCreer} nouveaux élèves, ${b.aRattacher} rattachés, ${b.ignorees} lignes non importées.',
        bouton: 'Importer')) {
      return;
    }
    if (!mounted) return;
    final octets = await File(_chemin!).readAsBytes();
    ResultatImportServeur? r;
    final ok = await executer(context, () async {
      r = await _s.gestion.importerListe(
        _droits,
        lignes: _lignes!,
        classeId: _classe!,
        format: _tableau!.format,
        nomFichier: p.basename(_chemin!),
        empreinteSha256: sha256Hex(octets),
      );
    });
    if (!ok || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Importation terminée'),
        content: Text('${r!.crees} dossiers créés, ${r!.rattaches} élèves rattachés, ${r!.changementsDeClasse} changements '
            'de classe, ${r!.ignores} lignes non importées.\nLes téléphones de l\'établissement recevront la liste à leur '
            'prochaine synchronisation.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
      ),
    );
    setState(() {
      _lignes = null;
      _tableau = null;
      _chemin = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_progression != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(_progression!),
      ]));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Importation des listes d\'élèves', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 320,
          child: DropdownButtonFormField<String>(
            value: _etab,
            decoration: const InputDecoration(labelText: 'Établissement'),
            items: [for (final e in _etabs) DropdownMenuItem(value: e.id, child: Text(e.nom, overflow: TextOverflow.ellipsis))],
            onChanged: _choisirEtab,
          ),
        ),
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<String>(
            value: _classe,
            decoration: InputDecoration(labelText: 'Classe (${_annee?.libelle ?? ''})'),
            items: [for (final c in _classes) DropdownMenuItem(value: c.id, child: Text('${c.libelle} · ${c.effectif} élèves'))],
            onChanged: (c) => setState(() => _classe = c),
          ),
        ),
        FilledButton.icon(
          onPressed: _classe == null ? null : _choisirFichier,
          icon: const Icon(Icons.folder_open),
          label: const Text('Choisir le fichier (Excel, CSV, PDF, image)'),
        ),
      ]),
      if (_erreur != null)
        Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(_erreur!))),
      if (_tableau != null && _lignes == null) ...[
        const SizedBox(height: 16),
        Text('Colonnes de « ${p.basename(_chemin!)} »', style: Theme.of(context).textTheme.titleMedium),
        Wrap(spacing: 12, runSpacing: 8, children: [
          for (var col = 0; col < _tableau!.nombreColonnes; col++)
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<ChampListe>(
                value: _correspondance[col] ?? ChampListe.ignorer,
                decoration: InputDecoration(
                  labelText: 'Colonne ${col + 1}'
                      '${_tableau!.ligneEntete != null && col < _tableau!.lignes[_tableau!.ligneEntete!].length ? ' « ${_tableau!.lignes[_tableau!.ligneEntete!][col]} »' : ''}',
                ),
                items: [for (final c in ChampListe.values) DropdownMenuItem(value: c, child: Text(c.libelle))],
                onChanged: (c) => setState(() =>
                    c == null || c == ChampListe.ignorer ? _correspondance.remove(col) : _correspondance[col] = c),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _correspondance.values.any((c) => c.estNom) ? _analyser : null,
            child: const Text('Analyser la liste'),
          ),
        ),
      ],
      if (_lignes != null) ..._controle(),
    ]);
  }

  List<Widget> _controle() {
    final b = bilan(_lignes!);
    return [
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: Text('${_lignes!.length} lignes : ${b.aCreer} nouveaux, ${b.aRattacher} rattachés, ${b.ignorees} non importés'
              '${b.bloquees == 0 ? '' : ', ${b.bloquees} en erreur'}'),
        ),
        FilledButton(onPressed: b.validable ? _valider : null, child: const Text('VALIDER L\'IMPORTATION')),
      ]),
      const SizedBox(height: 8),
      DataTable(
        columns: const [
          DataColumn(label: Text('Ligne')),
          DataColumn(label: Text('Matricule')),
          DataColumn(label: Text('Nom et prénoms')),
          DataColumn(label: Text('Sexe')),
          DataColumn(label: Text('Né(e) le')),
          DataColumn(label: Text('Contrôles')),
          DataColumn(label: Text('Action')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final l in _lignes!)
            DataRow(
              color: WidgetStatePropertyAll(l.action == ActionImport.ignorer
                  ? Colors.grey.shade200
                  : l.bloquee
                      ? Colors.red.shade50
                      : l.aVerifier
                          ? Colors.orange.shade50
                          : null),
              cells: [
                DataCell(Text('${l.numeroSource}')),
                DataCell(Text(l.matricule ?? '—')),
                DataCell(Text('${l.nom} ${l.prenoms}')),
                DataCell(Text(l.sexe?.code ?? '?')),
                DataCell(Text(l.dateNaissance == null ? '?' : dateFr(l.dateNaissance))),
                DataCell(SizedBox(
                  width: 320,
                  child: Text([...l.anomalies.map((a) => a.message), ...l.notes].join(' · '),
                      maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                )),
                DataCell(DropdownButton<ActionImport>(
                  value: l.action,
                  items: [
                    for (final a in ActionImport.values)
                      if (a != ActionImport.rattacher || l.eleveExistantId != null) DropdownMenuItem(value: a, child: Text(a.libelle)),
                  ],
                  onChanged: (a) {
                    if (a == null) return;
                    l.imposerAction(a);
                    _controler();
                    setState(() {});
                  },
                )),
                DataCell(IconButton(icon: const Icon(Icons.edit), tooltip: 'Corriger', onPressed: () => _corriger(l))),
              ],
            ),
        ],
      ),
    ];
  }
}
