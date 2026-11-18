/// VACCINATION DU PRÉSCOLAIRE : enfants des classes de petite, moyenne et
/// grande section (et des établissements préscolaires) avec leurs vaccins du
/// PEV et hors PEV, obligatoires et recommandés (✓ fait, ✗ non fait, —
/// non renseigné) et leur état vaccinal ; fiche de l'enfant (parent ou
/// tuteur, carnet présenté, vaccins, observations) ; ajout d'un enfant ;
/// couverture par vaccin ; liste des vaccins modifiable ; export PDF, Word,
/// Excel.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../donnees/requetes_poste.dart';
import '../rapports/service_rapports.dart';
import '../services.dart';
import 'commun.dart';
import 'dialogue_eleve.dart';
import 'dialogue_vaccins.dart';
import 'page_rapports.dart' show exporterRapport;
import 'statistiques_commun.dart';

const _couleurPev = Color(0xFF1F5FA8);
const _couleurHorsPev = Color(0xFF7B3FA0);

class PageVaccination extends ConsumerStatefulWidget {
  const PageVaccination({super.key});
  @override
  ConsumerState<PageVaccination> createState() => _PageVaccinationState();
}

class _PageVaccinationState extends ConsumerState<PageVaccination> {
  late final Droits _droits = ref.read(sessionProvider)!.droits;
  List<Annee> _annees = const [];
  Annee? _annee;
  List<Vaccin> _tous = const [];
  List<EnfantVaccination>? _enfants;
  String? _etab;
  String? _classe;
  EtatVaccinal? _etat;
  String _texte = '';
  bool _occupe = false;
  String? _erreur;

  RequetesPoste get _r => ref.read(servicesProvider).requetes;

  /// Vaccins de la liste du préscolaire (actifs), dans l'ordre d'affichage.
  List<Vaccin> get _vaccins => vaccinsPrescolaire(_tous);

  @override
  void initState() {
    super.initState();
    _demarrer();
  }

  Future<void> _demarrer() async {
    try {
      final annees = await _r.annees();
      _annees = annees;
      _annee = annees.isEmpty ? null : annees.firstWhere((a) => a.active, orElse: () => annees.first);
      await _charger();
    } catch (e) {
      if (mounted) setState(() => _erreur = '$e');
    }
  }

  Future<void> _charger() async {
    final a = _annee;
    if (a == null) {
      setState(() => _enfants = const []);
      return;
    }
    final vaccins = await _r.vaccins();
    final enfants = await _r.enfantsPrescolaire(a);
    if (!mounted) return;
    setState(() {
      _tous = vaccins;
      _enfants = enfants;
      if (_etab != null && !enfants.any((e) => e.etablissementId == _etab)) _etab = null;
      if (_classe != null && !enfants.any((e) => e.classeId == _classe)) _classe = null;
    });
  }

  List<EnfantVaccination> get _visibles {
    final t = _texte.trim().toLowerCase();
    return [
      for (final e in _enfants ?? const <EnfantVaccination>[])
        if ((_etab == null || e.etablissementId == _etab) &&
            (_classe == null || e.classeId == _classe) &&
            (_etat == null || etatVaccinal(e.suivi, _vaccins) == _etat) &&
            (t.length < 2 || '${e.nom} ${e.prenoms} ${e.matricule ?? ''}'.toLowerCase().contains(t)))
          e
    ];
  }

  String get _perimetre {
    final e = _enfants ?? const <EnfantVaccination>[];
    final etab = _etab == null ? null : e.firstWhere((x) => x.etablissementId == _etab).etablissement;
    final classe = _classe == null ? null : e.firstWhere((x) => x.classeId == _classe).classe;
    return [
      'Année ${_annee?.libelle ?? ''}',
      etab ?? 'Tous les établissements',
      if (classe != null) classe,
      if (_etat != null) 'État : ${_etat!.libelle.toLowerCase()}',
    ].join(' · ');
  }

  Future<void> _ouvrir(EnfantVaccination e) async {
    if (!_droits.peut(Permission.visiteSaisir)) return;
    final suivi = await showDialog<SuiviVaccinal>(
      context: context,
      builder: (_) => DialogueSuiviVaccinal(enfant: e, vaccins: _vaccins),
    );
    if (suivi == null || !mounted) return;
    final ok = await executer(context, () => ref.read(servicesProvider).gestion.enregistrerSuiviVaccinal(_droits, suivi),
        succes: 'Vaccination de ${e.nomComplet} enregistrée.');
    if (ok) await _charger();
  }

  /// Nouvel enfant inscrit dans une classe du préscolaire, puis sa fiche de vaccination.
  Future<void> _ajouter() async {
    final a = _annee;
    if (a == null) return;
    final s = ref.read(servicesProvider);
    final etabs = await _r.etablissements(a);
    final classes = await _r.classesDeLAnnee(a);
    final types = {for (final e in etabs) e.id: e.donnees['type'] as String?};
    bool prescolaire(String etab, String libelle, String? niveau) =>
        classePrescolaire(libelle, niveau: niveau, typeEtablissement: types[etab]);
    final avecPrescolaire = {for (final c in classes) if (prescolaire(c.etablissementId, c.libelle, c.niveau)) c.etablissementId};
    if (avecPrescolaire.isEmpty) {
      if (mounted) {
        message(context, 'Aucune classe du préscolaire cette année : créez d\'abord la classe (petite, moyenne ou grande section) '
            'dans Établissements.');
      }
      return;
    }
    if (!mounted) return;
    final saisie = await showDialog<SaisieEleve>(
      context: context,
      builder: (_) => DialogueEleve(
        titre: 'Nouvel enfant du préscolaire (${a.libelle})',
        etablissements: [for (final e in etabs) if (avecPrescolaire.contains(e.id)) e],
        classesDe: (id) async => [for (final c in await _r.classes(id, a)) if (prescolaire(id, c.libelle, c.niveau)) c],
        etablissementId: _etab != null && avecPrescolaire.contains(_etab) ? _etab : null,
        classeId: _classe,
      ),
    );
    if (saisie == null || !mounted) return;
    final existants = await s.depot.transaction((tx) => tx.chercher('eleve', const {}));
    final semblable = eleveSemblable(saisie.identite, existants);
    if (semblable != null && mounted) {
      final ok = await confirmer(
          context,
          'Cet enfant semble déjà enregistré',
          '${semblable.nom} ${semblable.prenoms}'
              '${semblable.dateNaissance == null ? '' : ' · né(e) le ${dateFr(semblable.dateNaissance)}'}\n\n'
              'Un enfant ne doit avoir qu\'un seul dossier. Créer quand même un nouveau dossier ?',
          bouton: 'Créer quand même');
      if (!ok || !mounted) return;
    }
    if (!mounted) return;
    Enregistrement? cree;
    final ok = await executer(context, () async {
      cree = await s.gestion.creerEleve(_droits, identite: saisie.identite, classeId: saisie.classeId!);
    }, succes: 'Enfant ajouté.');
    if (!ok || cree == null) return;
    await _charger();
    final e = _enfants?.where((x) => x.eleveId == cree!.id).firstOrNull;
    if (e != null && mounted) await _ouvrir(e);
  }

  Future<void> _exporter(FormatRapport format) async {
    final s = ref.read(servicesProvider);
    setState(() => _occupe = true);
    try {
      final entete = await s.rapports.entete();
      if (!mounted) return;
      final enfants = _visibles;
      await exporterRapport(
          context,
          s,
          _droits,
          () => rapportVaccinationPrescolaire(enfants, _tous,
              perimetre: _perimetre, entete: entete, acteur: _droits, genereLe: DateTime.now().toUtc()),
          format,
          table: _etab == null ? 'annee_scolaire' : 'etablissement',
          id: _etab ?? _annee?.id);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Widget _marque(bool? v) => switch (v) {
        true => Icon(Icons.check, size: 18, color: Colors.green.shade700),
        false => Icon(Icons.close, size: 18, color: Colors.red.shade700),
        null => const Text('—', style: TextStyle(color: Colors.black38)),
      };

  Widget _etatPuce(EtatVaccinal e) => Chip(
        visualDensity: VisualDensity.compact,
        label: Text(e.libelle, style: const TextStyle(fontSize: 12)),
        backgroundColor: switch (e) {
          EtatVaccinal.aJour => Colors.green.shade100,
          EtatVaccinal.incomplet => Colors.orange.shade100,
          EtatVaccinal.nonRenseigne => Colors.grey.shade200,
        },
      );

  @override
  Widget build(BuildContext context) {
    final enfants = _enfants;
    final vaccins = _vaccins;
    final visibles = _visibles;
    final etabs = <String, String>{for (final e in enfants ?? const <EnfantVaccination>[]) e.etablissementId: e.etablissement};
    final classes = <String, String>{
      for (final e in enfants ?? const <EnfantVaccination>[])
        if (_etab == null || e.etablissementId == _etab) e.classeId: _etab == null ? '${e.classe} · ${e.etablissement}' : e.classe
    };
    final etats = repartitionEtats(visibles, vaccins);
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('Vaccination du préscolaire', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      const Text('Enfants de petite, moyenne et grande section et leurs vaccins du PEV et hors PEV. Cliquez sur un enfant '
          'pour noter ses vaccins (fait ou non fait), le parent ou tuteur, le carnet et les observations. Les fiches '
          'remplies sur les téléphones pendant les visites arrivent à chaque synchronisation.'),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        DropdownButton<Annee>(
          value: _annee,
          hint: const Text('Année scolaire'),
          items: [for (final a in _annees) DropdownMenuItem(value: a, child: Text(a.libelle))],
          onChanged: (a) {
            setState(() {
              _annee = a;
              _enfants = null;
            });
            _charger();
          },
        ),
        DropdownButton<String?>(
          value: _etab,
          items: [
            const DropdownMenuItem(value: null, child: Text('Tous les établissements')),
            for (final e in etabs.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() {
            _etab = v;
            _classe = null;
          }),
        ),
        DropdownButton<String?>(
          value: _classe,
          items: [
            const DropdownMenuItem(value: null, child: Text('Toutes les classes')),
            for (final c in classes.entries) DropdownMenuItem(value: c.key, child: Text(c.value)),
          ],
          onChanged: (v) => setState(() => _classe = v),
        ),
        DropdownButton<EtatVaccinal?>(
          value: _etat,
          items: [
            const DropdownMenuItem(value: null, child: Text('Tous les états')),
            for (final e in EtatVaccinal.values) DropdownMenuItem(value: e, child: Text(e.libelle)),
          ],
          onChanged: (v) => setState(() => _etat = v),
        ),
        SizedBox(
          width: 220,
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nom ou matricule', isDense: true),
            onChanged: (v) => setState(() => _texte = v),
          ),
        ),
        IconButton(tooltip: 'Actualiser', onPressed: _charger, icon: const Icon(Icons.refresh)),
      ]),
      const SizedBox(height: 12),
      if (_erreur != null)
        Text('Lecture impossible : $_erreur')
      else if (enfants == null)
        const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
      else ...[
        Wrap(children: [
          CarteIndicateur('${visibles.length}', 'Enfants',
              detail: '${visibles.where((e) => e.sexe == Sexe.masculin).length} garçons · '
                  '${visibles.where((e) => e.sexe == Sexe.feminin).length} filles',
              icone: Icons.child_care),
          CarteIndicateur('${etats[EtatVaccinal.aJour]}', 'À jour', detail: 'Vaccins obligatoires faits',
              icone: Icons.verified, couleur: Colors.green.shade700),
          CarteIndicateur('${etats[EtatVaccinal.incomplet]}', 'Incomplets',
              icone: Icons.warning_amber, couleur: Colors.orange.shade800),
          CarteIndicateur('${etats[EtatVaccinal.nonRenseigne]}', 'Non renseignés', icone: Icons.help_outline),
          CarteIndicateur(
              pourcentage(taux(etats[EtatVaccinal.aJour]!, visibles.length)), 'Enfants à jour',
              icone: Icons.donut_large, couleur: Colors.blue.shade800),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (_droits.peutGererEleves)
            FilledButton.icon(onPressed: _ajouter, icon: const Icon(Icons.person_add), label: const Text('Ajouter un enfant')),
          if (_droits.peut(Permission.parametresModifier))
            OutlinedButton.icon(
              onPressed: () async {
                if (await gererVaccins(context)) await _charger();
              },
              icon: const Icon(Icons.vaccines),
              label: const Text('Vaccins PEV et hors PEV'),
            ),
          if (_droits.peut(Permission.rapportExporterNominatif))
            for (final f in FormatRapport.values)
              OutlinedButton.icon(
                onPressed: _occupe || visibles.isEmpty ? null : () => _exporter(f),
                icon: Icon(switch (f) {
                  FormatRapport.pdf => Icons.picture_as_pdf,
                  FormatRapport.word => Icons.description,
                  FormatRapport.excel => Icons.table_chart,
                }),
                label: Text('Exporter en ${f.libelle}'),
              ),
          if (_occupe) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 8),
        Panneau(
          'Enfants et vaccins (${visibles.length})',
          enfants.isEmpty
              ? const Text('Aucun enfant du préscolaire cette année : importez la liste des classes de petite, moyenne '
                  'ou grande section, ou ajoutez les enfants.')
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 16, children: [
                    for (final p in ProgrammeVaccin.values)
                      for (final s in StatutVaccin.values)
                        if (vaccins.any((v) => v.programme == p && v.statut == s))
                          Text(
                              '${p.libelle} ${s.pluriel.toLowerCase()} : '
                              '${vaccins.where((v) => v.programme == p && v.statut == s).map((v) => v.code).join(', ')}',
                              style: TextStyle(
                                  fontSize: 12, color: p == ProgrammeVaccin.pev ? _couleurPev : _couleurHorsPev)),
                  ]),
                  const Text('✓ fait · ✗ non fait · — non renseigné. Survolez un code pour le nom du vaccin.',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      showCheckboxColumn: false,
                      columnSpacing: 14,
                      horizontalMargin: 8,
                      headingRowHeight: 40,
                      dataRowMinHeight: 30,
                      dataRowMaxHeight: 40,
                      columns: [
                        const DataColumn(label: Text('N°'), numeric: true),
                        const DataColumn(label: Text('Nom et prénoms')),
                        const DataColumn(label: Text('Sexe')),
                        const DataColumn(label: Text('Âge')),
                        const DataColumn(label: Text('Classe')),
                        if (_etab == null) const DataColumn(label: Text('Établissement')),
                        const DataColumn(label: Text('Parent ou tuteur')),
                        const DataColumn(label: Text('Carnet')),
                        for (final v in vaccins)
                          DataColumn(
                            label: Tooltip(
                              message: '${v.libelle} · ${v.programme.libelle} · ${v.statut.libelle}'
                                  '${v.cible == null ? '' : ' · ${v.cible}'}',
                              child: Text(v.code,
                                  style: TextStyle(
                                      fontWeight: v.statut == StatutVaccin.obligatoire ? FontWeight.bold : FontWeight.normal,
                                      color: v.programme == ProgrammeVaccin.pev ? _couleurPev : _couleurHorsPev)),
                            ),
                          ),
                        const DataColumn(label: Text('État')),
                      ],
                      rows: [
                        for (final (i, e) in visibles.indexed)
                          DataRow(
                            onSelectChanged: _droits.peut(Permission.visiteSaisir) ? (_) => _ouvrir(e) : null,
                            cells: [
                              DataCell(Text('${i + 1}')),
                              DataCell(Text(e.nomComplet)),
                              DataCell(Text(e.sexe.code)),
                              DataCell(Text(e.dateNaissance == null ? '' : '${calculerAge(e.dateNaissance!, DateTime.now())}')),
                              DataCell(Text(e.classe)),
                              if (_etab == null)
                                DataCell(ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 200),
                                    child: Text(e.etablissement, overflow: TextOverflow.ellipsis))),
                              DataCell(ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 200),
                                child: Text(
                                    [
                                      e.suivi?.parentTuteur ?? '',
                                      (e.suivi?.parentTelephone.isNotEmpty ?? false)
                                          ? e.suivi!.parentTelephone
                                          : (e.telephoneContact ?? ''),
                                    ]
                                        .where((x) => x.isNotEmpty)
                                        .join(' · '),
                                    overflow: TextOverflow.ellipsis),
                              )),
                              DataCell(_marque(e.suivi?.carnetPresente)),
                              for (final v in vaccins) DataCell(Center(child: _marque(e.vaccin(v.id)))),
                              DataCell(_etatPuce(etatVaccinal(e.suivi, vaccins))),
                            ],
                          ),
                      ],
                    ),
                  ),
                ]),
        ),
        if (visibles.isNotEmpty)
          Panneau(
            'Couverture par vaccin',
            tableau([
              'Vaccin', 'Programme', 'Statut', 'Faits', 'Non faits', 'Non renseignés', 'Couverture'
            ], [
              for (final c in couvertureVaccins(visibles, vaccins))
                [c.vaccin.libelle, c.vaccin.programme.libelle, c.vaccin.statut.libelle, c.faits, c.nonFaits,
                  c.nonRenseignes, pourcentage(c.tauxCouverture)]
            ]),
          ),
      ],
    ]);
  }
}

/// Fiche de vaccination d'un enfant : parent ou tuteur, carnet présenté,
/// vaccins (fait, non fait ou non renseigné), observations.
class DialogueSuiviVaccinal extends StatefulWidget {
  final EnfantVaccination enfant;
  final List<Vaccin> vaccins;
  const DialogueSuiviVaccinal({super.key, required this.enfant, required this.vaccins});
  @override
  State<DialogueSuiviVaccinal> createState() => _DialogueSuiviVaccinalState();
}

class _DialogueSuiviVaccinalState extends State<DialogueSuiviVaccinal> {
  late final SuiviVaccinal _s = widget.enfant.suivi?.copie() ??
      SuiviVaccinal(eleveId: widget.enfant.eleveId, parentTelephone: widget.enfant.telephoneContact ?? '');
  late final _parent = TextEditingController(text: _s.parentTuteur);
  late final _telephone = TextEditingController(text: _s.parentTelephone);
  late final _observations = TextEditingController(text: _s.observations);

  @override
  void dispose() {
    for (final c in [_parent, _telephone, _observations]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _choix(bool? valeur, void Function(bool?) maj, {String oui = 'Fait', String non = 'Non fait'}) =>
      SegmentedButton<bool>(
        segments: [ButtonSegment(value: true, label: Text(oui)), ButtonSegment(value: false, label: Text(non))],
        selected: {if (valeur != null) valeur},
        emptySelectionAllowed: true,
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        onSelectionChanged: (s) => setState(() => maj(s.isEmpty ? null : s.first)),
      );

  @override
  Widget build(BuildContext context) {
    final e = widget.enfant;
    final etat = etatVaccinal(_s, widget.vaccins);
    return AlertDialog(
      title: Text('Vaccination · ${e.nomComplet}'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text([
              e.sexe.libelle,
              if (e.dateNaissance != null) 'né(e) le ${dateFr(e.dateNaissance)} (${calculerAge(e.dateNaissance!, DateTime.now())})',
              '${e.classe} · ${e.etablissement}',
            ].join(' · ')),
            const SizedBox(height: 4),
            Text('État vaccinal : ${etat.libelle} (${etat.description.toLowerCase()})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _parent,
                  decoration: const InputDecoration(labelText: 'Parent ou tuteur (nom)'),
                  onChanged: (v) => _s.parentTuteur = v,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _telephone,
                  decoration: const InputDecoration(labelText: 'Téléphone du parent ou tuteur'),
                  onChanged: (v) => _s.parentTelephone = v,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(child: Text('Carnet de vaccination présenté')),
              _choix(_s.carnetPresente, (v) => _s.carnetPresente = v, oui: 'Oui', non: 'Non'),
            ]),
            for (final p in ProgrammeVaccin.values)
              for (final st in StatutVaccin.values)
                if (widget.vaccins.any((v) => v.programme == p && v.statut == st)) ...[
                  const Divider(height: 24),
                  Row(children: [
                    Expanded(
                      child: Text('${p.libelle} · vaccins ${st.pluriel.toLowerCase()}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: p == ProgrammeVaccin.pev ? _couleurPev : _couleurHorsPev)),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        for (final v in widget.vaccins.where((v) => v.programme == p && v.statut == st)) {
                          _s.vaccins[v.id] = true;
                        }
                      }),
                      child: const Text('Tous faits'),
                    ),
                  ]),
                  for (final v in widget.vaccins.where((v) => v.programme == p && v.statut == st))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(
                          child: Text.rich(TextSpan(children: [
                            TextSpan(text: v.libelle),
                            if (v.cible != null)
                              TextSpan(text: '  ${v.cible}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ])),
                        ),
                        _choix(_s.vaccins[v.id], (x) {
                          if (x == null) {
                            _s.vaccins.remove(v.id);
                          } else {
                            _s.vaccins[v.id] = x;
                          }
                        }),
                      ]),
                    ),
                ],
            const Divider(height: 24),
            TextField(
              controller: _observations,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Observations (vaccin en retard, allergie connue…)'),
              onChanged: (v) => _s.observations = v,
            ),
            if (_s.dateVerification != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Dernière vérification : ${dateFr(_s.dateVerification)}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            _s.dateVerification = DateTime.now().toUtc();
            Navigator.pop(context, _s);
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
