/// Fiche d'un établissement (création ou modification), partagée par la page
/// Établissements et les Paramètres.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../services.dart';
import 'commun.dart';

/// Renvoie vrai si l'établissement a été enregistré.
Future<bool> editerEtablissement(BuildContext context, WidgetRef ref, Map<String, dynamic>? existant) async {
  final d = existant ?? const <String, dynamic>{};
  final champs = {
    for (final k in ['nom', 'code', 'region', 'district_sanitaire', 'localite', 'responsable', 'telephone'])
      k: TextEditingController(text: d[k]?.toString() ?? (k == 'district_sanitaire' ? 'Kouassi-Kouassikro' : k == 'region' ? "N'Zi" : '')),
  };
  var type = TypeEtablissement.depuisCode((d['type'] as String?) ?? 'primaire');
  var statut = StatutEtablissement.depuisCode((d['statut'] as String?) ?? 'public');
  const libelles = {
    'nom': 'Nom de l\'établissement',
    'code': 'Code',
    'region': 'Région',
    'district_sanitaire': 'District sanitaire',
    'localite': 'Localité',
    'responsable': 'Nom du responsable',
    'telephone': 'Téléphone',
  };
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, maj) => AlertDialog(
        title: Text(existant == null ? 'Nouvel établissement' : 'Modifier l\'établissement'),
        content: SizedBox(
          width: 480,
          child: ListView(shrinkWrap: true, children: [
            for (final k in champs.keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(controller: champs[k], decoration: InputDecoration(labelText: libelles[k])),
              ),
            DropdownButtonFormField<TypeEtablissement>(
              value: type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [for (final t in TypeEtablissement.values) DropdownMenuItem(value: t, child: Text(t.libelle))],
              onChanged: (v) => maj(() => type = v ?? type),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<StatutEtablissement>(
              value: statut,
              decoration: const InputDecoration(labelText: 'Statut'),
              items: [for (final t in StatutEtablissement.values) DropdownMenuItem(value: t, child: Text(t.libelle))],
              onChanged: (v) => maj(() => statut = v ?? statut),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enregistrer')),
        ],
      ),
    ),
  );
  final donnees = <String, Object?>{
    for (final x in champs.entries) x.key: x.value.text.trim().isEmpty ? null : x.value.text.trim(),
    'type': type.code,
    'statut': statut.code,
  };
  for (final c in champs.values) {
    c.dispose();
  }
  if (ok != true || !context.mounted) return false;
  final s = ref.read(servicesProvider);
  final droits = ref.read(sessionProvider)!.droits;
  return executer(context, () async {
    if (existant == null) {
      await s.gestion.creerEtablissement(droits, donnees);
    } else {
      await s.gestion.modifierEtablissement(droits, existant['id'].toString(), donnees);
    }
  }, succes: 'Établissement enregistré. Pensez à l\'affecter aux téléphones concernés.');
}
