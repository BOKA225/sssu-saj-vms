import 'package:flutter/material.dart';
import 'package:sssu_core/sssu_core.dart';

String dateFr(Object? v) {
  if (v == null) return '';
  final d = v is DateTime ? v.toLocal() : DateTime.tryParse(v.toString())?.toLocal();
  if (d == null) return v.toString();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String dateHeureFr(Object? v) {
  if (v == null) return '';
  final d = v is DateTime ? v.toLocal() : DateTime.tryParse(v.toString())?.toLocal();
  if (d == null) return v.toString();
  return '${dateFr(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

void message(BuildContext context, String texte) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));

/// Exécute une action de gestion et affiche son erreur éventuelle.
Future<bool> executer(BuildContext context, Future<void> Function() action, {String? succes}) async {
  try {
    await action();
    if (succes != null && context.mounted) message(context, succes);
    return true;
  } on ErreurGestion catch (e) {
    if (context.mounted) message(context, e.message);
  } on ErreurSaisie catch (e) {
    if (context.mounted) message(context, e.message);
  } on ArgumentError catch (e) {
    if (context.mounted) message(context, '${e.message}');
  } on StateError catch (e) {
    if (context.mounted) message(context, e.message);
  }
  return false;
}

Future<bool> confirmer(BuildContext context, String titre, String texte, {String bouton = 'Confirmer'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titre),
        content: Text(texte),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(bouton)),
        ],
      ),
    ) ==
    true;

/// Saisie d'un texte (motif, mot de passe temporaire…).
Future<String?> saisir(BuildContext context, String titre, String libelle, {bool secret = false}) async {
  final c = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(titre),
      content: SizedBox(
        width: 400,
        child: TextField(controller: c, obscureText: secret, autofocus: true, decoration: InputDecoration(labelText: libelle)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Valider')),
      ],
    ),
  );
  c.dispose();
  return r;
}

/// Le compte peut-il consulter les données médicales ?
bool accesMedical(Droits d) =>
    d.peut(Permission.visiteSaisir) || d.peut(Permission.visiteValider) || d.peut(Permission.visiteModifierToutes);

String libelleStatutVisite(String code) => StatutVisite.depuisCode(code).libelle;

String libelleConclusion(String? code) => code == null ? '—' : ConclusionVisite.depuisCode(code).libelle;

/// Carte titrée pour les écrans de consultation.
class Bloc extends StatelessWidget {
  final String titre;
  final List<Widget> enfants;
  final Widget? action;
  const Bloc({super.key, required this.titre, required this.enfants, this.action});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(titre, style: Theme.of(context).textTheme.titleMedium)),
              if (action != null) action!,
            ]),
            const SizedBox(height: 8),
            ...enfants,
          ]),
        ),
      );
}

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
