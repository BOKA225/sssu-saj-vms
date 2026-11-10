/// IMPORTATION DES LISTES D'ÉLÈVES : choix de la classe et du fichier,
/// aperçu du PDF, affectation des colonnes, tableau de contrôle (correction,
/// suppression, ajout de lignes, doublons), puis validation explicite.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:sssu_core/sssu_core.dart';

import '../data/requetes.dart';
import '../services.dart';
import '../ui/etablissements.dart' show formaterDateFr;
import 'lecteurs.dart';
import 'service_import.dart';

enum _Etape { choix, colonnes, controle, termine }

class EcranImport extends ConsumerStatefulWidget {
  /// Classe de destination, si l'importation est lancée depuis une classe.
  final String? classeId;
  const EcranImport({super.key, this.classeId});

  @override
  ConsumerState<EcranImport> createState() => _EcranImportState();
}

class _EcranImportState extends ConsumerState<EcranImport> {
  _Etape _etape = _Etape.choix;
  AnneeCourante? _annee;
  List<ResumeEtablissement> _etablissements = const [];
  ResumeEtablissement? _etab;
  List<ResumeClasse> _classes = const [];
  ResumeClasse? _classe;

  String? _chemin;
  String? _nomFichier;
  TableauBrut? _tableau;
  Map<int, ChampListe> _correspondance = {};
  List<LigneImport> _lignes = [];
  List<IdentiteEleve> _existants = const [];
  RegExp? _formatMatricule;
  bool _seulementAVerifier = false;

  String? _progression;
  String? _erreur;
  ResultatImport? _resultat;

  @override
  void initState() {
    super.initState();
    _initialiser();
  }

  Future<void> _initialiser() async {
    final r = ref.read(servicesProvider).requetes;
    final a = await r.anneeCourante();
    if (a == null) return;
    final etabs = await r.etablissements(a);
    final format = await r.parametre('format_matricule');
    ResumeEtablissement? etab;
    ResumeClasse? classe;
    List<ResumeClasse> classes = const [];
    if (widget.classeId != null) {
      for (final e in etabs) {
        final cs = await r.classes(e.id, a);
        final c = cs.where((c) => c.id == widget.classeId);
        if (c.isNotEmpty) {
          etab = e;
          classes = cs;
          classe = c.first;
          break;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _annee = a;
      _etablissements = etabs;
      _etab = etab;
      _classes = classes;
      _classe = classe;
      _formatMatricule = format == null || format.isEmpty ? null : RegExp(format);
    });
  }

  Future<void> _choisirEtablissement(ResumeEtablissement? e) async {
    setState(() {
      _etab = e;
      _classe = null;
      _classes = const [];
    });
    if (e == null || _annee == null) return;
    final cs = await ref.read(servicesProvider).requetes.classes(e.id, _annee!);
    if (mounted) setState(() => _classes = cs);
  }

  // ----------------------------------------------------------------- lecture

  Future<void> _choisirFichier() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: extensionsAcceptees);
    final chemin = r?.files.single.path;
    if (chemin == null) return;
    if (p.extension(chemin).toLowerCase() == '.pdf') {
      if (!mounted) return;
      final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _ApercuPdf(chemin: chemin)));
      if (ok != true) return;
    }
    await _lire(chemin, r!.files.single.name);
  }

  Future<void> _photographier() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 100, requestFullMetadata: false);
    if (x == null) return;
    await _lire(x.path, 'photo_liste_${formaterDate(DateTime.now())}.jpg', supprimerApres: true);
  }

  Future<void> _lire(String chemin, String nom, {bool supprimerApres = false}) async {
    setState(() {
      _erreur = null;
      _progression = 'Lecture du fichier…';
    });
    try {
      final t = await lireListe(chemin, progression: (etape, _) {
        if (mounted) setState(() => _progression = etape);
      });
      if (t.lignes.isEmpty) throw const ErreurImport('Aucune donnée trouvée dans ce fichier.');
      _existants = await ref.read(servicesProvider).requetes.identitesEleves();
      setState(() {
        _chemin = chemin;
        _nomFichier = nom;
        _tableau = t;
        _correspondance = Map.of(t.correspondance);
        _etape = _Etape.colonnes;
        _progression = null;
      });
      if (supprimerApres) _supprimerApresImport = chemin;
    } on ErreurImport catch (e) {
      setState(() {
        _erreur = e.message;
        _progression = null;
      });
    } catch (e) {
      setState(() {
        _erreur = 'Lecture impossible : $e';
        _progression = null;
      });
    }
  }

  /// Photo prise par l'appareil : effacée après l'importation (le fichier
  /// source est conservé chiffré dans l'application).
  String? _supprimerApresImport;

  void _analyser() {
    final t = _tableau!.avecCorrespondance(_correspondance);
    final lignes = analyserTableau(t, formatMatricule: _formatMatricule);
    _controler(lignes);
    setState(() {
      _lignes = lignes;
      _etape = _Etape.controle;
    });
  }

  void _controler([List<LigneImport>? lignes]) => controlerLignes(
        lignes ?? _lignes,
        existants: _existants,
        dateReference: DateTime.now().toUtc(),
        formatMatricule: _formatMatricule,
      );

  // ------------------------------------------------------------- correction

  Future<void> _editer(LigneImport? ligne) async {
    final l = ligne ??
        LigneImport(
            numeroSource: (_lignes.isEmpty ? 0 : _lignes.map((x) => x.numeroSource).reduce((a, b) => a > b ? a : b)) + 1,
            brut: {},
            nom: '',
            prenoms: '');
    final mat = TextEditingController(text: l.matricule ?? '');
    final nom = TextEditingController(text: l.nom);
    final prenoms = TextEditingController(text: l.prenoms);
    final date = TextEditingController(text: l.dateNaissance == null ? '' : formaterDateFr(l.dateNaissance!));
    final tel = TextEditingController(text: l.telephone ?? '');
    Sexe? sexe = l.sexe;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, maj) => AlertDialog(
          title: Text(ligne == null ? 'Ajouter un élève' : 'Ligne ${l.numeroSource}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (l.brut.isNotEmpty)
                Text('Lu dans le fichier : ${l.brut.values.join(' | ')}', style: const TextStyle(fontSize: 12)),
              TextField(controller: mat, decoration: const InputDecoration(labelText: 'Matricule')),
              TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom')),
              TextField(controller: prenoms, decoration: const InputDecoration(labelText: 'Prénoms')),
              TextField(controller: date, decoration: const InputDecoration(labelText: 'Date de naissance (JJ/MM/AAAA)')),
              TextField(controller: tel, decoration: const InputDecoration(labelText: 'Téléphone'), keyboardType: TextInputType.phone),
              const SizedBox(height: 8),
              SegmentedButton<Sexe>(
                emptySelectionAllowed: true,
                segments: [for (final s in Sexe.values) ButtonSegment(value: s, label: Text(s.libelle))],
                selected: {if (sexe != null) sexe!},
                onSelectionChanged: (s) => maj(() => sexe = s.isEmpty ? null : s.first),
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
    if (ok == true) {
      l
        ..matricule = normaliserMatricule(mat.text)
        ..nom = nom.text.trim().toUpperCase()
        ..prenoms = prenoms.text.trim()
        ..dateNaissance = lireDateListe(date.text)
        ..telephone = lireTelephone(tel.text)
        ..sexe = sexe;
      if (ligne == null) _lignes.add(l);
      _controler();
      setState(() {});
    }
    for (final t in [mat, nom, prenoms, date, tel]) {
      t.dispose();
    }
  }

  Future<void> _choisirAction(LigneImport l, ActionImport a) async {
    if (a == ActionImport.rattacher && l.eleveExistantId == null) {
      final choix = await _choisirDossierExistant(l);
      if (choix == null) return;
      l.imposerAction(a, eleveId: choix);
    } else {
      l.imposerAction(a);
    }
    _controler();
    setState(() {});
  }

  Future<String?> _choisirDossierExistant(LigneImport l) async {
    final n = normaliserTexte(l.nom);
    final proches = _existants.where((e) => e.id != null && normaliserTexte(e.nom) == n).toList();
    return showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Rattacher à quel dossier ?'),
        children: [
          if (proches.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucun élève de même nom.')),
          for (final e in proches)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, e.id),
              child: Text('${e.nom} ${e.prenoms}${e.matricule == null ? '' : ' · ${e.matricule}'}'
                  '${e.dateNaissance == null ? '' : ' · ${formaterDateFr(e.dateNaissance!)}'}'),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- validation

  Future<void> _valider() async {
    final b = bilan(_lignes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirmer l\'importation'),
        content: Text('Classe : ${_classe!.libelle}\n'
            '${b.aCreer} nouveaux élèves, ${b.aRattacher} déjà connus rattachés, ${b.ignorees} lignes non importées.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Revenir au contrôle')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Importer')),
        ],
      ),
    );
    if (ok != true) return;
    final s = ref.read(servicesProvider);
    setState(() => _progression = 'Enregistrement…');
    try {
      final r = await ServiceImport(s.base, s.depot, s.fichiers).enregistrer(
        lignes: _lignes,
        classe: ClasseCible(_classe!.id, _classe!.etablissementId, _classe!.anneeScolaireId),
        tableau: _tableau!.avecCorrespondance(_correspondance),
        nomFichier: _nomFichier!,
        octetsSource: await File(_chemin!).readAsBytes(),
        utilisateurId: ref.read(sessionProvider)!.utilisateur.id,
      );
      if (_supprimerApresImport != null) await File(_supprimerApresImport!).delete();
      setState(() {
        _resultat = r;
        _etape = _Etape.termine;
        _progression = null;
      });
    } on ErreurImport catch (e) {
      setState(() {
        _erreur = e.message;
        _progression = null;
      });
    }
  }

  // ------------------------------------------------------------------- écrans

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importation des listes d\'élèves')),
      body: _progression != null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(_progression!),
              ]),
            )
          : switch (_etape) {
              _Etape.choix => _ecranChoix(),
              _Etape.colonnes => _ecranColonnes(),
              _Etape.controle => _ecranControle(),
              _Etape.termine => _ecranTermine(),
            },
      bottomNavigationBar: _etape == _Etape.controle && _progression == null ? _barreValidation() : null,
    );
  }

  Widget _erreurAffichee() => _erreur == null
      ? const SizedBox.shrink()
      : Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(padding: const EdgeInsets.all(12), child: Text(_erreur!)),
        );

  Widget _ecranChoix() => ListView(padding: const EdgeInsets.all(16), children: [
        _erreurAffichee(),
        DropdownButtonFormField<ResumeEtablissement>(
          value: _etab,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Établissement'),
          items: [for (final e in _etablissements) DropdownMenuItem(value: e, child: Text(e.nom))],
          onChanged: _choisirEtablissement,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ResumeClasse>(
          value: _classe,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'Classe (${_annee?.libelle ?? ''})'),
          items: [for (final c in _classes) DropdownMenuItem(value: c, child: Text('${c.libelle} · ${c.effectif} élèves'))],
          onChanged: (c) => setState(() => _classe = c),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _classe == null ? null : _choisirFichier,
          icon: const Icon(Icons.folder_open),
          label: const Text('IMPORTER UN FICHIER (Excel, CSV, PDF)'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _classe == null ? null : _photographier,
          icon: const Icon(Icons.document_scanner),
          label: const Text('PHOTOGRAPHIER UNE LISTE PAPIER'),
        ),
        const SizedBox(height: 16),
        const Text('Les PDF scannés et les photos sont lus par reconnaissance de texte sur le téléphone, sans '
            'Internet. Aucune donnée n\'est enregistrée avant votre validation.'),
      ]);

  Widget _ecranColonnes() {
    final t = _tableau!;
    final debut = t.ligneEntete ?? -1;
    final apercu = t.lignes.skip(debut + 1).take(4).toList();
    final aNom = _correspondance.values.any((c) => c.estNom);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(t.ligneEntete == null
          ? 'Les intitulés des colonnes n\'ont pas été reconnus : indiquez le contenu de chaque colonne.'
          : 'Colonnes reconnues automatiquement : vérifiez et corrigez si nécessaire.'),
      const SizedBox(height: 12),
      for (var col = 0; col < t.nombreColonnes; col++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                [
                  if (t.ligneEntete != null && col < t.lignes[t.ligneEntete!].length) '« ${t.lignes[t.ligneEntete!][col]} »',
                  'ex. : ${apercu.map((l) => col < l.length ? l[col] : '').where((v) => v.isNotEmpty).take(3).join(' / ')}',
                ].join('  '),
                style: const TextStyle(fontSize: 13),
              ),
              DropdownButton<ChampListe>(
                isExpanded: true,
                value: _correspondance[col] ?? ChampListe.ignorer,
                items: [for (final c in ChampListe.values) DropdownMenuItem(value: c, child: Text(c.libelle))],
                onChanged: (c) => setState(() {
                  if (c == null || c == ChampListe.ignorer) {
                    _correspondance.remove(col);
                  } else {
                    _correspondance[col] = c;
                  }
                }),
              ),
            ]),
          ),
        ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: aNom ? _analyser : null,
        child: Text(aNom ? 'Analyser la liste' : 'Indiquez au moins la colonne du nom'),
      ),
      TextButton(onPressed: () => setState(() => _etape = _Etape.choix), child: const Text('Choisir un autre fichier')),
    ]);
  }

  Widget _ecranControle() {
    final visibles = [
      for (final l in _lignes)
        if (!_seulementAVerifier || l.aVerifier || l.action != ActionImport.creer) l
    ];
    return Column(children: [
      _erreurAffichee(),
      SwitchListTile(
        title: const Text('Seulement les lignes à vérifier'),
        value: _seulementAVerifier,
        onChanged: (v) => setState(() => _seulementAVerifier = v),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: visibles.length + 1,
          itemBuilder: (c, i) {
            if (i == visibles.length) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                    onPressed: () => _editer(null),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Ajouter un élève manquant')),
              );
            }
            return _carteLigne(visibles[i]);
          },
        ),
      ),
    ]);
  }

  Widget _carteLigne(LigneImport l) {
    final couleur = l.action == ActionImport.ignorer
        ? Colors.grey.shade200
        : l.bloquee
            ? Colors.red.shade50
            : l.aVerifier
                ? Colors.orange.shade50
                : null;
    return Card(
      color: couleur,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${l.numeroSource}. ${l.nom} ${l.prenoms}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration: l.action == ActionImport.ignorer ? TextDecoration.lineThrough : null)),
            ),
            IconButton(icon: const Icon(Icons.edit), tooltip: 'Corriger', onPressed: () => _editer(l)),
          ]),
          Text([
            l.matricule ?? 'sans matricule',
            l.sexe?.libelle ?? 'sexe ?',
            l.dateNaissance == null ? 'date ?' : formaterDateFr(l.dateNaissance!),
            if (l.telephone != null) l.telephone!,
          ].join(' · ')),
          for (final a in l.anomalies)
            Text('${a.gravite == GraviteAnomalie.bloquante ? '⛔' : '⚠'} ${a.message}',
                style: TextStyle(color: a.gravite == GraviteAnomalie.bloquante ? Colors.red.shade800 : Colors.orange.shade900)),
          for (final n in l.notes) Text('ℹ $n', style: const TextStyle(fontSize: 12)),
          DropdownButton<ActionImport>(
            value: l.action,
            items: [for (final a in ActionImport.values) DropdownMenuItem(value: a, child: Text(a.libelle))],
            onChanged: (a) => a == null ? null : _choisirAction(l, a),
          ),
        ]),
      ),
    );
  }

  Widget _barreValidation() {
    final b = bilan(_lignes);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${b.aCreer} nouveaux · ${b.aRattacher} rattachés · ${b.ignorees} non importés'
              '${b.bloquees == 0 ? '' : ' · ${b.bloquees} en erreur'}'),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: b.validable ? _valider : null,
            child: Text(b.validable ? 'VALIDER L\'IMPORTATION' : 'Corrigez les lignes en erreur'),
          ),
        ]),
      ),
    );
  }

  Widget _ecranTermine() {
    final r = _resultat!;
    return ListView(padding: const EdgeInsets.all(24), children: [
      const Icon(Icons.check_circle, color: Colors.green, size: 64),
      const SizedBox(height: 12),
      Text('Importation terminée dans la classe ${_classe!.libelle}.', style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 12),
      Text('${r.crees} nouveaux dossiers créés\n${r.rattaches} élèves déjà connus rattachés\n'
          '${r.changementsDeClasse} changements de classe\n${r.ignores} lignes non importées'),
      const SizedBox(height: 12),
      const Text('Les élèves sont disponibles pour les visites. Ils seront transmis au poste central à la '
          'prochaine synchronisation.'),
      const SizedBox(height: 24),
      FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Terminer')),
    ]);
  }
}

/// Aperçu d'un PDF avant extraction.
class _ApercuPdf extends StatelessWidget {
  final String chemin;
  const _ApercuPdf({required this.chemin});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(p.basename(chemin))),
        body: PdfViewer.file(chemin),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Extraire les élèves')),
          ),
        ),
      );
}
