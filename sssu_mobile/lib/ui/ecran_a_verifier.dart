import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../services.dart';
import 'etablissements.dart' show formaterDateFr;

const Map<String, String> libellesTables = {
  'eleve': 'Dossier d\'élève',
  'inscription': 'Inscription',
  'classe': 'Classe',
  'visite': 'Visite',
  'antecedent': 'Antécédent',
  'examen_appareil': 'Examen',
  'visite_pathologie': 'Pathologie',
  'consentement': 'Consentement',
  'photo': 'Photographie',
  'import_lot': 'Importation',
  'import_ligne': 'Ligne importée',
  'inspection': 'Inspection sanitaire',
  'inspection_reponse': 'Réponse d\'inspection',
  'inspection_photo': 'Photo d\'inspection',
};

/// Éléments que le poste central n'a pas acceptés (refus ou conflit), avec
/// leur motif. Ils restent sur le téléphone, intacts, jusqu'à la décision du
/// Médecin-Chef sur le poste central, qui les remplace à la synchronisation
/// suivante. Un élément jamais accepté par le poste (création refusée) peut
/// être abandonné ici.
class EcranAVerifier extends ConsumerStatefulWidget {
  const EcranAVerifier({super.key});
  @override
  ConsumerState<EcranAVerifier> createState() => _EcranAVerifierState();
}

class _EcranAVerifierState extends ConsumerState<EcranAVerifier> {
  List<({Enregistrement enregistrement, String? motif})>? _liste;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final l = await ref.read(servicesProvider).depot.enConflit();
    if (mounted) setState(() => _liste = l);
  }

  String _resume(Enregistrement e) {
    final d = e.donnees;
    final morceaux = <String>[
      if (d['nom'] != null) '${d['nom']} ${d['prenoms'] ?? ''}'.trim(),
      if (d['matricule'] != null) 'matricule ${d['matricule']}',
      if (d['libelle'] != null) '${d['libelle']}',
      if (d['date_visite'] is String) 'visite du ${formaterDateFr(lireDate(d['date_visite']! as String))}',
    ];
    return morceaux.isEmpty ? 'Saisi le ${formaterDateFr(e.updatedAt)}' : morceaux.join(' · ');
  }

  Future<void> _abandonner(Enregistrement e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Abandonner ma version ?'),
        content: const Text('Cet élément n\'a jamais été accepté par le poste central. Il sera effacé du téléphone, '
            'avec les éléments saisis qui en dépendent. Cette action est définitive.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Abandonner')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final n = await ref.read(servicesProvider).depot.abandonner(e.table, e.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(n == 1 ? 'Élément effacé.' : '$n éléments effacés.')));
      }
    } on StateError catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
    }
    _charger();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Éléments à vérifier')),
        body: _liste == null
            ? const Center(child: CircularProgressIndicator())
            : _liste!.isEmpty
                ? const Padding(padding: EdgeInsets.all(24), child: Text('Aucun élément à vérifier.'))
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('Ces éléments sont conservés sur le téléphone. Le Médecin-Chef décide sur le poste '
                            'central de la version à garder ; sa décision arrive à la prochaine synchronisation.'),
                      ),
                      for (final x in _liste!)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(libellesTables[x.enregistrement.table] ?? x.enregistrement.table,
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text(_resume(x.enregistrement)),
                                const SizedBox(height: 4),
                                Text(x.motif ?? 'Conflit signalé par le poste central.',
                                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                                if (x.enregistrement.versionBase == 0)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () => _abandonner(x.enregistrement),
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('Abandonner ma version'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
      );
}
