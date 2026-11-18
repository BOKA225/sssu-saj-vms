/// Suivi vaccinal d'un enfant du préscolaire : parent ou tuteur, carnet de
/// vaccination présenté, vaccins du PEV et hors PEV (obligatoires puis
/// recommandés) cochés « fait » ou « non fait », observations. Utilisé dans
/// l'onglet « Vaccination » de la visite et dans l'écran de vaccination de
/// l'enfant.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../data/requetes.dart';
import '../services.dart';
import 'service_vaccination.dart';

class EditeurVaccination extends StatelessWidget {
  final SuiviVaccinal suivi;

  /// Vaccins de la liste du préscolaire, dans l'ordre d'affichage.
  final List<Vaccin> vaccins;
  final bool modifiable;

  /// Appelé après chaque changement (la fiche est modifiée en place).
  final VoidCallback onChange;
  const EditeurVaccination(
      {super.key, required this.suivi, required this.vaccins, required this.modifiable, required this.onChange});

  void _maj(VoidCallback f) {
    f();
    onChange();
  }

  Widget _texte(String libelle, String valeur, void Function(String) maj,
          {int lignes = 1, TextInputType? clavier}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          initialValue: valeur,
          enabled: modifiable,
          maxLines: lignes,
          keyboardType: clavier,
          decoration: InputDecoration(labelText: libelle),
          onChanged: (v) => _maj(() => maj(v)),
        ),
      );

  Widget _choix(bool? valeur, void Function(bool?) maj, {String oui = 'Fait', String non = 'Non fait'}) =>
      SegmentedButton<bool>(
        segments: [ButtonSegment(value: true, label: Text(oui)), ButtonSegment(value: false, label: Text(non))],
        selected: {if (valeur != null) valeur},
        emptySelectionAllowed: true,
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        onSelectionChanged: modifiable ? (s) => _maj(() => maj(s.isEmpty ? null : s.first)) : null,
      );

  @override
  Widget build(BuildContext context) {
    final etat = etatVaccinal(suivi, vaccins);
    final couleur = switch (etat) {
      EtatVaccinal.aJour => Colors.green.shade700,
      EtatVaccinal.incomplet => Colors.orange.shade800,
      EtatVaccinal.nonRenseigne => Colors.grey.shade700,
    };
    final titre = Theme.of(context).textTheme.titleMedium;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: ListTile(
          leading: Icon(etat == EtatVaccinal.aJour ? Icons.verified : Icons.vaccines, color: couleur),
          title: Text('État vaccinal : ${etat.libelle}', style: TextStyle(color: couleur, fontWeight: FontWeight.bold)),
          subtitle: Text(etat.description),
        ),
      ),
      const SizedBox(height: 8),
      Text('Parent ou tuteur', style: titre),
      const SizedBox(height: 8),
      _texte('Nom du parent ou du tuteur', suivi.parentTuteur, (v) => suivi.parentTuteur = v),
      _texte('Téléphone du parent ou du tuteur', suivi.parentTelephone, (v) => suivi.parentTelephone = v,
          clavier: TextInputType.phone),
      Row(children: [
        const Expanded(child: Text('Carnet de vaccination présenté')),
        _choix(suivi.carnetPresente, (v) => suivi.carnetPresente = v, oui: 'Oui', non: 'Non'),
      ]),
      for (final p in ProgrammeVaccin.values)
        for (final s in StatutVaccin.values)
          if (vaccins.any((v) => v.programme == p && v.statut == s)) ...[
            const Divider(height: 28),
            Row(children: [
              Expanded(child: Text('${p.libelle} · vaccins ${s.pluriel.toLowerCase()}', style: titre)),
              if (modifiable)
                TextButton(
                  onPressed: () => _maj(() {
                    for (final v in vaccins.where((v) => v.programme == p && v.statut == s)) {
                      suivi.vaccins[v.id] = true;
                    }
                  }),
                  child: const Text('Tous faits'),
                ),
            ]),
            for (final v in vaccins.where((v) => v.programme == p && v.statut == s))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(v.libelle),
                      if (v.cible != null)
                        Text(v.cible!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ]),
                  ),
                  _choix(suivi.vaccins[v.id], (x) {
                    if (x == null) {
                      suivi.vaccins.remove(v.id);
                    } else {
                      suivi.vaccins[v.id] = x;
                    }
                  }),
                ]),
              ),
          ],
      if (vaccins.isEmpty)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Aucun vaccin dans la liste : synchronisez le téléphone avec le poste central.'),
        ),
      const Divider(height: 28),
      _texte('Observations (vaccin en retard, allergie connue…)', suivi.observations, (v) => suivi.observations = v,
          lignes: 3),
    ]);
  }
}

/// Écran de vaccination d'un enfant, ouvert depuis son dossier.
class EcranVaccination extends ConsumerStatefulWidget {
  final String eleveId;
  const EcranVaccination({super.key, required this.eleveId});
  @override
  ConsumerState<EcranVaccination> createState() => _EcranVaccinationState();
}

class _EcranVaccinationState extends ConsumerState<EcranVaccination> {
  LigneEleve? _eleve;
  List<Vaccin> _vaccins = const [];
  SuiviVaccinal? _suivi;
  bool _modifie = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final r = ref.read(servicesProvider).requetes;
    final a = await r.anneeCourante();
    final e = a == null ? null : await r.eleve(widget.eleveId, a);
    final vaccins = vaccinsPrescolaire(await r.vaccins());
    final suivi = await r.suiviVaccinal(widget.eleveId) ??
        SuiviVaccinal(eleveId: widget.eleveId, parentTelephone: e?.eleve.telephoneContact ?? '');
    if (mounted) {
      setState(() {
        _eleve = e;
        _vaccins = vaccins;
        _suivi = suivi;
      });
    }
  }

  bool get _modifiable => ref.read(sessionProvider)!.droits.peut(Permission.visiteSaisir);

  Future<bool> _enregistrer() async {
    final s = _suivi;
    if (s == null || !_modifie) return true;
    try {
      s.dateVerification = DateTime.now().toUtc();
      await ServiceVaccination(ref.read(servicesProvider).depot).enregistrer(s,
          utilisateurId: ref.read(sessionProvider)!.utilisateur.id, etablissementId: _eleve?.etablissementId);
      _modifie = false;
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : $e')));
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _suivi;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (aQuitte, _) async {
        if (aQuitte) return;
        final ok = await _enregistrer();
        if (ok && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_eleve == null ? 'Vaccination' : 'Vaccination · ${_eleve!.eleve.nomComplet}')),
        body: s == null
            ? const Center(child: CircularProgressIndicator())
            : EditeurVaccination(
                suivi: s,
                vaccins: _vaccins,
                modifiable: _modifiable,
                onChange: () => setState(() => _modifie = true),
              ),
        bottomNavigationBar: s == null || !_modifiable
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: FilledButton.icon(
                    onPressed: () async {
                      final ok = await _enregistrer();
                      if (ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Vaccination enregistrée. Elle sera transmise à la prochaine synchronisation.')));
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('Enregistrer'),
                  ),
                ),
              ),
      ),
    );
  }
}
