/// IMPORTATION DES LISTES D'ÉLÈVES sur le poste central : même analyse et
/// mêmes contrôles que sur le téléphone, validation explicite obligatoire.
///
/// Un fichier peut contenir plusieurs classes : une feuille Excel par classe,
/// ou une colonne « Classe ». Chaque partie est alors rapprochée d'une classe
/// de l'établissement (ou créée), puis tout est importé en une seule fois.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sssu_core/sssu_core.dart';

import '../donnees/requetes_poste.dart';
import '../import/lecteurs_poste.dart';
import '../services.dart';
import 'commun.dart';

/// Partie du fichier destinée à une classe, après analyse.
class _Partie {
  final GroupeClasse source;
  final List<LigneImport> lignes;

  /// Classe de destination (null : à choisir ou à créer).
  String? classeId;

  /// Faux : partie écartée de l'importation.
  bool importer = true;
  _Partie(this.source, this.lignes);
}

class PageImport extends ConsumerStatefulWidget {
  const PageImport({super.key});
  @override
  ConsumerState<PageImport> createState() => _PageImportState();
}

class _PageImportState extends ConsumerState<PageImport> {
  Annee? _annee;
  List<LigneEtablissement> _etabs = const [];
  String? _etab;
  List<LigneClasse> _classes = const [];

  /// Classe de destination d'un fichier d'une seule classe.
  String? _classe;
  String? _chemin;

  /// Listes lues : une par feuille utile d'un classeur, sinon une seule.
  List<TableauBrut> _tableaux = const [];
  List<Map<int, ChampListe>> _correspondances = const [];

  /// Feuille dont les colonnes sont affichées.
  int _feuille = 0;

  /// Parties analysées (une par classe du fichier).
  List<_Partie>? _parties;
  List<IdentiteEleve> _existants = const [];
  List<ClasseConnue> _classesAnnee = const [];
  String? _progression;
  String? _erreur;

  /// Établissement (et classe, pour un fichier d'une seule classe) proposés
  /// d'après les titres, le nom des feuilles et le nom du fichier.
  ReconnaissanceListe? _reconnaissance;

  ServicesPoste get _s => ref.read(servicesProvider);
  Droits get _droits => ref.read(sessionProvider)!.droits;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final a = await _s.requetes.anneeCourante();
    if (a == null) return;
    final e = await _s.requetes.etablissements(a);
    if (mounted) {
      setState(() {
        _annee = a;
        _etabs = e;
      });
    }
  }

  // ---------------------------------------------------------------- état

  List<TableauBrut> get _tableauxCourants =>
      [for (var i = 0; i < _tableaux.length; i++) _tableaux[i].avecCorrespondance(_correspondances[i])];

  /// Classes du fichier d'après les colonnes affectées (avant l'analyse).
  List<GroupeClasse> get _groupesPrevus => _tableaux.isEmpty ? const [] : grouperParClasse(_tableauxCourants);

  bool get _plusieurs => _parties != null ? _parties!.length > 1 : _groupesPrevus.length > 1;

  /// Lignes à importer : celles des parties retenues.
  List<LigneImport> get _lignes => [
        for (final pa in _parties ?? const <_Partie>[])
          if (pa.importer || !_plusieurs) ...pa.lignes
      ];

  List<ClasseConnue> get _classesEtab => [
        for (final c in _classes) ClasseConnue(id: c.id, etablissementId: _etab ?? '', libelle: c.libelle, niveau: c.niveau)
      ];

  List<EtablissementConnu> get _etabsConnus => [
        for (final e in _etabs)
          EtablissementConnu(id: e.id, nom: e.nom, code: '${e.donnees['code'] ?? ''}', localite: e.donnees['localite'] as String?)
      ];

  String _nomClasse(String? id) => _classes.where((c) => c.id == id).firstOrNull?.libelle ?? '';

  Future<void> _choisirEtab(String? id) async {
    setState(() {
      _etab = id;
      _classe = null;
      _classes = const [];
    });
    if (id == null) return;
    final c = await _s.requetes.classes(id, _annee!);
    if (!mounted) return;
    setState(() {
      _classes = c;
      if (_parties != null && _plusieurs) _proposerClasses();
    });
  }

  Future<void> _rechargerClasses() async {
    if (_etab == null || _annee == null) return;
    final c = await _s.requetes.classes(_etab!, _annee!);
    final toutes = await _s.requetes.classesDeLAnnee(_annee!);
    if (mounted) {
      setState(() {
        _classes = c;
        _classesAnnee = toutes;
      });
    }
  }

  // -------------------------------------------------------------- lecture

  Future<void> _choisirFichier() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: extensionsListes);
    final chemin = r?.files.single.path;
    if (chemin == null) return;
    setState(() {
      _erreur = null;
      _progression = 'Lecture du fichier…';
      _parties = null;
    });
    try {
      final tableaux = await _s.lecteur.lireTableaux(chemin, progression: (etape) {
        if (mounted) setState(() => _progression = etape);
      });
      final existants = await _s.depot.transaction((tx) => tx.chercher('eleve', const {}));
      _classesAnnee = await _s.requetes.classesDeLAnnee(_annee!);
      setState(() {
        _chemin = chemin;
        _tableaux = tableaux;
        _correspondances = [for (final t in tableaux) Map.of(t.correspondance)];
        _feuille = 0;
        _existants = [
          for (final e in existants)
            IdentiteEleve(
              id: e.id,
              matricule: e.donnees['matricule'] as String?,
              nom: e.donnees['nom']! as String,
              prenoms: e.donnees['prenoms']! as String,
              dateNaissance: e.donnees['date_naissance'] == null ? null : lireDate(e.donnees['date_naissance']! as String),
            ),
        ];
        _progression = null;
      });
      await _reconnaitre();
    } on ErreurLecture catch (e) {
      setState(() {
        _erreur = e.message;
        _progression = null;
      });
    }
  }

  /// Propose l'établissement, et la classe d'un fichier d'une seule classe ;
  /// la proposition est appliquée si rien n'a encore été choisi.
  Future<void> _reconnaitre() async {
    final groupes = _groupesPrevus;
    if (groupes.isEmpty) return;
    final plusieurs = groupes.length > 1;
    final premier = groupes.first;
    final reco = reconnaitreListe(
      titres: plusieurs
          ? {for (final t in _tableaux) ...t.titres}.toList()
          : {...premier.indices, ...premier.tableau.titres}.toList(),
      nomFichier: p.basename(_chemin!),
      etablissements: _etabsConnus,
      classes: _classesAnnee,
      classeLue: plusieurs ? null : premier.classeLue,
      lireLaClasse: !plusieurs,
    );
    if (_etab == null && reco.etablissement != null) {
      await _choisirEtab(reco.etablissement!.id);
      if (reco.classe != null) _classe = reco.classe!.id;
    } else if (_etab != null && _etab == reco.etablissement?.id && _classe == null && reco.classe != null) {
      _classe = reco.classe!.id;
    } else if (_etab != null && _classe == null && reco.classeLue != null) {
      // Établissement déjà choisi : la classe lue y est cherchée.
      _classe = rapprocherClasse(reco.classeLue!, _etab!, _classesEtab)?.id;
    }
    if (mounted) setState(() => _reconnaissance = reco);
  }

  /// Applique la proposition (établissement et classe).
  Future<void> _appliquer(ReconnaissanceListe r) async {
    if (r.etablissement == null) return;
    await _choisirEtab(r.etablissement!.id);
    if (r.classe != null && mounted) setState(() => _classe = r.classe!.id);
  }

  // -------------------------------------------------------------- classes

  Future<Enregistrement?> _creer(ClasseLue lue) async {
    Enregistrement? cree;
    await executer(context, () async {
      cree = await _s.gestion.creerClasse(_droits,
          etablissementId: _etab!,
          anneeScolaireId: _annee!.id,
          libelle: lue.libelle,
          niveau: lue.niveau.isEmpty ? null : lue.niveau);
    });
    return cree;
  }

  /// Crée la classe lue dans une liste d'une seule classe.
  Future<void> _creerClasse(ReconnaissanceListe r) async {
    final etab = _etab ?? r.etablissement?.id;
    final lue = r.classeLue;
    if (etab == null || lue == null || _annee == null) return;
    if (_etab != etab) await _choisirEtab(etab);
    if (!mounted) return;
    final nom = _etabs.firstWhere((e) => e.id == etab).nom;
    if (!await confirmer(context, 'Créer la classe « ${lue.libelle} » ?',
        'Classe de $nom pour l\'année ${_annee!.libelle}. Les élèves de la liste y seront inscrits à la validation.',
        bouton: 'Créer')) {
      return;
    }
    if (!mounted) return;
    final cree = await _creer(lue);
    if (cree == null) return;
    await _rechargerClasses();
    if (mounted) {
      setState(() => _classe = cree.id);
      message(context, 'Classe « ${lue.libelle} » créée.');
    }
  }

  /// Classe proposée pour chaque partie : classe de même libellé dans
  /// l'établissement choisi (« 2nd G1 » = « 2nde G1 »), une seule fois.
  void _proposerClasses() {
    final prises = <String>{};
    for (final pa in _parties!) {
      final lue = pa.source.classeLue;
      final c = _etab == null || lue == null ? null : rapprocherClasse(lue, _etab!, _classesEtab);
      pa.classeId = c != null && prises.add(c.id) ? c.id : null;
    }
  }

  /// Parties retenues dont la classe lue n'existe pas encore.
  List<_Partie> get _aCreer => [
        for (final pa in _parties ?? const <_Partie>[])
          if (pa.importer && pa.classeId == null && pa.source.classeLue != null) pa
      ];

  Future<void> _creerClasses(List<_Partie> parties) async {
    if (_etab == null || parties.isEmpty) return;
    final noms = {for (final pa in parties) pa.source.classeLue!.libelle};
    final etab = _etabs.firstWhere((e) => e.id == _etab).nom;
    if (!await confirmer(
        context,
        noms.length == 1 ? 'Créer la classe « ${noms.single} » ?' : 'Créer ${noms.length} classes ?',
        '${noms.join(', ')}\n\nClasses de $etab pour l\'année ${_annee!.libelle}. Les élèves de chaque partie y seront '
            'inscrits à la validation.',
        bouton: 'Créer')) {
      return;
    }
    if (!mounted) return;
    final creees = <String, String>{};
    for (final pa in parties) {
      final lue = pa.source.classeLue!;
      final cle = cleClasse(lue.libelle);
      final deja = creees[cle];
      if (deja != null) continue;
      final cree = await _creer(lue);
      if (cree == null || !mounted) break;
      creees[cle] = cree.id;
      pa.classeId = cree.id;
    }
    await _rechargerClasses();
    if (mounted && creees.isNotEmpty) {
      setState(() {});
      message(context, creees.length == 1 ? 'Classe créée.' : '${creees.length} classes créées.');
    }
  }

  // -------------------------------------------------------------- analyse

  void _analyser() {
    final parties = <_Partie>[];
    for (final g in grouperParClasse(_tableauxCourants)) {
      final lignes = analyserTableau(g.tableau);
      if (lignes.isNotEmpty) parties.add(_Partie(g, lignes));
    }
    if (parties.isEmpty) {
      setState(() => _erreur = 'Aucun élève trouvé : vérifiez la colonne du nom.');
      return;
    }
    if (parties.length > 1) {
      for (final pa in parties) {
        for (final l in pa.lignes) {
          l.groupe = pa.source.libelle;
        }
      }
    }
    setState(() {
      _erreur = null;
      _parties = parties;
      if (parties.length > 1) _proposerClasses();
      _controler();
    });
  }

  void _controler() => controlerLignes(_lignes, existants: _existants, dateReference: DateTime.now().toUtc());

  Future<void> _corriger(LigneImport l) async {
    final c = {
      'matricule': TextEditingController(text: l.matricule ?? ''),
      'nom': TextEditingController(text: l.nom),
      'prenoms': TextEditingController(text: l.prenoms),
      'date': TextEditingController(text: l.dateNaissance == null ? '' : dateFr(l.dateNaissance)),
      'sexe': TextEditingController(text: l.sexe?.code ?? ''),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Ligne ${l.numeroSource}${l.groupe == null ? '' : ' · ${l.groupe}'}'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Lu : ${l.brut.values.join(' | ')}', style: const TextStyle(fontSize: 12)),
            for (final (k, lib) in [
              ('matricule', 'Matricule'),
              ('nom', 'Nom'),
              ('prenoms', 'Prénoms'),
              ('date', 'Date de naissance (JJ/MM/AAAA)'),
              ('sexe', 'Sexe (M ou F)'),
            ])
              TextField(controller: c[k], decoration: InputDecoration(labelText: lib)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok == true) {
      l
        ..matricule = normaliserMatricule(c['matricule']!.text)
        ..nom = c['nom']!.text.trim().toUpperCase()
        ..prenoms = c['prenoms']!.text.trim()
        ..dateNaissance = lireDateListe(c['date']!.text)
        ..sexe = lireSexe(c['sexe']!.text);
      _controler();
      setState(() {});
    }
    for (final t in c.values) {
      t.dispose();
    }
  }

  // ----------------------------------------------------------- validation

  /// Raison pour laquelle la validation est impossible (null : possible).
  String? get _empechement {
    final b = bilan(_lignes);
    if (!_plusieurs) {
      if (_classe == null) return 'Choisissez la classe';
      return b.validable ? null : (b.bloquees > 0 ? 'Corrigez les lignes en erreur' : 'Aucun élève à importer');
    }
    final retenues = [for (final pa in _parties!) if (pa.importer) pa];
    if (_etab == null) return 'Choisissez l\'établissement';
    if (retenues.isEmpty) return 'Aucune classe retenue';
    final sansClasse = retenues.where((pa) => pa.classeId == null).length;
    if (sansClasse > 0) return '$sansClasse partie${sansClasse > 1 ? 's' : ''} sans classe de destination';
    final ids = [for (final pa in retenues) pa.classeId];
    if (ids.toSet().length != ids.length) return 'Deux parties vont dans la même classe';
    return b.validable ? null : (b.bloquees > 0 ? 'Corrigez les lignes en erreur' : 'Aucun élève à importer');
  }

  Future<void> _valider() async {
    final b = bilan(_lignes);
    final etab = _etabs.where((e) => e.id == _etab).firstOrNull?.nom ?? '';
    final retenues = [for (final pa in _parties!) if (pa.importer || !_plusieurs) pa];
    final detail = _plusieurs
        ? [
            for (final pa in retenues)
              '• ${pa.source.libelle} → ${_nomClasse(pa.classeId)} : '
                  '${pa.lignes.where((l) => l.action != ActionImport.ignorer).length} élèves'
          ].join('\n')
        : 'Classe ${_nomClasse(_classe)}';
    if (!await confirmer(
        context,
        'Confirmer l\'importation',
        '$etab (${_annee?.libelle ?? ''})\n$detail\n\n'
            '${b.aCreer} nouveaux élèves, ${b.aRattacher} rattachés, ${b.ignorees} lignes non importées.',
        bouton: 'Importer')) {
      return;
    }
    if (!mounted) return;
    final octets = await File(_chemin!).readAsBytes();
    if (!mounted) return;
    List<ResultatImportServeur> r = const [];
    final ok = await executer(context, () async {
      r = await _s.gestion.importerListes(
        _droits,
        parties: [
          for (final pa in retenues)
            PartieImport(_plusieurs ? pa.classeId! : _classe!, pa.lignes, origine: _plusieurs ? pa.source.origine : null)
        ],
        format: _tableaux.first.format,
        nomFichier: p.basename(_chemin!),
        empreinteSha256: sha256Hex(octets),
      );
    });
    if (!ok || !mounted) return;
    int somme(int Function(ResultatImportServeur) f) => r.fold(0, (s, x) => s + f(x));
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Importation terminée'),
        content: Text('${r.length > 1 ? '${r.length} classes. ' : ''}'
            '${somme((x) => x.crees)} dossiers créés, ${somme((x) => x.rattaches)} élèves rattachés, '
            '${somme((x) => x.changementsDeClasse)} changements de classe, ${somme((x) => x.ignores)} lignes non importées.\n'
            'Les téléphones de l\'établissement recevront la liste à leur prochaine synchronisation.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
      ),
    );
    await _rechargerClasses();
    if (!mounted) return;
    setState(() {
      _parties = null;
      _tableaux = const [];
      _correspondances = const [];
      _chemin = null;
      _reconnaissance = null;
    });
  }

  Future<void> _enregistrerModele() async {
    final chemin = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer le modèle', fileName: 'modele_liste_eleves_plusieurs_classes.xlsx',
        type: FileType.custom, allowedExtensions: const ['xlsx']);
    if (chemin == null) return;
    final f = chemin.toLowerCase().endsWith('.xlsx') ? chemin : '$chemin.xlsx';
    await File(f).writeAsBytes(modeleListeEleves(), flush: true);
    if (mounted) message(context, 'Modèle enregistré : $f');
  }

  // ---------------------------------------------------------------- écran

  @override
  Widget build(BuildContext context) {
    if (_progression != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(_progression!),
      ]));
    }
    final plusieurs = _plusieurs;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Importation des listes d\'élèves', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 320,
          child: DropdownButtonFormField<String>(
            value: _etab,
            decoration: const InputDecoration(labelText: 'Établissement'),
            items: [for (final e in _etabs) DropdownMenuItem(value: e.id, child: Text(e.nom, overflow: TextOverflow.ellipsis))],
            onChanged: _choisirEtab,
          ),
        ),
        if (!plusieurs)
          SizedBox(
            width: 240,
            child: DropdownButtonFormField<String>(
              value: _classe,
              decoration: InputDecoration(labelText: 'Classe (${_annee?.libelle ?? ''})'),
              items: [
                for (final c in _classes) DropdownMenuItem(value: c.id, child: Text('${c.libelle} · ${c.effectif} élèves'))
              ],
              onChanged: (c) => setState(() => _classe = c),
            ),
          ),
        FilledButton.icon(
          onPressed: _annee == null ? null : _choisirFichier,
          icon: const Icon(Icons.folder_open),
          label: const Text('Choisir le fichier (Excel, CSV, PDF, image)'),
        ),
        OutlinedButton.icon(
          onPressed: _enregistrerModele,
          icon: const Icon(Icons.download),
          label: const Text('Modèle Excel (plusieurs classes)'),
        ),
      ]),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
            'Choisissez directement le fichier : l\'établissement et la classe sont proposés d\'après le titre de la liste, '
            'le nom des feuilles et le nom du fichier. Un classeur Excel peut contenir plusieurs classes : une feuille par '
            'classe, ou une colonne « Classe ».',
            style: TextStyle(fontSize: 12)),
      ),
      if (_reconnaissance != null && _tableaux.isNotEmpty) _carteReconnaissance(_reconnaissance!),
      if (_erreur != null)
        Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(padding: const EdgeInsets.all(12), child: Text(_erreur!))),
      if (_tableaux.isNotEmpty && _parties == null) ..._colonnes(),
      if (_parties != null) ..._controle(),
    ]);
  }

  Widget _carteReconnaissance(ReconnaissanceListe r) {
    final schema = Theme.of(context).colorScheme;
    final propose = r.etablissement;
    final differente = propose != null && _etab != null && _etab != propose.id;
    final classeLue = _plusieurs ? null : r.classeLue;
    final classeExiste = classeLue != null && _classes.any((c) => cleClasse(c.libelle) == cleClasse(classeLue.libelle));
    final titres = _tableaux.first.titres;
    return Card(
      color: schema.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome),
            const SizedBox(width: 8),
            Text('Reconnaissance automatique', style: Theme.of(context).textTheme.titleSmall),
          ]),
          const SizedBox(height: 4),
          for (final x in r.raisons) Text('• $x'),
          if (_plusieurs)
            Text('• ${_groupesPrevus.length} classes dans le fichier : '
                '${_groupesPrevus.map((g) => g.libelle).take(12).join(', ')}'
                '${_groupesPrevus.length > 12 ? '…' : ''}.'),
          if (titres.isNotEmpty)
            Text('Titres lus : ${titres.take(4).join(' · ')}',
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (differente) OutlinedButton(onPressed: () => _appliquer(r), child: Text('Utiliser « ${propose.nom} »')),
            if (classeLue != null && !classeExiste && (_etab ?? propose?.id) != null)
              FilledButton.tonalIcon(
                onPressed: () => _creerClasse(r),
                icon: const Icon(Icons.add),
                label: Text('Créer la classe « ${classeLue.libelle} »'),
              ),
          ]),
          Text(
              _plusieurs
                  ? 'Vérifiez l\'établissement ci-dessus ; la classe de chaque partie est proposée après l\'analyse.'
                  : 'Vérifiez l\'établissement et la classe ci-dessus avant de valider : vous pouvez les changer.',
              style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }

  /// Affectation des colonnes, feuille par feuille.
  List<Widget> _colonnes() {
    final t = _tableaux[_feuille];
    final correspondance = _correspondances[_feuille];
    final entete = t.ligneEntete == null ? null : t.lignes[t.ligneEntete!];
    final nomOk = [for (final c in _correspondances) c.values.any((x) => x.estNom)];
    return [
      const SizedBox(height: 16),
      Text('Colonnes de « ${p.basename(_chemin!)} »', style: Theme.of(context).textTheme.titleMedium),
      if (_tableaux.length > 1) ...[
        const SizedBox(height: 4),
        Text('${_tableaux.length} feuilles contiennent une liste d\'élèves (une classe par feuille) ; les autres sont '
            'ignorées. Colonnes reconnues automatiquement : vérifiez chaque feuille.'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < _tableaux.length; i++)
            ChoiceChip(
              selected: i == _feuille,
              avatar: Icon(nomOk[i] ? Icons.check_circle : Icons.error, size: 18, color: nomOk[i] ? Colors.green : Colors.red),
              label: Text(_tableaux[i].feuille ?? 'Feuille ${i + 1}'),
              onSelected: (_) => setState(() => _feuille = i),
            ),
        ]),
      ],
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 8, children: [
        for (var col = 0; col < t.nombreColonnes; col++)
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<ChampListe>(
              key: ValueKey('$_feuille-$col'),
              value: correspondance[col] ?? ChampListe.ignorer,
              decoration: InputDecoration(
                labelText: 'Colonne ${col + 1}${entete != null && col < entete.length ? ' « ${entete[col]} »' : ''}',
              ),
              items: [for (final c in ChampListe.values) DropdownMenuItem(value: c, child: Text(c.libelle))],
              onChanged: (c) => setState(() {
                if (c == null || c == ChampListe.ignorer) {
                  correspondance.remove(col);
                } else {
                  correspondance[col] = c;
                }
              }),
            ),
          ),
      ]),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('Colonne « Classe » : les élèves sont répartis dans les classes indiquées sur chaque ligne.',
            style: TextStyle(fontSize: 12)),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: nomOk.every((x) => x) ? _analyser : null,
          child: Text(nomOk.every((x) => x) ? 'Analyser la liste' : 'Indiquez la colonne du nom dans chaque feuille'),
        ),
      ),
    ];
  }

  /// Classes du fichier : partie, nombre d'élèves, classe de destination.
  Widget _tableauParties() {
    final manquantes = _aCreer;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${_parties!.length} classes dans le fichier', style: Theme.of(context).textTheme.titleMedium),
            ),
            if (manquantes.isNotEmpty && _etab != null)
              FilledButton.tonalIcon(
                onPressed: () => _creerClasses(manquantes),
                icon: const Icon(Icons.add),
                label: Text(manquantes.length == 1
                    ? 'Créer la classe manquante'
                    : 'Créer les ${manquantes.length} classes manquantes'),
              ),
          ]),
          if (_etab == null)
            const Text('Choisissez d\'abord l\'établissement : la classe de chaque partie y sera proposée.',
                style: TextStyle(color: Colors.red)),
          DataTable(
            columns: const [
              DataColumn(label: Text('Importer')),
              DataColumn(label: Text('Partie du fichier')),
              DataColumn(label: Text('Élèves')),
              DataColumn(label: Text('Classe de destination')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final pa in _parties!)
                DataRow(cells: [
                  DataCell(Checkbox(
                    value: pa.importer,
                    onChanged: (v) => setState(() {
                      pa.importer = v ?? true;
                      _controler();
                    }),
                  )),
                  DataCell(Text(pa.source.origine)),
                  DataCell(Text('${pa.lignes.length}')),
                  DataCell(SizedBox(
                    width: 220,
                    child: DropdownButton<String?>(
                      isExpanded: true,
                      value: _classes.any((c) => c.id == pa.classeId) ? pa.classeId : null,
                      hint: const Text('— choisir —'),
                      items: [
                        for (final c in _classes) DropdownMenuItem(value: c.id, child: Text('${c.libelle} · ${c.effectif} élèves')),
                      ],
                      onChanged: pa.importer ? (v) => setState(() => pa.classeId = v) : null,
                    ),
                  )),
                  DataCell(pa.importer && pa.classeId == null && pa.source.classeLue != null && _etab != null
                      ? TextButton.icon(
                          onPressed: () => _creerClasses([pa]),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text('Créer « ${pa.source.classeLue!.libelle} »'),
                        )
                      : const SizedBox.shrink()),
                ]),
            ],
          ),
        ]),
      ),
    );
  }

  List<Widget> _controle() {
    final lignes = _lignes;
    final b = bilan(lignes);
    final empechement = _empechement;
    final plusieurs = _plusieurs;
    return [
      const SizedBox(height: 16),
      if (plusieurs) _tableauParties(),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: Text('${lignes.length} lignes : ${b.aCreer} nouveaux, ${b.aRattacher} rattachés, ${b.ignorees} non importés'
              '${b.bloquees == 0 ? '' : ', ${b.bloquees} en erreur'}'),
        ),
        TextButton(
          onPressed: () => setState(() => _parties = null),
          child: const Text('Revenir aux colonnes'),
        ),
        if (empechement != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(empechement, style: const TextStyle(color: Colors.red)),
          ),
        FilledButton(onPressed: empechement == null ? _valider : null, child: const Text('VALIDER L\'IMPORTATION')),
      ]),
      const SizedBox(height: 8),
      DataTable(
        columns: [
          if (plusieurs) const DataColumn(label: Text('Classe')),
          const DataColumn(label: Text('Ligne')),
          const DataColumn(label: Text('Matricule')),
          const DataColumn(label: Text('Nom et prénoms')),
          const DataColumn(label: Text('Sexe')),
          const DataColumn(label: Text('Né(e) le')),
          const DataColumn(label: Text('Contrôles')),
          const DataColumn(label: Text('Action')),
          const DataColumn(label: Text('')),
        ],
        rows: [
          for (final l in lignes)
            DataRow(
              color: WidgetStatePropertyAll(l.action == ActionImport.ignorer
                  ? Colors.grey.shade200
                  : l.bloquee
                      ? Colors.red.shade50
                      : l.aVerifier
                          ? Colors.orange.shade50
                          : null),
              cells: [
                if (plusieurs) DataCell(Text(l.groupe ?? '')),
                DataCell(Text('${l.numeroSource}')),
                DataCell(Text(l.matricule ?? '—')),
                DataCell(Text('${l.nom} ${l.prenoms}')),
                DataCell(Text(l.sexe?.code ?? '?')),
                DataCell(Text(l.dateNaissance == null ? '?' : dateFr(l.dateNaissance))),
                DataCell(SizedBox(
                  width: 320,
                  child: Text([...l.anomalies.map((a) => a.message), ...l.notes].join(' · '),
                      maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                )),
                DataCell(DropdownButton<ActionImport>(
                  value: l.action,
                  items: [
                    for (final a in ActionImport.values)
                      if (a != ActionImport.rattacher || l.eleveExistantId != null)
                        DropdownMenuItem(value: a, child: Text(a.libelle)),
                  ],
                  onChanged: (a) {
                    if (a == null) return;
                    l.imposerAction(a);
                    _controler();
                    setState(() {});
                  },
                )),
                DataCell(IconButton(icon: const Icon(Icons.edit), tooltip: 'Corriger', onPressed: () => _corriger(l))),
              ],
            ),
        ],
      ),
    ];
  }
}
