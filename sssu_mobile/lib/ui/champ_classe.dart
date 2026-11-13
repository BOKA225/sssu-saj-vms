/// Saisie du libellé d'une classe, avec les classes usuelles proposées.
library;

import 'package:flutter/material.dart';
import 'package:sssu_core/sssu_core.dart';

/// Libellé de classe avec les classes usuelles proposées pendant la saisie
/// (primaire, secondaire général, enseignement technique : 2nde G1, Tle F2,
/// BT 1…). La saisie reste libre.
class ChampLibelleClasse extends StatefulWidget {
  final TextEditingController controleur;
  final bool autofocus;
  const ChampLibelleClasse(this.controleur, {super.key, this.autofocus = false});

  @override
  State<ChampLibelleClasse> createState() => _ChampLibelleClasseState();
}

class _ChampLibelleClasseState extends State<ChampLibelleClasse> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<String>(
        textEditingController: widget.controleur,
        focusNode: _focus,
        optionsBuilder: (v) => suggestionsClasses(v.text),
        fieldViewBuilder: (context, controleur, focus, valider) => TextField(
          controller: controleur,
          focusNode: focus,
          autofocus: widget.autofocus,
          decoration: const InputDecoration(
              labelText: 'Libellé', helperText: 'ex. CM2 A, 6ème 3, 2nde G1, 1ère F3, Tle G2, BT 1'),
          onSubmitted: (_) => valider(),
        ),
        optionsViewBuilder: (context, choisir, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 300),
              child: ListView(padding: EdgeInsets.zero, shrinkWrap: true, children: [
                for (final o in options) ListTile(dense: true, title: Text(o), onTap: () => choisir(o)),
              ]),
            ),
          ),
        ),
      );
}
