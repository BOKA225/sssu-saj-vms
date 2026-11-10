/// Menu INSPECTION SANITAIRE DES ÉTABLISSEMENTS SCOLAIRES : choix de
/// l'établissement, historique des inspections faites sur ce téléphone, et
/// grille d'inspection (critères par rubrique, observations, recommandations,
/// photos des insuffisances, signature de l'inspecteur).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sssu_core/sssu_core.dart';

import '../data/requetes.dart';
import '../services.dart';
import '../ui/etablissements.dart' show formaterDateFr;
import 'depot_inspection.dart';
import 'signature.dart';

DepotInspection _depotDe(WidgetRef ref) {
  final s = ref.read(servicesProvider);
  return DepotInspection(s.base, s.depot, s.fichiers);
}

Color couleurNiveau(NiveauConformite? n) => switch (n) {
      NiveauConformite.satisfaisant => Colors.green.shade700,
      NiveauConformite.moyen => Colors.orange.shade800,
      NiveauConformite.insuffisant => Colors.red.shade700,
      null => Colors.grey,
    };

String libelleEtat(StatutInspection s, EtatSync e) {
  if (e == EtatSync.conflit) return 'À vérifier (refusée par le poste)';
  if (s == StatutInspection.ebauche) return 'Ébauche (sur le téléphone)';
  return switch (e) {
    EtatSync.enAttente => 'En attente de synchronisation',
    EtatSync.synchronise => 'Transmise au poste central',
    _ => s.libelle,
  };
}

// ------------------------------------------------------------ établissements

class EcranInspections extends ConsumerStatefulWidget {
  const EcranInspections({super.key});
  @override
  ConsumerState<EcranInspections> createState() => _EcranInspectionsState();
}

class _EcranInspectionsState extends ConsumerState<EcranInspections> {
  AnneeCourante? _annee;
  List<ResumeEtablissement>? _etabs;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final r = ref.read(servicesProvider).requetes;
    final a = await r.anneeCourante();
    final l = a == null ? <ResumeEtablissement>[] : await r.etablissements(a);
    if (mounted) {
      setState(() {
        _annee = a;
        _etabs = l;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Inspection sanitaire')),
        body: _etabs == null
            ? const Center(child: CircularProgressIndicator())
            : _etabs!.isEmpty || _annee == null
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Aucun établissement sur ce téléphone. Synchronisez avec le poste central.'))
                : ListView(padding: const EdgeInsets.all(8), children: [
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('INSPECTION SANITAIRE DES ÉTABLISSEMENTS SCOLAIRES',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    for (final e in _etabs!)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.fact_check),
                          title: Text(e.nom),
                          subtitle: Text(e.localite ?? e.code),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => EcranHistoriqueInspections(etablissement: e, annee: _annee!))),
                        ),
                      ),
                  ]),
      );
}

// --------------------------------------------------------------- historique

class EcranHistoriqueInspections extends ConsumerStatefulWidget {
  final ResumeEtablissement etablissement;
  final AnneeCourante annee;
  const EcranHistoriqueInspections({super.key, required this.etablissement, required this.annee});
  @override
  ConsumerState<EcranHistoriqueInspections> createState() => _EcranHistoriqueInspectionsState();
}

class _EcranHistoriqueInspectionsState extends ConsumerState<EcranHistoriqueInspections> {
  List<ResumeInspection>? _liste;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final l = await _depotDe(ref).inspections(widget.etablissement.id);
    if (mounted) setState(() => _liste = l);
  }

  Future<void> _ouvrir({String? inspectionId}) async {
    final session = ref.read(sessionProvider)!;
    final depot = _depotDe(ref);
    try {
      final d = inspectionId == null
          ? await depot.nouvelle(
              etablissementId: widget.etablissement.id,
              anneeScolaireId: widget.annee.id,
              inspecteurId: session.utilisateur.id,
              date: DateTime.now().toUtc())
          : await depot.charger(inspectionId);
      if (!mounted) return;
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => EcranInspection(dossier: d, etablissement: widget.etablissement.nom)));
    } on StateError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    final peut = ref.read(sessionProvider)!.droits.peut(Permission.inspectionRealiser);
    return Scaffold(
      appBar: AppBar(title: Text(widget.etablissement.nom)),
      floatingActionButton: peut
          ? FloatingActionButton.extended(
              onPressed: () => _ouvrir(), icon: const Icon(Icons.add), label: const Text('Nouvelle inspection'))
          : null,
      body: _liste == null
          ? const Center(child: CircularProgressIndicator())
          : _liste!.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Aucune inspection sur ce téléphone pour cet établissement. '
                      'L\'historique complet se consulte sur le poste central.'))
              : ListView(padding: const EdgeInsets.fromLTRB(8, 8, 8, 80), children: [
                  for (final i in _liste!)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: couleurNiveau(i.niveau),
                          child: Text(i.taux == null ? '–' : '${i.taux!.round()}',
                              style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                        title: Text('Inspection du ${formaterDateFr(i.date)}'),
                        subtitle: Text('${i.niveau?.libelle ?? 'Taux non calculé'} · ${libelleEtat(i.statut, i.etat)}'
                            '${i.inspecteur == null || i.inspecteur!.isEmpty ? '' : '\n${i.inspecteur}'}'),
                        isThreeLine: i.inspecteur != null && i.inspecteur!.isNotEmpty,
                        onTap: () => _ouvrir(inspectionId: i.id),
                      ),
                    ),
                ]),
    );
  }
}

// ------------------------------------------------------------------- grille

class EcranInspection extends ConsumerStatefulWidget {
  final DossierInspection dossier;
  final String etablissement;
  const EcranInspection({super.key, required this.dossier, required this.etablissement});
  @override
  ConsumerState<EcranInspection> createState() => _EcranInspectionState();
}

class _EcranInspectionState extends ConsumerState<EcranInspection> with WidgetsBindingObserver {
  late final DepotInspection _depot = _depotDe(ref);
  late final TextEditingController _observations = TextEditingController(text: _f.observations);
  late final TextEditingController _recommandations = TextEditingController(text: _f.recommandations);
  final Map<String, TextEditingController> _obsCriteres = {};
  SeuilsConformite _seuils = const SeuilsConformite();
  Timer? _minuterie;
  bool _modifie = false;
  bool _occupe = false;
  String? _sauvegarde;

  /// Incrémenté après l'ajout d'une photo : recharge les vignettes.
  int _versionPhotos = 0;

  FormulaireInspection get _f => widget.dossier.formulaire;
  String get _utilisateur => ref.read(sessionProvider)!.utilisateur.id;
  bool get _modifiable => _f.modifiable && ref.read(sessionProvider)!.droits.peut(Permission.inspectionRealiser);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final c in _f.criteres) {
      _obsCriteres[c.id] = TextEditingController(text: _f.reponses[c.id]?.observation ?? '');
    }
    _depot.seuils().then((s) {
      if (mounted) setState(() => _seuils = s);
    });
    _minuterie = Timer.periodic(const Duration(seconds: 30), (_) => _sauver(silencieux: true));
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _observations.dispose();
    _recommandations.dispose();
    for (final c in _obsCriteres.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) _sauver(silencieux: true);
  }

  void _lireChamps() {
    _f.observations = _observations.text;
    _f.recommandations = _recommandations.text;
    for (final e in _obsCriteres.entries) {
      _f.reponses[e.key]?.observation = e.value.text;
    }
  }

  Future<void> _sauver({bool silencieux = false}) async {
    if (!_modifiable || _occupe || (silencieux && !_modifie)) return;
    _occupe = true;
    try {
      _lireChamps();
      await _depot.enregistrer(widget.dossier, utilisateurId: _utilisateur);
      _modifie = false;
      final m = TimeOfDay.now();
      if (mounted) setState(() => _sauvegarde = 'Ébauche enregistrée à ${m.hour}:${m.minute.toString().padLeft(2, '0')}');
    } finally {
      _occupe = false;
    }
  }

  void _changer(VoidCallback f) => setState(() {
        f();
        _modifie = true;
      });

  Future<void> _transmettre() async {
    _lireChamps();
    final c = controlerInspection(_f);
    if (!c.transmissible) {
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Inspection incomplète'),
          content: Text(c.erreurs.join('\n')),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Compléter'))],
        ),
      );
      return;
    }
    final r = _f.resultat(_seuils);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Enregistrer et transmettre ?'),
        content: Text([
          'Taux de conformité : ${pourcentage(r.taux)} (${r.niveau?.libelle ?? 'non calculé'}).',
          if (c.avertissements.isNotEmpty) '\nÀ vérifier :\n• ${c.avertissements.join('\n• ')}',
          '\nL\'inspection ne sera plus modifiable sur le téléphone.',
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Revenir')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Transmettre')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _occupe = true);
    try {
      await _depot.transmettre(widget.dossier, utilisateurId: _utilisateur);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inspection enregistrée : elle partira à la prochaine synchronisation.')));
      Navigator.pop(context);
    } on StateError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _supprimer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Supprimer cette ébauche ?'),
        content: const Text('Les réponses et les photos de cette inspection seront effacées du téléphone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    _modifie = false;
    await _depot.supprimerEbauche(widget.dossier, utilisateurId: _utilisateur);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _signer() async {
    final controleur = ControleurSignature();
    final png = await showDialog<Uint8List>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Signature de l\'inspecteur'),
        content: SizedBox(width: 400, child: ZoneSignature(controleur: controleur)),
        actions: [
          TextButton(onPressed: controleur.effacer, child: const Text('Effacer')),
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              final p = await controleur.versPng();
              if (d.mounted) Navigator.pop(d, p);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    controleur.dispose();
    if (png != null) _changer(() => _f.signaturePng = png);
  }

  Future<void> _photo(CritereGrille c) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (d) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Photographiez l\'insuffisance, sans élève ni personne reconnaissable.'),
          ),
          ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(d, ImageSource.camera)),
          ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(d, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    // La photo est rattachée à la réponse : celle-ci doit être enregistrée.
    _modifie = true;
    await _sauver();
    try {
      await _depot.ajouterPhoto(source: source, d: widget.dossier, critereId: c.id, auteurId: _utilisateur);
      if (mounted) setState(() => _versionPhotos++);
    } on StateError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _critere(CritereGrille c) {
    final r = _f.reponses[c.id]!;
    final insuffisance = r.resultat == ResultatInspection.nonConforme || r.resultat == ResultatInspection.partiel;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.libelle, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final x in ResultatInspection.values)
            ChoiceChip(
              label: Text(x.libelle, style: const TextStyle(fontSize: 12)),
              selected: r.resultat == x,
              selectedColor: switch (x) {
                ResultatInspection.conforme => Colors.green.shade100,
                ResultatInspection.partiel => Colors.orange.shade100,
                ResultatInspection.nonConforme => Colors.red.shade100,
                ResultatInspection.nonApplicable => Colors.grey.shade300,
              },
              onSelected: _modifiable ? (s) => _changer(() => r.resultat = s ? x : null) : null,
            ),
        ]),
        if (insuffisance || (_obsCriteres[c.id]?.text.isNotEmpty ?? false))
          TextField(
            controller: _obsCriteres[c.id],
            enabled: _modifiable,
            decoration: const InputDecoration(labelText: 'Observation', isDense: true),
            maxLines: null,
            onChanged: (_) => _modifie = true,
          ),
        if (insuffisance && widget.dossier.idsReponses[c.id] != null) _PhotosCritere(
          key: ValueKey('${c.id}-$_versionPhotos'),
          depot: _depot,
          dossier: widget.dossier,
          critere: c,
          modifiable: _modifiable,
          onAjouter: () => _photo(c),
        ) else if (insuffisance && _modifiable)
          TextButton.icon(
              onPressed: () => _photo(c), icon: const Icon(Icons.add_a_photo), label: const Text('Photo de l\'insuffisance')),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _f.resultat(_seuils);
    final grille = _f.parRubrique;
    final session = ref.read(sessionProvider)!;
    return PopScope(
      onPopInvokedWithResult: (pop, _) {
        if (pop) _sauver(silencieux: true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Inspection · ${widget.etablissement}'),
          actions: [
            if (_modifiable && _f.id != null)
              IconButton(tooltip: 'Supprimer l\'ébauche', onPressed: _supprimer, icon: const Icon(Icons.delete_outline)),
            if (_modifiable) IconButton(tooltip: 'Enregistrer', onPressed: () => _sauver(), icon: const Icon(Icons.save)),
          ],
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Date : ${formaterDateFr(_f.dateInspection)}')),
                  if (_modifiable)
                    TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                            context: context,
                            initialDate: _f.dateInspection,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now());
                        if (d != null) _changer(() => _f.dateInspection = DateTime.utc(d.year, d.month, d.day));
                      },
                      child: const Text('Modifier'),
                    ),
                ]),
                Text('Inspecteur : ${session.utilisateur.id == _f.inspecteurId ? session.utilisateur.nomAffiche : 'autre agent'}'),
                Text(libelleEtat(_f.statut, widget.dossier.etat)),
                if (_sauvegarde != null) Text(_sauvegarde!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ]),
            ),
          ),
          Card(
            color: couleurNiveau(r.niveau).withOpacity(0.08),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Conformité : ${pourcentage(r.taux)}${r.niveau == null ? '' : ' · ${r.niveau!.libelle}'}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: couleurNiveau(r.niveau))),
                Text('${r.conformes} conforme(s) · ${r.partiels} partiel(s) · ${r.nonConformes} non conforme(s) · '
                    '${r.nonApplicables} non applicable(s)'),
                Text('${_f.nombreRepondus} / ${_f.criteres.length} critères renseignés',
                    style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
          for (final MapEntry(key: rub, value: criteres) in grille.entries)
            Card(
              child: ExpansionTile(
                title: Text(rub.libelle),
                subtitle: Text(
                    '${rub.elements} · ${criteres.where((c) => _f.reponses[c.id]!.resultat != null).length}/${criteres.length}'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [for (final c in criteres) _critere(c)],
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _observations,
            enabled: _modifiable,
            decoration: const InputDecoration(labelText: 'Observations', border: OutlineInputBorder()),
            maxLines: 4,
            onChanged: (_) => _modifie = true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _recommandations,
            enabled: _modifiable,
            decoration: const InputDecoration(labelText: 'Recommandations', border: OutlineInputBorder()),
            maxLines: 4,
            onChanged: (_) => _modifie = true,
          ),
          const SizedBox(height: 12),
          const Text('Signature de l\'inspecteur', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            height: 120,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26)),
            alignment: Alignment.center,
            child: _f.signaturePng == null
                ? const Text('Pas encore signée', style: TextStyle(color: Colors.black38))
                : Image.memory(Uint8List.fromList(_f.signaturePng!), fit: BoxFit.contain),
          ),
          if (_modifiable)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _signer,
                icon: const Icon(Icons.draw),
                label: Text(_f.signaturePng == null ? 'Signer' : 'Signer à nouveau'),
              ),
            ),
        ]),
        bottomNavigationBar: _modifiable
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    onPressed: _occupe ? null : _transmettre,
                    icon: const Icon(Icons.send),
                    label: const Text('ENREGISTRER ET TRANSMETTRE'),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _PhotosCritere extends StatefulWidget {
  final DepotInspection depot;
  final DossierInspection dossier;
  final CritereGrille critere;
  final bool modifiable;
  final VoidCallback onAjouter;
  const _PhotosCritere(
      {super.key,
      required this.depot, required this.dossier, required this.critere, required this.modifiable, required this.onAjouter});
  @override
  State<_PhotosCritere> createState() => _PhotosCritereState();
}

class _PhotosCritereState extends State<_PhotosCritere> {
  List<(Enregistrement, Uint8List?)>? _photos;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final id = widget.dossier.idsReponses[widget.critere.id];
    if (id == null) return;
    final l = [for (final p in await widget.depot.photos(id)) (p, await widget.depot.lirePhoto(p))];
    if (mounted) setState(() => _photos = l);
  }

  @override
  Widget build(BuildContext context) {
    final l = _photos ?? const [];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final (p, image) in l)
          SizedBox(
            width: 72,
            height: 72,
            child: image == null
                ? const ColoredBox(
                    color: Colors.black12,
                    child: Center(
                        child: Text('Transférée', textAlign: TextAlign.center, style: TextStyle(fontSize: 10))))
                : GestureDetector(
                    onLongPress: widget.modifiable
                        ? () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (d) => AlertDialog(
                                title: const Text('Supprimer cette photo ?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Non')),
                                  FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Supprimer')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await widget.depot.supprimerPhoto(p, utilisateurId: widget.dossier.formulaire.inspecteurId);
                              _charger();
                            }
                          }
                        : null,
                    child: Image.memory(image, fit: BoxFit.cover),
                  ),
          ),
        if (widget.modifiable)
          IconButton(onPressed: widget.onAjouter, icon: const Icon(Icons.add_a_photo), tooltip: 'Photo de l\'insuffisance'),
      ]),
    );
  }
}
