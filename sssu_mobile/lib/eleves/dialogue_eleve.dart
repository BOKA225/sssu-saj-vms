/// Saisie de l'identité d'un élève sur le téléphone (ajout ou modification),
/// avec les mêmes contrôles que l'importation (`identiteEleveSaisie`).
library;

import 'package:flutter/material.dart';
import 'package:sssu_core/sssu_core.dart';

String _dateFr(String? iso) {
  if (iso == null) return '';
  final d = lireDate(iso);
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// Identité contrôlée, ou null si l'utilisateur annule.
Future<Map<String, Object?>?> saisirEleve(BuildContext context, {required String titre, Map<String, Object?>? actuel}) =>
    showDialog<Map<String, Object?>>(context: context, builder: (_) => _DialogueEleve(titre, actuel ?? const {}));

class _DialogueEleve extends StatefulWidget {
  final String titre;
  final Map<String, Object?> actuel;
  const _DialogueEleve(this.titre, this.actuel);
  @override
  State<_DialogueEleve> createState() => _DialogueEleveState();
}

class _DialogueEleveState extends State<_DialogueEleve> {
  late final TextEditingController _nom, _prenoms, _date, _matricule, _telephone;
  Sexe? _sexe;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    final d = widget.actuel;
    _nom = TextEditingController(text: d['nom'] as String? ?? '');
    _prenoms = TextEditingController(text: d['prenoms'] as String? ?? '');
    _date = TextEditingController(text: _dateFr(d['date_naissance'] as String?));
    _matricule = TextEditingController(text: d['matricule'] as String? ?? '');
    _telephone = TextEditingController(text: d['telephone_contact'] as String? ?? '');
    _sexe = lireSexe(d['sexe'] as String?);
  }

  @override
  void dispose() {
    for (final c in [_nom, _prenoms, _date, _matricule, _telephone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _valider() {
    try {
      Navigator.pop(
          context,
          identiteEleveSaisie(
            matricule: _matricule.text,
            nom: _nom.text,
            prenoms: _prenoms.text,
            dateNaissance: _date.text,
            sexe: _sexe?.code,
            telephone: _telephone.text,
            aujourdhui: DateTime.now().toUtc(),
          ));
    } on FormatException catch (e) {
      setState(() => _erreur = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.titre),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
                controller: _nom,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Nom *')),
            TextField(
                controller: _prenoms,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Prénoms *')),
            const SizedBox(height: 12),
            SegmentedButton<Sexe>(
              emptySelectionAllowed: true,
              segments: [for (final s in Sexe.values) ButtonSegment(value: s, label: Text(s.libelle))],
              selected: {if (_sexe != null) _sexe!},
              onSelectionChanged: (s) => setState(() => _sexe = s.isEmpty ? null : s.first),
            ),
            TextField(
                controller: _date,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(labelText: 'Date de naissance (JJ/MM/AAAA)')),
            TextField(controller: _matricule, decoration: const InputDecoration(labelText: 'Matricule')),
            TextField(
                controller: _telephone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Téléphone du parent')),
            if (_erreur != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: _valider, child: const Text('Enregistrer')),
        ],
      );
}
