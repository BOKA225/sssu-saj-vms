/// Journal des synchronisations et journal d'audit (traçabilité).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services.dart';
import 'commun.dart';

class PageSynchronisations extends ConsumerStatefulWidget {
  const PageSynchronisations({super.key});
  @override
  ConsumerState<PageSynchronisations> createState() => _PageSynchronisationsState();
}

class _PageSynchronisationsState extends ConsumerState<PageSynchronisations> {
  List<Map<String, dynamic>> _lignes = const [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final l = await ref.read(servicesProvider).requetes.journalSynchronisations();
    if (mounted) setState(() => _lignes = l);
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Text('Synchronisations reçues', style: Theme.of(context).textTheme.headlineSmall),
          const Spacer(),
          IconButton(onPressed: _charger, icon: const Icon(Icons.refresh), tooltip: 'Actualiser'),
        ]),
        DataTable(
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Téléphone')),
            DataColumn(label: Text('Agent')),
            DataColumn(label: Text('Canal')),
            DataColumn(label: Text('Reçus'), numeric: true),
            DataColumn(label: Text('Refus / conflits'), numeric: true),
            DataColumn(label: Text('Détail')),
          ],
          rows: [
            for (final l in _lignes)
              DataRow(cells: [
                DataCell(Text(dateHeureFr(l['debut']))),
                DataCell(Text('${l['appareil']}')),
                DataCell(Text('${l['utilisateur'] ?? ''}')),
                DataCell(Text(l['canal'] == 'wifi' ? 'Wi-Fi local' : 'Internet')),
                DataCell(Text('${l['envoyes']}')),
                DataCell(Text('${l['erreurs']}', style: TextStyle(color: (l['erreurs'] as int) > 0 ? Colors.red : null))),
                DataCell(SizedBox(
                  width: 360,
                  child: Text(
                    ((l['detail'] as Map?)?['refus'] as List?)?.join(' · ') ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
              ]),
          ],
        ),
      ]);
}

class PageJournal extends ConsumerStatefulWidget {
  const PageJournal({super.key});
  @override
  ConsumerState<PageJournal> createState() => _PageJournalState();
}

class _PageJournalState extends ConsumerState<PageJournal> {
  List<Map<String, dynamic>> _lignes = const [];
  String? _action;

  static const _actions = {
    'connexion': 'Connexions',
    'echec_connexion': 'Échecs de connexion',
    'consultation': 'Consultations',
    'telechargement': 'Téléchargements',
    'creation': 'Créations',
    'modification': 'Modifications',
    'suppression': 'Suppressions / archivages',
    'export': 'Exports',
  };

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final l = await ref.read(servicesProvider).requetes.journalAudit(action: _action);
    if (mounted) setState(() => _lignes = l);
  }

  String _resume(Object? avant, Object? apres) {
    String j(Object? x) => x == null ? '' : (x is String ? x : jsonEncode(x));
    final a = j(avant), b = j(apres);
    if (a.isEmpty) return b;
    return '$a → $b';
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Text('Journal d\'audit', style: Theme.of(context).textTheme.headlineSmall),
          const Spacer(),
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String?>(
              value: _action,
              decoration: const InputDecoration(labelText: 'Type d\'action'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Toutes')),
                for (final e in _actions.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (a) {
                _action = a;
                _charger();
              },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        DataTable(
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Utilisateur')),
            DataColumn(label: Text('Action')),
            DataColumn(label: Text('Objet')),
            DataColumn(label: Text('Détail')),
          ],
          rows: [
            for (final l in _lignes)
              DataRow(cells: [
                DataCell(Text(dateHeureFr(l['survenu_le']))),
                DataCell(Text('${l['utilisateur']}${l['appareil'] == null ? '' : ' (${l['appareil']})'}')),
                DataCell(Text(_actions[l['action']] ?? '${l['action']}')),
                DataCell(Text('${l['table_cible'] ?? ''}')),
                DataCell(SizedBox(
                  width: 420,
                  child: Text(_resume(l['avant'], l['apres']), maxLines: 2, overflow: TextOverflow.ellipsis),
                )),
              ]),
          ],
        ),
      ]);
}
