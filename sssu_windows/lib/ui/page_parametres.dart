/// Paramètres (droit `parametres.modifier`) : en-tête institutionnel des
/// rapports (modifiable pour un déploiement dans un autre district), logo du
/// SSSU-SAJ, nom du Médecin-Chef, seuils du niveau de conformité des
/// inspections, délais de verrouillage. Les paramètres sont transmis aux
/// téléphones à leur synchronisation suivante.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:sssu_core/sssu_core.dart';

import '../services.dart';
import 'commun.dart';
import 'dialogue_etablissement.dart';

/// Logo réduit à 400 px au plus et réencodé en PNG (fond transparent conservé).
Uint8List preparerLogo(Uint8List octets) {
  final source = img.decodeImage(octets);
  if (source == null) throw const FormatException('Image illisible.');
  var image = source;
  if (image.width > 400 || image.height > 400) {
    image = image.width >= image.height ? img.copyResize(image, width: 400) : img.copyResize(image, height: 400);
  }
  return img.encodePng(image, level: 9);
}

class PageParametres extends ConsumerStatefulWidget {
  const PageParametres({super.key});
  @override
  ConsumerState<PageParametres> createState() => _PageParametresState();
}

class _PageParametresState extends ConsumerState<PageParametres> {
  final _lignes = List.generate(6, (_) => TextEditingController());
  final _medecin = TextEditingController();
  final _satisfaisant = TextEditingController();
  final _moyen = TextEditingController();
  final _verrouMobile = TextEditingController();
  final _verrouWindows = TextEditingController();
  String? _logo;
  bool _logoModifie = false;
  List<Map<String, dynamic>> _etablissements = const [];
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    for (final c in [..._lignes, _medecin, _satisfaisant, _moyen, _verrouMobile, _verrouWindows]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _charger() async {
    final p = await ref.read(servicesProvider).statistiques.parametres();
    final etablissements = await ref.read(servicesProvider).requetes.listeEtablissements();
    if (!mounted) return;
    setState(() {
      _etablissements = etablissements;
      for (var i = 0; i < 6; i++) {
        _lignes[i].text = p['entete_ligne_${i + 1}'] ?? '';
      }
      _medecin.text = p['nom_medecin_chef'] ?? '';
      _satisfaisant.text = p['seuil_conformite_satisfaisant'] ?? '80';
      _moyen.text = p['seuil_conformite_moyen'] ?? '50';
      _verrouMobile.text = p['verrouillage_mobile_minutes'] ?? '5';
      _verrouWindows.text = p['verrouillage_windows_minutes'] ?? '15';
      _logo = p['logo_png'];
      _logoModifie = false;
      _charge = true;
    });
  }

  Future<void> _choisirLogo() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg']);
    final chemin = r?.files.single.path;
    if (chemin == null) return;
    try {
      final png = preparerLogo(await File(chemin).readAsBytes());
      setState(() {
        _logo = base64.encode(png);
        _logoModifie = true;
      });
    } on FormatException catch (e) {
      if (mounted) message(context, e.message);
    }
  }

  Future<void> _enregistrer() async {
    final s = ref.read(servicesProvider);
    final droits = ref.read(sessionProvider)!.droits;
    final ok = await executer(
      context,
      () => s.gestion.definirParametres(droits, {
        for (var i = 0; i < 6; i++) 'entete_ligne_${i + 1}': _lignes[i].text,
        'nom_medecin_chef': _medecin.text,
        'seuil_conformite_satisfaisant': _satisfaisant.text,
        'seuil_conformite_moyen': _moyen.text,
        'verrouillage_mobile_minutes': _verrouMobile.text,
        'verrouillage_windows_minutes': _verrouWindows.text,
        if (_logoModifie) 'logo_png': _logo,
      }),
      succes: 'Paramètres enregistrés. Ils seront transmis aux téléphones à leur prochaine synchronisation.',
    );
    if (ok) _charger();
  }

  Widget _champ(TextEditingController c, String libelle, {double largeur = 640, bool nombre = false}) => SizedBox(
        width: largeur,
        child: TextField(
          controller: c,
          decoration: InputDecoration(labelText: libelle),
          keyboardType: nombre ? TextInputType.number : null,
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!_charge) return const Center(child: CircularProgressIndicator());
    final apercu = EnteteRapport.depuisParametres({
      for (var i = 0; i < 6; i++) 'entete_ligne_${i + 1}': _lignes[i].text,
    });
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('Paramètres', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('En-tête institutionnel des rapports', style: Theme.of(context).textTheme.titleMedium),
            const Text('Une ligne par niveau. Laissez toutes les lignes vides pour revenir à l\'en-tête par défaut.',
                style: TextStyle(fontSize: 12)),
            for (var i = 0; i < 6; i++) _champ(_lignes[i], 'Ligne ${i + 1}'),
            const SizedBox(height: 12),
            _champ(_medecin, 'Nom du Médecin-Chef (bloc de signature des rapports)'),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
                alignment: Alignment.center,
                child: _logo == null || _logo!.isEmpty
                    ? const Text('Pas de logo', style: TextStyle(color: Colors.black38))
                    : Image.memory(base64.decode(_logo!), fit: BoxFit.contain),
              ),
              const SizedBox(width: 16),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Logo du SSSU-SAJ (PNG ou JPEG, réduit automatiquement).'),
                const SizedBox(height: 8),
                Row(children: [
                  OutlinedButton.icon(onPressed: _choisirLogo, icon: const Icon(Icons.image), label: const Text('Choisir')),
                  const SizedBox(width: 8),
                  if (_logo != null && _logo!.isNotEmpty)
                    TextButton(
                        onPressed: () => setState(() {
                              _logo = null;
                              _logoModifie = true;
                            }),
                        child: const Text('Retirer')),
                ]),
              ]),
              const SizedBox(width: 32),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  color: const Color(0xFFF5F7FA),
                  child: Column(children: [
                    const Text('Aperçu', style: TextStyle(fontSize: 11, color: Colors.black54)),
                    for (final l in apercu.lignes)
                      Text(l, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ]),
                ),
              ),
            ]),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Inspections sanitaires', style: Theme.of(context).textTheme.titleMedium),
            const Text('Niveau global : satisfaisant à partir du premier seuil, moyen à partir du second, insuffisant en '
                'dessous. Le taux compte « partiellement conforme » pour moitié et exclut « non applicable ».',
                style: TextStyle(fontSize: 12)),
            Wrap(spacing: 24, children: [
              _champ(_satisfaisant, 'Seuil « satisfaisant » (%)', largeur: 220, nombre: true),
              _champ(_moyen, 'Seuil « moyen » (%)', largeur: 220, nombre: true),
            ]),
            const SizedBox(height: 8),
            const Text('Les seuils s\'appliquent aux inspections enregistrées après leur modification.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Verrouillage automatique', style: Theme.of(context).textTheme.titleMedium),
            Wrap(spacing: 24, children: [
              _champ(_verrouMobile, 'Téléphones (minutes)', largeur: 220, nombre: true),
              _champ(_verrouWindows, 'Poste central (minutes)', largeur: 220, nombre: true),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(onPressed: _enregistrer, icon: const Icon(Icons.save), label: const Text('Enregistrer')),
      ),
      const SizedBox(height: 24),
      _carteEtablissements(),
    ]);
  }

  Future<void> _rechargerEtablissements() async {
    final l = await ref.read(servicesProvider).requetes.listeEtablissements();
    if (mounted) setState(() => _etablissements = l);
  }

  /// Liste des établissements : code, nom, responsable, statut. Les
  /// modifications sont enregistrées aussitôt (indépendamment du bouton
  /// « Enregistrer » ci-dessus) et transmises aux téléphones concernés.
  Widget _carteEtablissements() {
    final peutGerer = ref.read(sessionProvider)!.droits.peut(Permission.etablissementGerer);
    String statut(Object? c) {
      try {
        return StatutEtablissement.depuisCode(c! as String).libelle;
      } catch (_) {
        return '${c ?? ''}';
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('Établissements (${_etablissements.length})', style: Theme.of(context).textTheme.titleMedium),
            ),
            if (peutGerer)
              OutlinedButton.icon(
                onPressed: () async {
                  if (await editerEtablissement(context, ref, null)) await _rechargerEtablissements();
                },
                icon: const Icon(Icons.add),
                label: const Text('Nouvel établissement'),
              ),
          ]),
          const Text('Modifications enregistrées immédiatement. Classes et archivage : page Établissements.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          if (_etablissements.isEmpty)
            const Padding(padding: EdgeInsets.all(8), child: Text('Aucun établissement enregistré.'))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                showCheckboxColumn: false,
                columns: const [
                  DataColumn(label: Text('Code')),
                  DataColumn(label: Text('Nom')),
                  DataColumn(label: Text('Responsable')),
                  DataColumn(label: Text('Statut')),
                ],
                rows: [
                  for (final e in _etablissements)
                    DataRow(
                      onSelectChanged: !peutGerer
                          ? null
                          : (_) async {
                              if (await editerEtablissement(context, ref, e)) await _rechargerEtablissements();
                            },
                      cells: [
                        DataCell(Text('${e['code'] ?? ''}')),
                        DataCell(Text('${e['nom'] ?? ''}')),
                        DataCell(Text('${e['responsable'] ?? '—'}')),
                        DataCell(Text(statut(e['statut']))),
                      ],
                    ),
                ],
              ),
            ),
        ]),
      ),
    );
  }
}
