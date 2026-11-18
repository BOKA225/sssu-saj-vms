/// Saisie des effectifs des classes d'un établissement, par sexe : élèves
/// inscrits et élèves visités (visite systématique ; visite d'aptitude pour
/// les classes de 3ème et de terminale). Droit `etablissement.gerer`
/// (administrateur, Médecin-Chef). Les statistiques utilisent ces chiffres
/// pour les classes sans liste d'élèves ; une classe dont la liste est
/// importée garde les chiffres de sa liste.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../donnees/requetes_poste.dart';
import '../services.dart';
import 'commun.dart';

/// Ouvre la saisie ; retourne `true` si des effectifs ont été enregistrés.
Future<bool> saisirEffectifs(BuildContext context,
        {required String etablissement, required List<LigneClasse> classes}) async =>
    await showDialog<bool>(
        context: context, builder: (_) => _DialogueEffectifs(etablissement: etablissement, classes: classes)) ??
    false;

const _champs = ['garcons', 'filles', 'visites_garcons', 'visites_filles', 'aptitude_garcons', 'aptitude_filles'];

class _DialogueEffectifs extends ConsumerStatefulWidget {
  final String etablissement;
  final List<LigneClasse> classes;
  const _DialogueEffectifs({required this.etablissement, required this.classes});
  @override
  ConsumerState<_DialogueEffectifs> createState() => _DialogueEffectifsState();
}

class _DialogueEffectifsState extends ConsumerState<_DialogueEffectifs> {
  /// Classe → champ → saisie.
  late final Map<String, Map<String, TextEditingController>> _c = {
    for (final c in widget.classes)
      c.id: {
        for (final k in _champs)
          k: TextEditingController(text: '${c.saisi?.versDonnees()[k] ?? ''}')..addListener(_rafraichir),
      }
  };
  String? _erreur;
  bool _occupe = false;

  void _rafraichir() => setState(() {});

  @override
  void dispose() {
    for (final m in _c.values) {
      for (final t in m.values) {
        t.dispose();
      }
    }
    super.dispose();
  }

  int? _n(String classe, String champ) => int.tryParse(_c[classe]![champ]!.text.trim());

  EffectifSaisi _saisie(LigneClasse c) => EffectifSaisi(
        c.id,
        garcons: _n(c.id, 'garcons'),
        filles: _n(c.id, 'filles'),
        visitesGarcons: _n(c.id, 'visites_garcons'),
        visitesFilles: _n(c.id, 'visites_filles'),
        aptitudeGarcons: c.aptitude ? _n(c.id, 'aptitude_garcons') : null,
        aptitudeFilles: c.aptitude ? _n(c.id, 'aptitude_filles') : null,
      );

  Future<void> _enregistrer() async {
    final saisies = [for (final c in widget.classes) if (c.effectif == 0) _saisie(c)];
    for (final c in widget.classes.where((c) => c.effectif == 0)) {
      for (final k in _champs) {
        final t = _c[c.id]![k]!.text.trim();
        if (t.isNotEmpty && int.tryParse(t) == null) {
          setState(() => _erreur = '${c.libelle} : « $t » n\'est pas un nombre.');
          return;
        }
      }
      final e = _saisie(c).erreurs(classe: c.libelle);
      if (e.isNotEmpty) {
        setState(() => _erreur = e.first);
        return;
      }
    }
    setState(() {
      _erreur = null;
      _occupe = true;
    });
    final s = ref.read(servicesProvider);
    final ok = await executer(context, () => s.gestion.enregistrerEffectifs(ref.read(sessionProvider)!.droits, saisies),
        succes: 'Effectifs enregistrés.');
    if (!mounted) return;
    setState(() => _occupe = false);
    if (ok) Navigator.pop(context, true);
  }

  Widget _champ(LigneClasse c, String k) => SizedBox(
        width: 64,
        child: TextField(
          controller: _c[c.id]![k],
          textAlign: TextAlign.right,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final aptitude = widget.classes.any((c) => c.aptitude);
    const gras = TextStyle(fontWeight: FontWeight.bold);
    final saisies = [for (final c in widget.classes) if (c.effectif == 0) _saisie(c)];
    int somme(int? Function(EffectifSaisi s) f) => saisies.fold(0, (t, s) => t + (f(s) ?? 0));
    return AlertDialog(
      title: Text('Effectifs par classe et par sexe · ${widget.etablissement}'),
      content: SizedBox(
        width: aptitude ? 1060 : 860,
        height: 560,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Pour les classes sans liste d\'élèves, saisissez le nombre de garçons et de filles inscrits, puis les '
              'élèves visités. Les statistiques et les rapports les utilisent pour l\'effectif, les examinés et la '
              'couverture. Une classe dont la liste est importée garde les chiffres de sa liste. Laissez vide ce qui '
              'n\'est pas connu.'),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 14,
                  headingRowHeight: 52,
                  dataRowMinHeight: 44,
                  dataRowMaxHeight: 52,
                  columns: [
                    const DataColumn(label: Text('Classe', style: gras)),
                    const DataColumn(label: Text('Inscrits\ngarçons', style: gras)),
                    const DataColumn(label: Text('Inscrits\nfilles', style: gras)),
                    const DataColumn(label: Text('Total', style: gras), numeric: true),
                    const DataColumn(label: Text('Visités (syst.)\ngarçons', style: gras)),
                    const DataColumn(label: Text('Visités (syst.)\nfilles', style: gras)),
                    if (aptitude) ...[
                      const DataColumn(label: Text('Aptitude\ngarçons', style: gras)),
                      const DataColumn(label: Text('Aptitude\nfilles', style: gras)),
                    ],
                    const DataColumn(label: Text('Couverture', style: gras), numeric: true),
                  ],
                  rows: [
                    for (final c in widget.classes)
                      if (c.effectif > 0)
                        DataRow(
                          color: const WidgetStatePropertyAll(Color(0xFFF4F6F8)),
                          cells: [
                            DataCell(Text(c.libelle)),
                            DataCell(Text('${c.garcons}')),
                            DataCell(Text('${c.filles}')),
                            DataCell(Text('${c.effectif}')),
                            DataCell(Text('Liste d\'élèves : ${c.examines} examiné(s)',
                                style: const TextStyle(fontSize: 12, color: Colors.black54))),
                            const DataCell(Text('')),
                            if (aptitude) ...[const DataCell(Text('')), const DataCell(Text(''))],
                            DataCell(Text(pourcentage(taux(c.examines, c.effectif)))),
                          ],
                        )
                      else
                        DataRow(cells: [
                          DataCell(Text(c.libelle)),
                          DataCell(_champ(c, 'garcons')),
                          DataCell(_champ(c, 'filles')),
                          DataCell(Text('${_saisie(c).effectif}')),
                          DataCell(_champ(c, 'visites_garcons')),
                          DataCell(_champ(c, 'visites_filles')),
                          if (aptitude) ...[
                            DataCell(c.aptitude ? _champ(c, 'aptitude_garcons') : const Text('—')),
                            DataCell(c.aptitude ? _champ(c, 'aptitude_filles') : const Text('—')),
                          ],
                          DataCell(Text(pourcentage(taux(_saisie(c).visites(TypeVisite.systematique), _saisie(c).effectif)))),
                        ]),
                  ],
                ),
              ),
            ),
          ),
          const Divider(),
          Text(
              'Classes sans liste : ${somme((s) => s.garcons)} garçons et ${somme((s) => s.filles)} filles inscrits ; '
              '${somme((s) => s.visitesGarcons)} garçons et ${somme((s) => s.visitesFilles)} filles visités'
              '${aptitude ? ' (aptitude : ${somme((s) => s.aptitudeGarcons)} G, ${somme((s) => s.aptitudeFilles)} F)' : ''}.',
              style: gras),
          if (_erreur != null) Text(_erreur!, style: const TextStyle(color: Colors.red)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton(onPressed: _occupe ? null : _enregistrer, child: const Text('Enregistrer')),
      ],
    );
  }
}
