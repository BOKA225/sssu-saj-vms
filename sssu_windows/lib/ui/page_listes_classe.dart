/// LISTES DE CLASSE par établissement : choix de l'établissement, puis de la
/// classe ; liste des élèves inscrits (identité, âge, téléphone du parent,
/// dernière visite) ; ouverture du dossier ; ajout d'un élève dans la
/// classe ; impression ou exportation d'une classe ou de toutes les classes
/// (PDF, Word, Excel d'une feuille par classe, réimportable).
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../donnees/requetes_poste.dart';
import '../rapports/service_rapports.dart';
import '../services.dart';
import 'commun.dart';
import 'dialogue_eleve.dart';
import 'fiche_dossier.dart';
import 'page_rapports.dart' show exporterRapport;

class PageListesClasse extends ConsumerStatefulWidget {
  const PageListesClasse({super.key});
  @override
  ConsumerState<PageListesClasse> createState() => _PageListesClasseState();
}

class _PageListesClasseState extends ConsumerState<PageListesClasse> {
  List<Annee> _annees = const [];
  Annee? _annee;
  List<LigneEtablissement> _etabs = const [];
  String? _etab;
  List<ListeDeClasse> _listes = const [];

  /// Classe affichée.
  String? _classe;
  String _filtre = '';
  bool _chargement = false;

  ServicesPoste get _s => ref.read(servicesProvider);
  Droits get _droits => ref.read(sessionProvider)!.droits;

  @override
  void initState() {
    super.initState();
    _chargerAnnees();
  }

  Future<void> _chargerAnnees() async {
    final annees = await _s.requetes.annees();
    final annee = annees.isEmpty ? null : annees.firstWhere((a) => a.active, orElse: () => annees.first);
    if (!mounted) return;
    setState(() {
      _annees = annees;
      _annee = annee;
    });
    await _chargerEtablissements();
  }

  Future<void> _chargerEtablissements() async {
    final etabs = _annee == null ? <LigneEtablissement>[] : await _s.requetes.etablissements(_annee!);
    if (!mounted) return;
    setState(() {
      _etabs = etabs;
      if (!etabs.any((e) => e.id == _etab)) {
        _etab = null;
        _listes = const [];
        _classe = null;
      }
    });
    if (_etab != null) await _chargerListes();
  }

  Future<void> _chargerListes() async {
    if (_etab == null || _annee == null) return;
    setState(() => _chargement = true);
    final listes = await _s.requetes.listesDeClasses(_etab!, _annee!);
    if (!mounted) return;
    setState(() {
      _listes = listes;
      _chargement = false;
      if (!listes.any((l) => l.classeId == _classe)) _classe = listes.isEmpty ? null : listes.first.classeId;
    });
  }

  ListeDeClasse? get _liste => _listes.where((l) => l.classeId == _classe).firstOrNull;
  String get _nomEtab => _etabs.where((e) => e.id == _etab).firstOrNull?.nom ?? '';

  List<EleveListe> _visibles(ListeDeClasse l) {
    final f = normaliserTexte(_filtre.trim());
    if (f.isEmpty) return l.eleves;
    return [
      for (final e in l.eleves)
        if (normaliserTexte('${e.nom} ${e.prenoms} ${e.prenoms} ${e.nom} ${e.matricule ?? ''}').contains(f)) e
    ];
  }

  Future<void> _ouvrir(String eleveId) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => FicheDossier(eleveId: eleveId)));
    _chargerListes();
  }

  /// Ajout d'un élève dans la classe affichée.
  Future<void> _ajouter() async {
    final l = _liste;
    if (l == null || _annee == null) return;
    final etab = _etabs.firstWhere((e) => e.id == _etab);
    final saisie = await showDialog<SaisieEleve>(
      context: context,
      builder: (_) => DialogueEleve(
        titre: 'Nouvel élève · ${l.libelle}',
        etablissements: [etab],
        classesDe: (id) => _s.requetes.classes(id, _annee!),
        etablissementId: etab.id,
        classeId: l.classeId,
      ),
    );
    if (saisie == null || !mounted) return;
    final existants = await _s.depot.transaction((tx) => tx.chercher('eleve', const {}));
    final semblable = eleveSemblable(saisie.identite, existants);
    if (semblable != null && mounted) {
      final ouvrir = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Cet élève semble déjà enregistré'),
          content: Text('${semblable.nom} ${semblable.prenoms}'
              '${semblable.matricule == null ? '' : ' · matricule ${semblable.matricule}'}'
              '${semblable.dateNaissance == null ? '' : ' · né(e) le ${dateFr(semblable.dateNaissance)}'}\n\n'
              'Ouvrez son dossier pour changer sa classe, plutôt que de créer un second dossier.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
            OutlinedButton(onPressed: () => Navigator.pop(d, false), child: const Text('Créer quand même')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Ouvrir son dossier')),
          ],
        ),
      );
      if (ouvrir == null || !mounted) return;
      if (ouvrir) return _ouvrir(semblable.id!);
    }
    if (!mounted) return;
    await executer(context, () => _s.gestion.creerEleve(_droits, identite: saisie.identite, classeId: saisie.classeId!),
        succes: 'Élève ajouté à la classe.');
    _chargerListes();
  }

  /// Impression ou exportation : classe affichée ou toutes les classes.
  Future<void> _exporter({required bool toutes, required FormatRapport format}) async {
    final classes = toutes ? _listes : [if (_liste != null) _liste!];
    if (classes.isEmpty || _annee == null) return;
    if (format == FormatRapport.excel) return _exporterClasseur(classes);
    final entete = await _s.rapports.entete();
    if (!mounted) return;
    await exporterRapport(
      context,
      _s,
      _droits,
      () => rapportListesDeClasse(
        etablissement: _nomEtab,
        annee: _annee!.libelle,
        classes: classes,
        entete: entete,
        acteur: _droits,
        genereLe: DateTime.now(),
      ),
      format,
      table: 'etablissement',
      id: _etab,
    );
  }

  /// Excel : une feuille par classe, aux colonnes du modèle d'importation.
  Future<void> _exporterClasseur(List<ListeDeClasse> classes) async {
    if (!peutExporterListesDeClasse(_droits)) {
      message(context, 'Vous n\'êtes pas autorisé à exporter les listes de classe.');
      return;
    }
    final base = 'listes_classe_${_nomEtab}_${classes.length == 1 ? classes.single.libelle : _annee!.libelle}'
        .replaceAll(RegExp(r'[^A-Za-z0-9À-ÿ]+'), '_');
    final chemin = await FilePicker.platform.saveFile(
      dialogTitle: 'Enregistrer les listes de classe (Excel)',
      fileName: '$base.xlsx',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (chemin == null) return;
    final complet = chemin.toLowerCase().endsWith('.xlsx') ? chemin : '$chemin.xlsx';
    try {
      await File(complet).writeAsBytes(classeurListesDeClasse(classes), flush: true);
      await _s.gestion.noterExport(_droits, classes.length == 1 ? 'Liste de classe' : 'Listes de classe',
          table: 'etablissement', id: _etab, detail: {'format': 'xlsx', 'classes': classes.length});
      if (mounted) message(context, 'Listes enregistrées : $complet');
    } catch (e) {
      if (mounted) message(context, 'Échec de l\'enregistrement : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _listes.fold<int>(0, (s, l) => s + l.eleves.length);
    final peutExporter = peutExporterListesDeClasse(_droits);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Listes de classe', style: Theme.of(context).textTheme.headlineSmall),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              value: _annee?.id,
              decoration: const InputDecoration(labelText: 'Année scolaire'),
              items: [
                for (final a in _annees) DropdownMenuItem(value: a.id, child: Text('${a.libelle}${a.active ? ' (active)' : ''}'))
              ],
              onChanged: (id) {
                setState(() => _annee = _annees.firstWhere((a) => a.id == id));
                _chargerEtablissements();
              },
            ),
          ),
          DropdownMenu<String>(
            key: ValueKey('${_annee?.id}-${_etabs.length}'),
            width: 380,
            initialSelection: _etab,
            enableFilter: true,
            requestFocusOnTap: true,
            menuHeight: 400,
            label: const Text('Établissement'),
            hintText: 'Tapez le nom de l\'établissement',
            dropdownMenuEntries: [
              for (final e in _etabs) DropdownMenuEntry(value: e.id, label: e.nom),
            ],
            onSelected: (id) {
              if (id == null) return;
              setState(() {
                _etab = id;
                _classe = null;
                _filtre = '';
              });
              _chargerListes();
            },
          ),
          if (_etab != null && peutExporter)
            MenuAnchor(
              builder: (context, menu, _) => FilledButton.tonalIcon(
                onPressed: _listes.isEmpty ? null : () => menu.isOpen ? menu.close() : menu.open(),
                icon: const Icon(Icons.print),
                label: const Text('Imprimer / exporter'),
              ),
              menuChildren: [
                for (final toutes in [false, true])
                  SubmenuButton(
                    menuChildren: [
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.picture_as_pdf),
                        onPressed: () => _exporter(toutes: toutes, format: FormatRapport.pdf),
                        child: const Text('PDF (à imprimer)'),
                      ),
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.description),
                        onPressed: () => _exporter(toutes: toutes, format: FormatRapport.word),
                        child: const Text('Word'),
                      ),
                      MenuItemButton(
                        leadingIcon: const Icon(Icons.table_chart),
                        onPressed: () => _exporter(toutes: toutes, format: FormatRapport.excel),
                        child: Text(toutes ? 'Excel (une feuille par classe)' : 'Excel'),
                      ),
                    ],
                    child: Text(toutes
                        ? 'Toutes les classes (${_listes.length})'
                        : 'Classe affichée${_liste == null ? '' : ' (${_liste!.libelle})'}'),
                  ),
              ],
            ),
        ]),
      ),
      if (_etab != null && !_chargement)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('$_nomEtab · ${_listes.length} classe${_listes.length > 1 ? 's' : ''} · $total élèves inscrits'),
        ),
      const Divider(),
      Expanded(
        child: _etab == null
            ? const Center(child: Text('Choisissez un établissement pour voir ses listes de classe.'))
            : _chargement
                ? const Center(child: CircularProgressIndicator())
                : _listes.isEmpty
                    ? const Center(child: Text('Aucune classe pour cette année scolaire : créez-les dans Établissements.'))
                    : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 280, child: _colonneClasses()),
                        const VerticalDivider(width: 1),
                        Expanded(child: _liste == null ? const SizedBox.shrink() : _tableauClasse(_liste!)),
                      ]),
      ),
    ]);
  }

  Widget _colonneClasses() => ListView(padding: const EdgeInsets.all(8), children: [
        for (final l in _listes)
          Card(
            color: l.classeId == _classe ? Theme.of(context).colorScheme.primaryContainer : null,
            child: ListTile(
              dense: true,
              title: Text(l.libelle, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(l.effectif),
              onTap: () => setState(() {
                _classe = l.classeId;
                _filtre = '';
              }),
            ),
          ),
      ]);

  Widget _tableauClasse(ListeDeClasse l) {
    final visibles = _visibles(l);
    final maintenant = DateTime.now();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('${l.libelle} — ${l.effectif}', style: Theme.of(context).textTheme.titleLarge),
        SizedBox(
          width: 260,
          child: TextField(
            key: ValueKey(l.classeId),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nom, prénoms ou matricule'),
            onChanged: (t) => setState(() => _filtre = t),
          ),
        ),
        if (_droits.peutGererEleves)
          OutlinedButton.icon(onPressed: _ajouter, icon: const Icon(Icons.person_add), label: const Text('Ajouter un élève')),
      ]),
      const SizedBox(height: 8),
      if (l.eleves.isEmpty)
        const Text('Aucun élève inscrit dans cette classe : importez sa liste (Importer une liste) ou ajoutez les élèves.'),
      if (l.eleves.isNotEmpty)
        DataTable(
          showCheckboxColumn: false,
          columns: const [
            DataColumn(label: Text('N°'), numeric: true),
            DataColumn(label: Text('Matricule')),
            DataColumn(label: Text('Nom et prénoms')),
            DataColumn(label: Text('Sexe')),
            DataColumn(label: Text('Né(e) le')),
            DataColumn(label: Text('Âge'), numeric: true),
            DataColumn(label: Text('Téléphone du parent')),
            DataColumn(label: Text('Dernière visite')),
          ],
          rows: [
            for (final e in visibles)
              DataRow(
                onSelectChanged: (_) => _ouvrir(e.id),
                cells: [
                  DataCell(Text('${l.eleves.indexOf(e) + 1}')),
                  DataCell(Text(e.matricule ?? '—')),
                  DataCell(Text(e.nomComplet)),
                  DataCell(Text(e.sexe)),
                  DataCell(Text(e.dateNaissance == null ? '—' : dateFr(e.dateNaissance))),
                  DataCell(Text(e.dateNaissance == null
                      ? '—'
                      : '${calculerAge(lireDate(e.dateNaissance!), maintenant.toUtc()).annees}')),
                  DataCell(Text(e.telephone ?? '—')),
                  DataCell(Text(e.derniereVisite == null
                      ? 'Non examiné(e)'
                      : '${dateFr(e.derniereVisite)}${e.statutVisite == 'valide' ? ' · validée' : ''}')),
                ],
              ),
          ],
        ),
    ]);
  }
}
