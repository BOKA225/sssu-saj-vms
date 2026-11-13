/// Saisie du dossier administratif d'un élève (ajout ou modification) :
/// identité, et pour un ajout, l'établissement et la classe de l'année.
/// Mêmes contrôles que l'importation des listes (`identiteEleveSaisie`).
library;

import 'package:flutter/material.dart';
import 'package:sssu_core/sssu_core.dart';

import '../donnees/requetes_poste.dart';
import 'commun.dart';

class SaisieEleve {
  /// Champs contrôlés, prêts à être enregistrés.
  final Map<String, Object?> identite;

  /// Classe choisie (ajout seulement).
  final String? classeId;
  const SaisieEleve(this.identite, this.classeId);
}

class DialogueEleve extends StatefulWidget {
  final String titre;

  /// Identité actuelle (modification).
  final Map<String, Object?>? actuel;

  /// Établissements proposés pour un ajout (null : pas de choix de classe).
  final List<LigneEtablissement>? etablissements;
  final Future<List<LigneClasse>> Function(String etablissementId)? classesDe;
  final String? etablissementId;
  final String? classeId;

  const DialogueEleve({
    super.key,
    required this.titre,
    this.actuel,
    this.etablissements,
    this.classesDe,
    this.etablissementId,
    this.classeId,
  });

  @override
  State<DialogueEleve> createState() => _DialogueEleveState();
}

class _DialogueEleveState extends State<DialogueEleve> {
  late final Map<String, TextEditingController> _c;
  String? _sexe;
  String? _etab;
  String? _classe;
  List<LigneClasse> _classes = const [];
  String? _erreur;

  bool get _choixClasse => widget.etablissements != null;

  @override
  void initState() {
    super.initState();
    final d = widget.actuel ?? const <String, Object?>{};
    String texte(String k) => d[k] as String? ?? '';
    _c = {
      'matricule': TextEditingController(text: texte('matricule')),
      'nom': TextEditingController(text: texte('nom')),
      'prenoms': TextEditingController(text: texte('prenoms')),
      'date': TextEditingController(text: d['date_naissance'] == null ? '' : dateFr(d['date_naissance'])),
      'telephone': TextEditingController(text: texte('telephone_contact')),
    };
    _sexe = d['sexe'] as String?;
    _etab = widget.etablissementId;
    _classe = widget.classeId;
    if (_choixClasse && _etab != null) _chargerClasses(_etab!);
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _chargerClasses(String etab) async {
    final c = await widget.classesDe!(etab);
    if (!mounted) return;
    setState(() {
      _classes = c;
      if (!c.any((x) => x.id == _classe)) _classe = null;
    });
  }

  void _valider() {
    try {
      final identite = identiteEleveSaisie(
        matricule: _c['matricule']!.text,
        nom: _c['nom']!.text,
        prenoms: _c['prenoms']!.text,
        dateNaissance: _c['date']!.text,
        sexe: _sexe,
        telephone: _c['telephone']!.text,
        aujourdhui: DateTime.now().toUtc(),
      );
      if (_choixClasse && _classe == null) {
        setState(() => _erreur = 'Choisissez l\'établissement et la classe de l\'élève.');
        return;
      }
      Navigator.pop(context, SaisieEleve(identite, _classe));
    } on FormatException catch (e) {
      setState(() => _erreur = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.titre),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: _c['nom'], autofocus: true, decoration: const InputDecoration(labelText: 'Nom *')),
              TextField(controller: _c['prenoms'], decoration: const InputDecoration(labelText: 'Prénoms *')),
              const SizedBox(height: 12),
              const Text('Sexe *'),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(value: 'M', label: Text('Masculin')),
                  ButtonSegment(value: 'F', label: Text('Féminin')),
                ],
                selected: {if (_sexe != null) _sexe!},
                onSelectionChanged: (s) => setState(() => _sexe = s.isEmpty ? null : s.first),
              ),
              TextField(
                  controller: _c['date'], decoration: const InputDecoration(labelText: 'Date de naissance (JJ/MM/AAAA)')),
              TextField(controller: _c['matricule'], decoration: const InputDecoration(labelText: 'Matricule')),
              TextField(controller: _c['telephone'], decoration: const InputDecoration(labelText: 'Téléphone du parent')),
              if (_choixClasse) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _etab,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Établissement *'),
                  items: [
                    for (final e in widget.etablissements!)
                      DropdownMenuItem(value: e.id, child: Text(e.nom, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (id) {
                    setState(() {
                      _etab = id;
                      _classe = null;
                      _classes = const [];
                    });
                    if (id != null) _chargerClasses(id);
                  },
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey(_etab),
                  value: _classe,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Classe *'),
                  items: [
                    for (final c in _classes) DropdownMenuItem(value: c.id, child: Text('${c.libelle} · ${c.effectif} élèves')),
                  ],
                  onChanged: (c) => setState(() => _classe = c),
                ),
              ],
              if (_erreur != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: _valider, child: const Text('Enregistrer')),
        ],
      );
}

/// Élève déjà enregistré qui ressemble à celui saisi (même matricule, ou
/// mêmes nom, prénoms et date de naissance), sinon null.
IdentiteEleve? eleveSemblable(Map<String, Object?> identite, List<Enregistrement> existants, {String? sauf}) {
  final candidat = IdentiteEleve(
    matricule: identite['matricule'] as String?,
    nom: identite['nom']! as String,
    prenoms: identite['prenoms']! as String,
    dateNaissance: identite['date_naissance'] == null ? null : lireDate(identite['date_naissance']! as String),
  );
  final connus = [
    for (final e in existants)
      if (e.id != sauf)
        IdentiteEleve(
          id: e.id,
          matricule: e.donnees['matricule'] as String?,
          nom: e.donnees['nom']! as String,
          prenoms: e.donnees['prenoms']! as String,
          dateNaissance: e.donnees['date_naissance'] == null ? null : lireDate(e.donnees['date_naissance']! as String),
        ),
  ];
  final d = detecterDoublons([candidat], connus);
  return d.isEmpty ? null : d.first.existant;
}
