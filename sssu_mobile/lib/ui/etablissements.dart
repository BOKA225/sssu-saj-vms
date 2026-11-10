/// Consultation des établissements, des classes, des effectifs et des élèves ;
/// recherche rapide ; fiche de l'élève avec l'historique de ses visites.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../data/requetes.dart';
import '../import/ecran_import.dart';
import '../services.dart';
import '../visite/ecran_visite.dart';

String _pourcent(int n, int total) => total == 0 ? '—' : '${(n * 100 / total).round()} %';

Widget _chiffre(String valeur, String libelle) => Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(valeur, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(libelle, style: const TextStyle(fontSize: 12)),
      ]),
    );

// ------------------------------------------------------------ établissements

class EcranEtablissements extends ConsumerStatefulWidget {
  const EcranEtablissements({super.key});
  @override
  ConsumerState<EcranEtablissements> createState() => _EcranEtablissementsState();
}

class _EcranEtablissementsState extends ConsumerState<EcranEtablissements> {
  AnneeCourante? _annee;
  List<ResumeEtablissement>? _liste;

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
        _liste = l;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_annee == null ? 'Établissements' : 'Établissements · ${_annee!.libelle}'),
          actions: [
            IconButton(
              tooltip: 'Rechercher un élève',
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EcranRechercheEleve())),
            ),
          ],
        ),
        body: _liste == null
            ? const Center(child: CircularProgressIndicator())
            : _liste!.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Aucun établissement sur ce téléphone. Synchronisez avec le poste central, '
                        'qui affecte les établissements à chaque téléphone.'),
                  )
                : RefreshIndicator(
                    onRefresh: _charger,
                    child: ListView(padding: const EdgeInsets.all(8), children: [
                      for (final e in _liste!)
                        Card(
                          child: InkWell(
                            onTap: () async {
                              await Navigator.push(
                                  context, MaterialPageRoute(builder: (_) => EcranClasses(etablissement: e, annee: _annee!)));
                              _charger();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(e.nom, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                                Text('${e.type.libelle} · ${e.statut.libelle}${e.localite == null ? '' : ' · ${e.localite}'}'),
                                const SizedBox(height: 8),
                                Row(children: [
                                  _chiffre('${e.classes}', 'classes'),
                                  _chiffre('${e.effectif}', 'élèves'),
                                  _chiffre('${e.examines}', 'examinés'),
                                  _chiffre(_pourcent(e.examines, e.effectif), 'couverture'),
                                ]),
                                const SizedBox(height: 4),
                                LinearProgressIndicator(value: e.couverture),
                              ]),
                            ),
                          ),
                        ),
                    ]),
                  ),
      );
}

// ------------------------------------------------------------------ classes

class EcranClasses extends ConsumerStatefulWidget {
  final ResumeEtablissement etablissement;
  final AnneeCourante annee;
  const EcranClasses({super.key, required this.etablissement, required this.annee});
  @override
  ConsumerState<EcranClasses> createState() => _EcranClassesState();
}

class _EcranClassesState extends ConsumerState<EcranClasses> {
  List<ResumeClasse>? _classes;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final c = await ref.read(servicesProvider).requetes.classes(widget.etablissement.id, widget.annee);
    if (mounted) setState(() => _classes = c);
  }

  Future<void> _nouvelleClasse() async {
    final libelle = TextEditingController();
    final niveau = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nouvelle classe'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: libelle, decoration: const InputDecoration(labelText: 'Libellé (ex. CM2 A)')),
          const SizedBox(height: 8),
          TextField(controller: niveau, decoration: const InputDecoration(labelText: 'Niveau (ex. CM2)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Créer')),
        ],
      ),
    );
    final l = libelle.text.trim(), n = niveau.text.trim();
    libelle.dispose();
    niveau.dispose();
    if (ok != true || l.isEmpty) return;
    final s = ref.read(servicesProvider);
    final session = ref.read(sessionProvider)!;
    if ((_classes ?? []).any((c) => normaliserTexte(c.libelle) == normaliserTexte(l))) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cette classe existe déjà.')));
      return;
    }
    await s.depot.creer(
      'classe',
      {
        'etablissement_id': widget.etablissement.id,
        'annee_scolaire_id': widget.annee.id,
        'libelle': l,
        'niveau': n.isEmpty ? null : n,
      },
      utilisateurId: session.utilisateur.id,
      etablissementId: widget.etablissement.id,
    );
    await _charger();
  }

  @override
  Widget build(BuildContext context) {
    final droits = ref.watch(sessionProvider)!.droits;
    return Scaffold(
      appBar: AppBar(title: Text(widget.etablissement.nom)),
      floatingActionButton: droits.peut(Permission.etablissementGerer)
          ? FloatingActionButton.extended(
              onPressed: _nouvelleClasse, icon: const Icon(Icons.add), label: const Text('Nouvelle classe'))
          : null,
      body: _classes == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(8), children: [
              if (_classes!.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text('Aucune classe pour cette année scolaire.')),
              for (final c in _classes!)
                Card(
                  child: ListTile(
                    title: Text(c.libelle, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${c.effectif} élèves (${c.garcons} G, ${c.filles} F) · '
                        '${c.examines} examinés · ${_pourcent(c.examines, c.effectif)}'),
                    trailing: droits.peut(Permission.importExecuter)
                        ? IconButton(
                            tooltip: 'Importer la liste de cette classe',
                            icon: const Icon(Icons.upload_file),
                            onPressed: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => EcranImport(classeId: c.id)));
                              _charger();
                            },
                          )
                        : null,
                    onTap: () async {
                      await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => EcranElevesClasse(classe: c, annee: widget.annee)));
                      _charger();
                    },
                  ),
                ),
            ]),
    );
  }
}

// ------------------------------------------------------------------- élèves

Widget _pastilleVisite(LigneEleve l) {
  final v = l.derniereVisite;
  if (v == null) return const Chip(label: Text('Non examiné'), visualDensity: VisualDensity.compact);
  final couleur = switch (v.statut) {
    StatutVisite.ebauche => Colors.orange.shade100,
    StatutVisite.enregistre => Colors.amber.shade100,
    StatutVisite.valide => Colors.green.shade200,
    _ => v.etat == EtatSync.synchronise ? Colors.green.shade100 : Colors.blue.shade100,
  };
  return Chip(label: Text(v.libelleStatut), backgroundColor: couleur, visualDensity: VisualDensity.compact);
}

Widget _tuileEleve(BuildContext context, LigneEleve l, VoidCallback apres) => ListTile(
      title: Text(l.eleve.nomComplet),
      subtitle: Text([
        if (l.eleve.matricule != null) l.eleve.matricule!,
        l.eleve.sexe.code,
        if (l.eleve.dateNaissance != null) formaterDateFr(l.eleve.dateNaissance!),
        if (l.classeLibelle != null) l.classeLibelle!,
      ].join(' · ')),
      trailing: _pastilleVisite(l),
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => EcranFicheEleve(eleveId: l.eleve.id)));
        apres();
      },
    );

String formaterDateFr(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class EcranElevesClasse extends ConsumerStatefulWidget {
  final ResumeClasse classe;
  final AnneeCourante annee;
  const EcranElevesClasse({super.key, required this.classe, required this.annee});
  @override
  ConsumerState<EcranElevesClasse> createState() => _EcranElevesClasseState();
}

class _EcranElevesClasseState extends ConsumerState<EcranElevesClasse> {
  List<LigneEleve>? _eleves;
  String _filtre = '';
  bool _nonExamines = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final l = await ref.read(servicesProvider).requetes.elevesDeClasse(widget.classe.id, widget.annee);
    if (mounted) setState(() => _eleves = l);
  }

  @override
  Widget build(BuildContext context) {
    final f = normaliserTexte(_filtre);
    final visibles = (_eleves ?? []).where((l) {
      if (_nonExamines && l.examine) return false;
      if (f.isEmpty) return true;
      return normaliserTexte(l.eleve.nomComplet).contains(f) || (l.eleve.matricule ?? '').contains(f);
    }).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.classe.libelle)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Nom ou matricule'),
            onChanged: (v) => setState(() => _filtre = v),
          ),
        ),
        SwitchListTile(
          title: const Text('Seulement les élèves non examinés'),
          value: _nonExamines,
          onChanged: (v) => setState(() => _nonExamines = v),
        ),
        Expanded(
          child: _eleves == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  itemCount: visibles.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) => _tuileEleve(c, visibles[i], _charger),
                ),
        ),
      ]),
    );
  }
}

class EcranRechercheEleve extends ConsumerStatefulWidget {
  const EcranRechercheEleve({super.key});
  @override
  ConsumerState<EcranRechercheEleve> createState() => _EcranRechercheEleveState();
}

class _EcranRechercheEleveState extends ConsumerState<EcranRechercheEleve> {
  List<LigneEleve> _resultats = const [];
  String _texte = '';

  Future<void> _chercher(String t) async {
    _texte = t;
    final r = ref.read(servicesProvider).requetes;
    final a = await r.anneeCourante();
    if (a == null) return;
    final res = await r.rechercher(t, a);
    if (mounted && t == _texte) setState(() => _resultats = res);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: TextField(
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            cursorColor: Colors.white,
            decoration: const InputDecoration(
              hintText: 'Nom, prénoms ou matricule',
              hintStyle: TextStyle(color: Colors.white70),
              border: InputBorder.none,
            ),
            onChanged: _chercher,
          ),
        ),
        body: ListView.separated(
          itemCount: _resultats.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (c, i) => _tuileEleve(c, _resultats[i], () => _chercher(_texte)),
        ),
      );
}

// --------------------------------------------------------------- fiche élève

class EcranFicheEleve extends ConsumerStatefulWidget {
  final String eleveId;
  const EcranFicheEleve({super.key, required this.eleveId});
  @override
  ConsumerState<EcranFicheEleve> createState() => _EcranFicheEleveState();
}

class _EcranFicheEleveState extends ConsumerState<EcranFicheEleve> {
  LigneEleve? _eleve;
  List<ResumeVisite> _visites = const [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final r = ref.read(servicesProvider).requetes;
    final a = await r.anneeCourante();
    if (a == null) return;
    final e = await r.eleve(widget.eleveId, a);
    final v = await r.visitesDeEleve(widget.eleveId);
    if (mounted) {
      setState(() {
        _eleve = e;
        _visites = v;
      });
    }
  }

  Future<void> _ouvrir({String? visiteId}) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => EcranVisite(eleveId: widget.eleveId, visiteId: visiteId)));
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    final e = _eleve;
    final session = ref.watch(sessionProvider)!;
    final enCours = _visites.where((v) => v.statut == StatutVisite.ebauche || v.statut == StatutVisite.enregistre);
    return Scaffold(
      appBar: AppBar(title: const Text('Dossier de l\'élève')),
      floatingActionButton: e != null && session.droits.peut(Permission.visiteSaisir) && e.inscriptionId != null
          ? FloatingActionButton.extended(
              onPressed: () => enCours.isEmpty ? _ouvrir() : _ouvrir(visiteId: enCours.first.id),
              icon: Icon(enCours.isEmpty ? Icons.medical_services : Icons.edit_note),
              label: Text(enCours.isEmpty ? 'Nouvelle visite' : 'Reprendre l\'ébauche'),
            )
          : null,
      body: e == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(e.eleve.nomComplet, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('Matricule : ${e.eleve.matricule ?? 'non renseigné'}'),
              Text('Sexe : ${e.eleve.sexe.libelle}'),
              if (e.eleve.dateNaissance != null)
                Text('Né(e) le ${formaterDateFr(e.eleve.dateNaissance!)} · '
                    '${calculerAge(e.eleve.dateNaissance!, DateTime.now())}'),
              if (e.eleve.telephoneContact != null) Text('Téléphone : ${e.eleve.telephoneContact}'),
              Text(e.classeLibelle == null
                  ? 'Non inscrit cette année : importez la liste de sa classe pour l\'examiner.'
                  : '${e.etablissementNom} · ${e.classeLibelle}'),
              const Divider(height: 32),
              Text('Visites médicales', style: Theme.of(context).textTheme.titleMedium),
              if (_visites.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Aucune visite enregistrée.')),
              for (final v in _visites)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.assignment),
                    title: Text(formaterDateFr(lireDate(v.date))),
                    subtitle: Text([
                      v.libelleStatut,
                      if (v.conclusion != null) ConclusionVisite.depuisCode(v.conclusion!).libelle,
                    ].join(' · ')),
                    onTap: () => _ouvrir(visiteId: v.id),
                  ),
                ),
            ]),
    );
  }
}
