/// Élèves : recherche par établissement, classe, nom ou matricule ; ouverture
/// du dossier.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../donnees/requetes_poste.dart';
import '../services.dart';
import 'commun.dart';
import 'fiche_dossier.dart';

class PageEleves extends ConsumerStatefulWidget {
  const PageEleves({super.key});
  @override
  ConsumerState<PageEleves> createState() => _PageElevesState();
}

class _PageElevesState extends ConsumerState<PageEleves> {
  Annee? _annee;
  List<LigneEtablissement> _etabs = const [];
  String? _etab;
  List<LigneClasse> _classes = const [];
  String? _classe;
  String _texte = '';
  bool _nonExamines = false;
  List<LigneEleve> _eleves = const [];
  Timer? _attente;

  RequetesPoste get _r => ref.read(servicesProvider).requetes;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _attente?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final a = await _r.anneeCourante();
    if (a == null) return;
    final e = await _r.etablissements(a);
    if (!mounted) return;
    setState(() {
      _annee = a;
      _etabs = e;
    });
    await _chercher();
  }

  Future<void> _choisirEtab(String? id) async {
    setState(() {
      _etab = id;
      _classe = null;
      _classes = const [];
    });
    if (id != null) {
      final c = await _r.classes(id, _annee!);
      if (mounted) setState(() => _classes = c);
    }
    await _chercher();
  }

  Future<void> _chercher() async {
    if (_annee == null) return;
    if (_etab == null && _classe == null && _texte.trim().length < 2) {
      setState(() => _eleves = const []);
      return;
    }
    final l = await _r.eleves(_annee!, etablissementId: _etab, classeId: _classe, texte: _texte);
    if (mounted) setState(() => _eleves = l);
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _nonExamines ? _eleves.where((e) => e.statutVisite == null || e.statutVisite == 'ebauche').toList() : _eleves;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Élèves${_annee == null ? '' : ' · ${_annee!.libelle}'}', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 280,
            child: DropdownButtonFormField<String?>(
              value: _etab,
              decoration: const InputDecoration(labelText: 'Établissement'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tous')),
                for (final e in _etabs) DropdownMenuItem(value: e.id, child: Text(e.nom, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _choisirEtab,
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String?>(
              value: _classe,
              decoration: const InputDecoration(labelText: 'Classe'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Toutes')),
                for (final c in _classes) DropdownMenuItem(value: c.id, child: Text(c.libelle)),
              ],
              onChanged: (c) {
                setState(() => _classe = c);
                _chercher();
              },
            ),
          ),
          SizedBox(
            width: 300,
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Nom, prénoms ou matricule'),
              onChanged: (t) {
                _texte = t;
                _attente?.cancel();
                _attente = Timer(const Duration(milliseconds: 300), _chercher);
              },
            ),
          ),
          FilterChip(
            label: const Text('Non examinés'),
            selected: _nonExamines,
            onSelected: (v) => setState(() => _nonExamines = v),
          ),
          Text('${visibles.length} élève(s)'),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: visibles.isEmpty
              ? const Center(child: Text('Choisissez un établissement ou saisissez au moins deux caractères.'))
              : SingleChildScrollView(
                  child: DataTable(
                    showCheckboxColumn: false,
                    columns: const [
                      DataColumn(label: Text('Matricule')),
                      DataColumn(label: Text('Nom et prénoms')),
                      DataColumn(label: Text('Sexe')),
                      DataColumn(label: Text('Né(e) le')),
                      DataColumn(label: Text('Classe')),
                      DataColumn(label: Text('Établissement')),
                      DataColumn(label: Text('Dernière visite')),
                    ],
                    rows: [
                      for (final e in visibles)
                        DataRow(
                          onSelectChanged: (_) async {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => FicheDossier(eleveId: e.id)));
                            _chercher();
                          },
                          cells: [
                            DataCell(Text(e.matricule ?? '—')),
                            DataCell(Text('${e.nom} ${e.prenoms}')),
                            DataCell(Text(e.sexe)),
                            DataCell(Text(dateFr(e.dateNaissance))),
                            DataCell(Text(e.classe ?? 'non inscrit')),
                            DataCell(Text(e.etablissement ?? '')),
                            DataCell(Text(e.derniereVisite == null
                                ? 'Non examiné'
                                : '${dateFr(e.derniereVisite)} · ${libelleStatutVisite(e.statutVisite!)}')),
                          ],
                        ),
                    ],
                  ),
                ),
        ),
      ]),
    );
  }
}
