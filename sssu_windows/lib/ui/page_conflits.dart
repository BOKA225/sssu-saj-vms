/// Conflits de synchronisation à examiner par le Médecin-Chef : comparaison
/// champ par champ de la version du poste central et de celle du téléphone,
/// puis décision. La décision est transmise aux téléphones à leur
/// synchronisation suivante et remplace leur version en conflit.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../services.dart';
import 'commun.dart';

const Map<String, String> _libellesTypes = {
  TypesConflit.modificationConcurrente: 'Modifications concurrentes',
  TypesConflit.suppressionModification: 'Suppression et modification',
  TypesConflit.doublonEleve: 'Doublon probable d\'élève',
  TypesConflit.doublonVisite: 'Deux visites le même jour',
  TypesConflit.unicite: 'Enregistrement déjà existant',
};

const Map<String, String> _explications = {
  TypesConflit.modificationConcurrente:
      'Le même enregistrement a été modifié sur le poste central et sur un téléphone depuis leur dernière '
          'synchronisation. Choisissez la version à garder, ou composez-en une champ par champ.',
  TypesConflit.suppressionModification:
      'L\'enregistrement a été supprimé d\'un côté et modifié de l\'autre.',
  TypesConflit.doublonEleve:
      'Un téléphone a créé un dossier dont le matricule existe déjà. Les deux dossiers ont été conservés. '
          'S\'il s\'agit du même élève, fusionnez-les : visites, antécédents et photos sont regroupés.',
  TypesConflit.doublonVisite:
      'Deux visites ont été enregistrées pour le même élève à la même date (souvent deux agents sur le même élève). '
          'Les deux ont été conservées.',
  TypesConflit.unicite:
      'Le téléphone a envoyé un enregistrement qui existe déjà (par exemple une seconde inscription pour la même '
          'année). Sa version n\'a pas été enregistrée sur le poste. Après la clôture, l\'agent peut l\'abandonner '
          'sur son téléphone (écran « Éléments à vérifier ») ; une modification d\'un enregistrement existant est '
          'remplacée par la version du poste à la synchronisation suivante.',
};

/// Champs techniques ou secrets jamais affichés.
bool _masque(String champ) => champ.startsWith('hash_') || champ == 'chemin_chiffre';

class PageConflits extends ConsumerStatefulWidget {
  const PageConflits({super.key});
  @override
  ConsumerState<PageConflits> createState() => _PageConflitsState();
}

class _PageConflitsState extends ConsumerState<PageConflits> {
  List<Enregistrement>? _conflits;
  Map<String, String> _appareils = const {};
  Enregistrement? _choisi;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final s = ref.read(servicesProvider);
    final l = (await s.conflits.ouverts())..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final appareils = await s.depot.transaction((tx) => tx.chercher('appareil', const {}));
    if (!mounted) return;
    setState(() {
      _conflits = l;
      _appareils = {for (final a in appareils) a.id: '${a.donnees['nom']}'};
      _choisi = _choisi == null ? null : l.where((c) => c.id == _choisi!.id).firstOrNull;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = _conflits;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 380,
        child: Column(children: [
          ListTile(
            title: Text('Conflits à examiner (${l?.length ?? '…'})', style: Theme.of(context).textTheme.titleMedium),
            trailing: IconButton(onPressed: _charger, icon: const Icon(Icons.refresh), tooltip: 'Actualiser'),
          ),
          const Divider(height: 1),
          Expanded(
            child: l == null
                ? const Center(child: CircularProgressIndicator())
                : l.isEmpty
                    ? const Padding(padding: EdgeInsets.all(24), child: Text('Aucun conflit en attente.'))
                    : ListView.builder(
                        itemCount: l.length,
                        itemBuilder: (c, i) {
                          final x = l[i];
                          return ListTile(
                            selected: _choisi?.id == x.id,
                            leading: const Icon(Icons.report_problem, color: Colors.orange),
                            title: Text(_libellesTypes[x.donnees['type']] ?? '${x.donnees['type']}'),
                            subtitle: Text('${x.donnees['table_cible']} · '
                                '${_appareils[x.donnees['appareil_id']] ?? 'téléphone inconnu'} · ${dateHeureFr(x.createdAt)}'),
                            onTap: () => setState(() => _choisi = x),
                          );
                        },
                      ),
          ),
        ]),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: _choisi == null
            ? const Center(child: Text('Sélectionnez un conflit.'))
            : _DetailConflit(
                key: ValueKey(_choisi!.id),
                conflit: _choisi!,
                appareil: _appareils[_choisi!.donnees['appareil_id']],
                onTraite: () async {
                  setState(() => _choisi = null);
                  await _charger();
                },
              ),
      ),
    ]);
  }
}

class _DetailConflit extends ConsumerStatefulWidget {
  final Enregistrement conflit;
  final String? appareil;
  final Future<void> Function() onTraite;
  const _DetailConflit({super.key, required this.conflit, required this.appareil, required this.onTraite});
  @override
  ConsumerState<_DetailConflit> createState() => _DetailConflitState();
}

class _DetailConflitState extends ConsumerState<_DetailConflit> {
  late final Enregistrement? _serveur;
  late final Enregistrement _appareil;
  Enregistrement? _actuel;

  /// Fusion : pour chaque champ différent, `true` = valeur du téléphone.
  final Map<String, bool> _depuisTelephone = {};

  String get _type => widget.conflit.donnees['type']! as String;

  static Enregistrement? _lireVersion(Object? v) {
    if (v == null) return null;
    final m = v is String ? jsonDecode(v) : v;
    return Enregistrement.depuisJson(Map<String, Object?>.from(m as Map));
  }

  @override
  void initState() {
    super.initState();
    _serveur = _lireVersion(widget.conflit.donnees['version_serveur']);
    _appareil = _lireVersion(widget.conflit.donnees['version_appareil'])!;
    _chargerActuel();
  }

  /// Version actuelle sur le poste (elle a pu changer depuis la détection).
  Future<void> _chargerActuel() async {
    final s = ref.read(servicesProvider);
    final id = _serveur?.id ?? _appareil.id;
    final e = await s.depot.transaction((tx) => tx.lire(_serveur?.table ?? _appareil.table, id));
    if (mounted) setState(() => _actuel = e);
  }

  Enregistrement? get _reference => _actuel ?? _serveur;

  List<String> get _champs {
    final cles = <String>{...?_reference?.donnees.keys, ..._appareil.donnees.keys}..removeWhere(_masque);
    return cles.toList()..sort();
  }

  static String _valeur(Object? v) {
    if (v == null) return '—';
    if (v is bool) return v ? 'oui' : 'non';
    if (v is Map || v is List) return jsonEncode(v);
    return '$v';
  }

  bool _different(String champ) => _valeur(_reference?.donnees[champ]) != _valeur(_appareil.donnees[champ]);

  Future<void> _agir(String titre, String texte, Future<void> Function(Droits d) action) async {
    if (!await confirmer(context, titre, texte)) return;
    if (!mounted) return;
    final d = ref.read(sessionProvider)!.droits;
    final ok = await executer(context, () => action(d), succes: 'Décision enregistrée. Elle sera transmise aux téléphones.');
    if (ok) await widget.onTraite();
  }

  List<Widget> _actions() {
    final conflits = ref.read(servicesProvider).conflits;
    final id = widget.conflit.id;
    switch (_type) {
      case TypesConflit.modificationConcurrente:
      case TypesConflit.suppressionModification:
        final differents = _champs.where(_different).toList();
        return [
          OutlinedButton(
            onPressed: () => _agir('Garder la version du poste central', 'La version du téléphone sera remplacée.',
                (d) => conflits.resoudre(id, choix: ChoixConflit.serveur, acteur: d)),
            child: const Text('Garder la version du poste central'),
          ),
          OutlinedButton(
            onPressed: () => _agir('Retenir la version du téléphone',
                'La version du téléphone devient la version de référence${_appareil.supprime ? ' (suppression)' : ''}.',
                (d) => conflits.resoudre(id, choix: ChoixConflit.appareil, acteur: d)),
            child: Text(_appareil.supprime ? 'Accepter la suppression du téléphone' : 'Retenir la version du téléphone'),
          ),
          if (differents.isNotEmpty && !_appareil.supprime && _reference != null && !_reference!.supprime)
            FilledButton(
              onPressed: () => _agir(
                  'Enregistrer la version composée',
                  'Champs repris du téléphone : '
                      '${differents.where((c) => _depuisTelephone[c] == true).join(', ').ifEmpty('aucun')}.',
                  (d) => conflits.resoudre(id, choix: ChoixConflit.fusion, acteur: d, donneesFusion: {
                        for (final c in differents)
                          if (_depuisTelephone[c] == true) c: _appareil.donnees[c],
                      })),
              child: const Text('Enregistrer la version composée'),
            ),
        ];
      case TypesConflit.doublonEleve:
        final existant = _serveur;
        return [
          if (existant != null) ...[
            FilledButton(
              onPressed: () => _agir(
                  'Fusionner les dossiers',
                  'Le dossier créé par le téléphone est fusionné dans le dossier existant, puis archivé. '
                      'Les informations manquantes du dossier existant sont complétées.',
                  (d) => conflits.fusionnerEleves(garderId: existant.id, absorberId: _appareil.id, acteur: d)),
              child: const Text('Même élève : fusionner dans le dossier existant'),
            ),
            OutlinedButton(
              onPressed: () => _agir(
                  'Fusionner dans le nouveau dossier',
                  'Le dossier existant est fusionné dans celui créé par le téléphone, puis archivé.',
                  (d) => conflits.fusionnerEleves(garderId: _appareil.id, absorberId: existant.id, acteur: d)),
              child: const Text('Même élève : garder le nouveau dossier'),
            ),
          ],
          OutlinedButton(
            onPressed: () => _agir('Élèves différents', 'Les deux dossiers sont conservés (vérifiez le matricule saisi).',
                (d) => conflits.fermer(id, acteur: d)),
            child: const Text('Élèves différents : garder les deux'),
          ),
        ];
      case TypesConflit.doublonVisite:
        final existante = _serveur;
        return [
          OutlinedButton(
            onPressed: () => _agir('Archiver la visite du téléphone',
                'La visite reçue du téléphone et ses éléments sont archivés.',
                (d) => conflits.archiverVisite(id, _appareil.id, acteur: d)),
            child: const Text('Archiver la visite du téléphone'),
          ),
          if (existante != null)
            OutlinedButton(
              onPressed: () => _agir('Archiver la visite déjà enregistrée',
                  'La visite enregistrée auparavant et ses éléments sont archivés.',
                  (d) => conflits.archiverVisite(id, existante.id, acteur: d)),
              child: const Text('Archiver la visite déjà enregistrée'),
            ),
          OutlinedButton(
            onPressed: () => _agir('Garder les deux visites', 'Les deux visites sont conservées.',
                (d) => conflits.fermer(id, acteur: d)),
            child: const Text('Garder les deux'),
          ),
        ];
      default:
        return [
          FilledButton(
            onPressed: () => _agir('Clore le conflit', 'La version du poste central est conservée.',
                (d) => conflits.fermer(id, acteur: d)),
            child: const Text('Clore : garder la version du poste central'),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final fusion = _type == TypesConflit.modificationConcurrente;
    final ref_ = _reference;
    final couleurDiff = Colors.amber.shade100;
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text(_libellesTypes[_type] ?? _type, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      Text('Table : ${widget.conflit.donnees['table_cible']} · téléphone : ${widget.appareil ?? 'inconnu'} · '
          'détecté le ${dateHeureFr(widget.conflit.createdAt)}'),
      const SizedBox(height: 12),
      Text(_explications[_type] ?? ''),
      const SizedBox(height: 16),
      DataTable(
        headingRowColor: WidgetStatePropertyAll(Theme.of(context).colorScheme.surfaceContainerHighest),
        columns: [
          const DataColumn(label: Text('Champ')),
          DataColumn(
              label: Text(_type == TypesConflit.doublonEleve || _type == TypesConflit.doublonVisite
                  ? 'Déjà enregistré'
                  : 'Poste central${ref_?.supprime == true ? ' (supprimé)' : ''}')),
          DataColumn(label: Text('Téléphone${_appareil.supprime ? ' (supprimé)' : ''}')),
          if (fusion) const DataColumn(label: Text('Version composée')),
        ],
        rows: [
          for (final c in _champs)
            DataRow(
              color: _different(c) ? WidgetStatePropertyAll(couleurDiff) : null,
              cells: [
                DataCell(Text(c)),
                DataCell(SizedBox(width: 260, child: Text(_valeur(ref_?.donnees[c])))),
                DataCell(SizedBox(width: 260, child: Text(_valeur(_appareil.donnees[c])))),
                if (fusion)
                  DataCell(_different(c)
                      ? SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('Poste')),
                            ButtonSegment(value: true, label: Text('Téléphone')),
                          ],
                          selected: {_depuisTelephone[c] ?? false},
                          onSelectionChanged: (s) => setState(() => _depuisTelephone[c] = s.first),
                        )
                      : const Text('=')),
              ],
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text('Version du téléphone saisie le ${dateHeureFr(_appareil.updatedAt)}'
          '${ref_ == null ? '' : ' · version du poste du ${dateHeureFr(ref_.updatedAt)}'}'),
      const SizedBox(height: 24),
      Wrap(spacing: 12, runSpacing: 12, children: _actions()),
    ]);
  }
}

extension on String {
  String ifEmpty(String autre) => isEmpty ? autre : this;
}
