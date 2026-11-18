/// Liste des vaccins (PEV et hors PEV, obligatoires ou recommandés) :
/// consultation, ajout et modification (droit `parametres.modifier`). La
/// liste est envoyée aux téléphones à la synchronisation suivante.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../services.dart';
import 'commun.dart';

/// Ouvre la liste des vaccins ; retourne `true` si elle a changé.
Future<bool> gererVaccins(BuildContext context) async =>
    await showDialog<bool>(context: context, builder: (_) => const _DialogueVaccins()) ?? false;

class _DialogueVaccins extends ConsumerStatefulWidget {
  const _DialogueVaccins();
  @override
  ConsumerState<_DialogueVaccins> createState() => _DialogueVaccinsState();
}

class _DialogueVaccinsState extends ConsumerState<_DialogueVaccins> {
  List<Vaccin>? _vaccins;
  bool _modifie = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final v = await ref.read(servicesProvider).requetes.vaccins();
    if (mounted) setState(() => _vaccins = v);
  }

  Future<void> _editer([Vaccin? v]) async {
    final saisi = await showDialog<Vaccin>(context: context, builder: (_) => _DialogueVaccin(actuel: v));
    if (saisi == null || !mounted) return;
    final s = ref.read(servicesProvider);
    final droits = ref.read(sessionProvider)!.droits;
    final ok = await executer(context, () async {
      if (v == null) {
        await s.gestion.creerVaccin(droits, saisi);
      } else {
        await s.gestion.modifierVaccin(droits, v.id, saisi);
      }
    }, succes: v == null ? 'Vaccin ajouté.' : 'Vaccin modifié.');
    if (ok) {
      _modifie = true;
      await _charger();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _vaccins;
    final peut = ref.read(sessionProvider)!.droits.peut(Permission.parametresModifier);
    return AlertDialog(
      title: const Text('Vaccins PEV et hors PEV'),
      content: SizedBox(
        width: 980,
        height: 560,
        child: l == null
            ? const Center(child: CircularProgressIndicator())
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Les vaccins actifs de la liste du préscolaire sont proposés sur les téléphones et dans la '
                    'liste de vaccination du préscolaire. Un vaccin désactivé n\'est plus proposé ; les vaccins déjà '
                    'notés sont conservés. Le vaccin HPV (code HPV) est vérifié lors de la visite des filles de 9 à 14 ans.'),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 18,
                      dataRowMinHeight: 32,
                      dataRowMaxHeight: 48,
                      columns: const [
                        DataColumn(label: Text('Code')),
                        DataColumn(label: Text('Vaccin')),
                        DataColumn(label: Text('Programme')),
                        DataColumn(label: Text('Statut')),
                        DataColumn(label: Text('Âge ou cible')),
                        DataColumn(label: Text('Préscolaire')),
                        DataColumn(label: Text('Actif')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final v in l)
                          DataRow(
                            color: v.actif ? null : const WidgetStatePropertyAll(Color(0xFFF2F2F2)),
                            cells: [
                              DataCell(Text(v.code, style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 260),
                                  child: Text(v.libelle, overflow: TextOverflow.ellipsis))),
                              DataCell(Text(v.programme.libelle)),
                              DataCell(Text(v.statut.libelle)),
                              DataCell(ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 220),
                                  child: Text(v.cible ?? '', overflow: TextOverflow.ellipsis))),
                              DataCell(Icon(v.prescolaire ? Icons.check : Icons.remove, size: 18)),
                              DataCell(Icon(v.actif ? Icons.check_circle : Icons.block,
                                  size: 18, color: v.actif ? Colors.green.shade700 : Colors.grey)),
                              DataCell(peut
                                  ? IconButton(
                                      tooltip: 'Modifier', icon: const Icon(Icons.edit, size: 18), onPressed: () => _editer(v))
                                  : const SizedBox.shrink()),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ]),
      ),
      actions: [
        if (peut) OutlinedButton.icon(onPressed: () => _editer(), icon: const Icon(Icons.add), label: const Text('Ajouter un vaccin')),
        FilledButton(onPressed: () => Navigator.pop(context, _modifie), child: const Text('Fermer')),
      ],
    );
  }
}

/// Saisie d'un vaccin (ajout ou modification ; le code ne change pas).
class _DialogueVaccin extends StatefulWidget {
  final Vaccin? actuel;
  const _DialogueVaccin({this.actuel});
  @override
  State<_DialogueVaccin> createState() => _DialogueVaccinState();
}

class _DialogueVaccinState extends State<_DialogueVaccin> {
  late final _code = TextEditingController(text: widget.actuel?.code ?? '');
  late final _libelle = TextEditingController(text: widget.actuel?.libelle ?? '');
  late final _cible = TextEditingController(text: widget.actuel?.cible ?? '');
  late final _ordre = TextEditingController(text: widget.actuel == null ? '' : '${widget.actuel!.ordre}');
  late ProgrammeVaccin _programme = widget.actuel?.programme ?? ProgrammeVaccin.pev;
  late StatutVaccin _statut = widget.actuel?.statut ?? StatutVaccin.obligatoire;
  late bool _prescolaire = widget.actuel?.prescolaire ?? true;
  late bool _actif = widget.actuel?.actif ?? true;
  String? _erreur;

  @override
  void dispose() {
    for (final c in [_code, _libelle, _cible, _ordre]) {
      c.dispose();
    }
    super.dispose();
  }

  void _valider() {
    if (_libelle.text.trim().isEmpty) {
      setState(() => _erreur = 'Nom du vaccin obligatoire.');
      return;
    }
    final ordre = int.tryParse(_ordre.text.trim());
    Navigator.pop(
      context,
      Vaccin(
        id: widget.actuel?.id ?? '',
        code: widget.actuel?.code ?? _code.text.trim(),
        libelle: _libelle.text.trim(),
        programme: _programme,
        statut: _statut,
        cible: _cible.text.trim().isEmpty ? null : _cible.text.trim(),
        prescolaire: _prescolaire,
        actif: _actif,
        ordre: ordre ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.actuel == null ? 'Nouveau vaccin' : 'Modifier ${widget.actuel!.code}'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _libelle,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom du vaccin (ex. : Fièvre jaune (VAA))'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              enabled: widget.actuel == null,
              decoration: InputDecoration(
                  labelText: 'Code court (colonne des listes)',
                  helperText: widget.actuel == null ? 'Facultatif : tiré du nom s\'il est vide' : 'Le code ne change pas'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const SizedBox(width: 90, child: Text('Programme')),
              SegmentedButton<ProgrammeVaccin>(
                segments: [for (final p in ProgrammeVaccin.values) ButtonSegment(value: p, label: Text(p.libelle))],
                selected: {_programme},
                onSelectionChanged: (s) => setState(() => _programme = s.first),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const SizedBox(width: 90, child: Text('Statut')),
              SegmentedButton<StatutVaccin>(
                segments: [for (final s in StatutVaccin.values) ButtonSegment(value: s, label: Text(s.libelle))],
                selected: {_statut},
                onSelectionChanged: (s) => setState(() => _statut = s.first),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _cible,
              decoration: const InputDecoration(labelText: 'Âge ou population cible (ex. : 9 mois, À la naissance)'),
            ),
            TextField(
              controller: _ordre,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Ordre dans la liste (facultatif)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dans la liste de vaccination du préscolaire'),
              value: _prescolaire,
              onChanged: (v) => setState(() => _prescolaire = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Actif (proposé sur les téléphones)'),
              value: _actif,
              onChanged: (v) => setState(() => _actif = v),
            ),
            if (_erreur != null) Text(_erreur!, style: const TextStyle(color: Colors.red)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: _valider, child: const Text('Enregistrer')),
        ],
      );
}
