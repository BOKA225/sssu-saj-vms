/// IMPORTATION DE LA LISTE DES ÉTABLISSEMENTS sur le poste central : fichier
/// Excel ou CSV, colonnes reconnues automatiquement (à vérifier), contrôle de
/// chaque ligne (création ou mise à jour d'un établissement connu), puis
/// validation explicite.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sssu_core/sssu_core.dart';

import '../import/lecteurs_poste.dart';
import '../services.dart';
import 'commun.dart';

/// Ouvre l'importation ; renvoie vrai si des établissements ont été enregistrés.
Future<bool> importerEtablissements(BuildContext context) async =>
    await showDialog<bool>(context: context, builder: (_) => const _DialogueImport()) ?? false;

class _DialogueImport extends ConsumerStatefulWidget {
  const _DialogueImport();
  @override
  ConsumerState<_DialogueImport> createState() => _DialogueImportState();
}

class _DialogueImportState extends ConsumerState<_DialogueImport> {
  String? _fichier;
  List<List<String>>? _brut;
  int? _entete;
  Map<int, ChampEtablissement> _colonnes = {};
  List<LigneEtablissementImport>? _lignes;
  String? _erreur;
  bool _occupe = false;

  ServicesPoste get _s => ref.read(servicesProvider);

  Future<void> _choisir() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx', 'csv', 'txt']);
    final chemin = r?.files.single.path;
    if (chemin == null) return;
    setState(() {
      _erreur = null;
      _lignes = null;
    });
    try {
      final brut = await _s.lecteur.lireLignes(chemin);
      final e = detecterEnteteEtablissements(brut);
      setState(() {
        _fichier = p.basename(chemin);
        _brut = brut;
        _entete = e?.$1;
        _colonnes = Map.of(e?.$2 ?? {});
      });
      if (e != null) await _analyser();
    } on ErreurLecture catch (e) {
      setState(() => _erreur = e.message);
    }
  }

  int get _nombreColonnes => (_brut ?? const []).fold(0, (m, l) => l.length > m ? l.length : m);

  Future<void> _analyser() async {
    final existants = await _s.depot.requete('SELECT CAST(id AS text) AS id, code, nom FROM etablissement WHERE deleted_at IS NULL');
    final l = analyserEtablissements(
      _brut!,
      ligneEntete: _entete,
      correspondance: _colonnes,
      existants: [for (final x in existants) EtablissementExistant(x['id'] as String, x['code'] as String, x['nom'] as String)],
    );
    if (mounted) setState(() => _lignes = l);
  }

  Future<void> _valider() async {
    final b = bilanEtablissements(_lignes!);
    if (!await confirmer(context, 'Importer la liste ?',
        '${b.aCreer} établissement(s) à créer, ${b.aMettreAJour} à mettre à jour, ${b.ignorees} ligne(s) ignorée(s).',
        bouton: 'Importer')) {
      return;
    }
    if (!mounted) return;
    setState(() => _occupe = true);
    ResultatImportEtablissements? r;
    final ok = await executer(context, () async {
      r = await _s.gestion.importerEtablissements(ref.read(sessionProvider)!.droits, _lignes!);
    });
    if (!mounted) return;
    setState(() => _occupe = false);
    if (!ok || r == null) return;
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Importation terminée'),
        content: Text('${r!.crees} établissement(s) créé(s), ${r!.misAJour} mis à jour, ${r!.ignores} ligne(s) ignorée(s).\n'
            'Pensez à créer les classes et à affecter les établissements aux téléphones.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  Widget _colonnesWidget() {
    final entete = _entete == null ? null : _brut![_entete!];
    return Wrap(spacing: 10, runSpacing: 8, children: [
      for (var c = 0; c < _nombreColonnes; c++)
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<ChampEtablissement>(
            value: _colonnes[c] ?? ChampEtablissement.ignorer,
            isExpanded: true,
            decoration: InputDecoration(
                labelText: 'Colonne ${c + 1}${entete != null && c < entete.length ? ' « ${entete[c]} »' : ''}', isDense: true),
            items: [for (final x in ChampEtablissement.values) DropdownMenuItem(value: x, child: Text(x.libelle))],
            onChanged: (x) {
              setState(() => x == null || x == ChampEtablissement.ignorer ? _colonnes.remove(c) : _colonnes[c] = x);
              if (_colonnes.containsValue(ChampEtablissement.nom)) _analyser();
            },
          ),
        ),
    ]);
  }

  Widget _tableau() {
    final l = _lignes!;
    return DataTable(
      columnSpacing: 14,
      dataRowMaxHeight: 64,
      columns: const [
        DataColumn(label: Text('Ligne')),
        DataColumn(label: Text('Code')),
        DataColumn(label: Text('Nom')),
        DataColumn(label: Text('Type')),
        DataColumn(label: Text('Statut')),
        DataColumn(label: Text('Localité')),
        DataColumn(label: Text('Responsable')),
        DataColumn(label: Text('Action')),
        DataColumn(label: Text('Contrôles')),
      ],
      rows: [
        for (final x in l)
          DataRow(
            color: WidgetStatePropertyAll(x.action == ActionEtablissement.ignorer
                ? Colors.grey.shade200
                : x.bloquee
                    ? Colors.red.shade50
                    : x.avertissements.isNotEmpty
                        ? Colors.amber.shade50
                        : null),
            cells: [
              DataCell(Text('${x.numeroSource}')),
              DataCell(Text(x.code)),
              DataCell(SizedBox(width: 220, child: Text(x.nom))),
              DataCell(DropdownButton<TypeEtablissement>(
                value: x.type,
                hint: const Text('—'),
                items: [for (final t in TypeEtablissement.values) DropdownMenuItem(value: t, child: Text(t.libelle))],
                onChanged: (t) => setState(() => x.type = t),
              )),
              DataCell(DropdownButton<StatutEtablissement>(
                value: x.statut,
                hint: const Text('—'),
                items: [for (final t in StatutEtablissement.values) DropdownMenuItem(value: t, child: Text(t.libelle))],
                onChanged: (t) => setState(() => x.statut = t),
              )),
              DataCell(Text(x.localite ?? '')),
              DataCell(Text(x.responsable ?? '')),
              DataCell(DropdownButton<ActionEtablissement>(
                value: x.action,
                items: [
                  if (x.existantId == null)
                    const DropdownMenuItem(value: ActionEtablissement.creer, child: Text('Créer'))
                  else
                    const DropdownMenuItem(value: ActionEtablissement.mettreAJour, child: Text('Mettre à jour')),
                  const DropdownMenuItem(value: ActionEtablissement.ignorer, child: Text('Ignorer')),
                ],
                onChanged: (a) => setState(() => x.action = a ?? x.action),
              )),
              DataCell(SizedBox(
                width: 280,
                child: Text(
                  [
                    if (x.existantId != null) 'Connu : ${x.existantNom}',
                    ...x.erreurs,
                    ...x.avertissements,
                  ].join('\n'),
                  style: TextStyle(fontSize: 12, color: x.bloquee ? Colors.red.shade800 : null),
                ),
              )),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = _lignes == null ? null : bilanEtablissements(_lignes!);
    return Dialog(
      child: SizedBox(
        width: 1180,
        height: 760,
        child: Column(children: [
          ListTile(
            title: Text('Importer la liste des établissements', style: Theme.of(context).textTheme.titleLarge),
            subtitle: const Text('Fichier Excel (.xlsx) ou CSV avec au moins une colonne « Nom » ; colonnes possibles : code, '
                'type, statut, région, district sanitaire, localité, responsable, téléphone.'),
            trailing: IconButton(onPressed: () => Navigator.pop(context, false), icon: const Icon(Icons.close)),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                FilledButton.icon(
                    onPressed: _occupe ? null : _choisir, icon: const Icon(Icons.folder_open), label: const Text('Choisir le fichier')),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final chemin = await FilePicker.platform.saveFile(
                        dialogTitle: 'Enregistrer le modèle', fileName: 'modele_liste_etablissements.xlsx',
                        type: FileType.custom, allowedExtensions: const ['xlsx']);
                    if (chemin == null) return;
                    final f = chemin.toLowerCase().endsWith('.xlsx') ? chemin : '$chemin.xlsx';
                    await File(f).writeAsBytes(modeleListeEtablissements(), flush: true);
                    if (context.mounted) message(context, 'Modèle enregistré : $f');
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Modèle Excel'),
                ),
                const SizedBox(width: 12),
                if (_fichier != null) Expanded(child: Text(_fichier!, overflow: TextOverflow.ellipsis)),
              ]),
              if (_erreur != null)
                Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(padding: const EdgeInsets.all(12), child: Text(_erreur!))),
              if (_brut != null) ...[
                const SizedBox(height: 16),
                Text(_entete == null
                    ? 'Intitulés des colonnes non reconnus : indiquez au moins la colonne du nom.'
                    : 'Colonnes reconnues (ligne ${_entete! + 1}) : vérifiez-les.'),
                const SizedBox(height: 8),
                _colonnesWidget(),
              ],
              if (_lignes != null) ...[
                const SizedBox(height: 16),
                SingleChildScrollView(scrollDirection: Axis.horizontal, child: _tableau()),
              ],
            ]),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Text(b == null
                    ? ''
                    : '${b.aCreer} à créer · ${b.aMettreAJour} à mettre à jour · ${b.ignorees} ignorée(s)'
                        '${b.bloquees == 0 ? '' : ' · ${b.bloquees} en erreur (à ignorer ou corriger dans le fichier)'}'),
              ),
              FilledButton(
                onPressed: b != null && b.validable && !_occupe ? _valider : null,
                child: const Text('VALIDER L\'IMPORTATION'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
