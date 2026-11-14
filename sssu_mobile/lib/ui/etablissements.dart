/// Consultation des établissements, des classes, des effectifs et des élèves ;
/// recherche rapide ; fiche de l'élève avec l'historique de ses visites.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../data/requetes.dart';
import '../eleves/dialogue_eleve.dart';
import '../eleves/service_eleves.dart';
import '../import/ecran_import.dart';
import '../services.dart';
import '../visite/ecran_visite.dart';
import 'champ_classe.dart';

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
          ChampLibelleClasse(libelle, autofocus: true),
          const SizedBox(height: 8),
          TextField(controller: niveau, decoration: const InputDecoration(labelText: 'Niveau (facultatif)')),
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
    if ((_classes ?? []).any((c) => cleClasse(c.libelle) == cleClasse(l))) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cette classe existe déjà.')));
      return;
    }
    await s.depot.creer(
      'classe',
      {
        'etablissement_id': widget.etablissement.id,
        'annee_scolaire_id': widget.annee.id,
        'libelle': l,
        'niveau': n.isEmpty ? niveauDeClasse(l) : n,
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

/// Élève déjà présent sur le téléphone qui ressemble à celui saisi (même
/// matricule, ou mêmes nom, prénoms et date de naissance), sinon null.
IdentiteEleve? _semblable(Map<String, Object?> identite, List<IdentiteEleve> existants, {String? sauf}) {
  final candidat = IdentiteEleve(
    matricule: identite['matricule'] as String?,
    nom: identite['nom']! as String,
    prenoms: identite['prenoms']! as String,
    dateNaissance: identite['date_naissance'] == null ? null : lireDate(identite['date_naissance']! as String),
  );
  final d = detecterDoublons([candidat], [for (final e in existants) if (e.id != sauf) e]);
  return d.isEmpty ? null : d.first.existant;
}

String _decrire(IdentiteEleve e) => '${e.nom} ${e.prenoms}'
    '${e.matricule == null ? '' : ' · matricule ${e.matricule}'}'
    '${e.dateNaissance == null ? '' : ' · né(e) le ${formaterDateFr(e.dateNaissance!)}'}';

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

  /// Ajoute un élève absent de la liste importée ; un élève semblable déjà
  /// présent sur le téléphone est signalé.
  Future<void> _ajouter() async {
    final identite = await saisirEleve(context, titre: 'Nouvel élève · ${widget.classe.libelle}');
    if (identite == null || !mounted) return;
    final s = ref.read(servicesProvider);
    final semblable = _semblable(identite, await s.requetes.identitesEleves());
    if (semblable != null && mounted) {
      final choix = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Cet élève semble déjà enregistré'),
          content: Text('${_decrire(semblable)}\n\nOuvrez son dossier plutôt que de créer un second dossier.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(d, 'ajouter'), child: const Text('Ajouter quand même')),
            FilledButton(onPressed: () => Navigator.pop(d, 'ouvrir'), child: const Text('Ouvrir son dossier')),
          ],
        ),
      );
      if (choix == null || !mounted) return;
      if (choix == 'ouvrir') {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => EcranFicheEleve(eleveId: semblable.id!)));
        return _charger();
      }
    }
    try {
      await ServiceEleves(s.base, s.depot).ajouter(
        identite: identite,
        classeId: widget.classe.id,
        etablissementId: widget.classe.etablissementId,
        anneeScolaireId: widget.classe.anneeScolaireId,
        utilisateurId: ref.read(sessionProvider)!.utilisateur.id,
      );
    } on ErreurDossier catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    await _charger();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${identite['nom']} ${identite['prenoms']} ajouté(e) à la classe ${widget.classe.libelle}.')));
    }
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
      floatingActionButton: ref.watch(sessionProvider)!.droits.peutGererEleves
          ? FloatingActionButton.extended(
              onPressed: _ajouter, icon: const Icon(Icons.person_add), label: const Text('Ajouter un élève'))
          : null,
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

  Future<void> _ouvrir({String? visiteId, TypeVisite type = TypeVisite.systematique}) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => EcranVisite(eleveId: widget.eleveId, visiteId: visiteId, type: type)));
    _charger();
  }

  /// Nouvelle visite : pour un élève de 3ème ou de terminale, choix entre la
  /// visite systématique et la visite d'aptitude.
  Future<void> _nouvelleVisite() async {
    final classe = _eleve?.classeLibelle;
    if (classe == null || !classeConcerneeParAptitude(classe)) return _ouvrir();
    final type = await showDialog<TypeVisite>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('Quelle visite ?'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Élève de $classe : classe concernée par la visite d\'aptitude.',
                style: const TextStyle(fontSize: 13)),
          ),
          for (final t in TypeVisite.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, t),
              child: ListTile(
                leading: Icon(t == TypeVisite.aptitude ? Icons.directions_run : Icons.medical_services),
                title: Text(t.libelle),
                subtitle: Text(t == TypeVisite.aptitude
                    ? 'Aptitude à la pratique de l\'EPS et aux examens (BEPC, BAC)'
                    : 'Bilan de santé de tous les élèves'),
              ),
            ),
        ],
      ),
    );
    if (type != null) await _ouvrir(type: type);
  }

  /// Modification de l'identité (nom, prénoms, sexe, date de naissance,
  /// matricule, téléphone du parent).
  Future<void> _modifier() async {
    final e = _eleve!.eleve;
    final identite = await saisirEleve(context, titre: 'Modifier le dossier', actuel: {
      'matricule': e.matricule,
      'nom': e.nom,
      'prenoms': e.prenoms,
      'date_naissance': e.dateNaissance == null ? null : formaterDate(e.dateNaissance!),
      'sexe': e.sexe.code,
      'telephone_contact': e.telephoneContact,
    });
    if (identite == null || !mounted) return;
    final s = ref.read(servicesProvider);
    final semblable = _semblable(identite, await s.requetes.identitesEleves(), sauf: e.id);
    if (semblable != null && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Un autre dossier ressemble à celui-ci'),
          content: Text('${_decrire(semblable)}\n\nVérifiez qu\'il ne s\'agit pas du même élève : un élève ne doit '
              'avoir qu\'un seul dossier.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Enregistrer quand même')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    try {
      await ServiceEleves(s.base, s.depot).modifier(e.id, identite, utilisateurId: ref.read(sessionProvider)!.utilisateur.id);
    } on ErreurDossier catch (x) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(x.message)));
      return;
    }
    await _charger();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dossier mis à jour. Il sera transmis au poste central à la prochaine synchronisation.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _eleve;
    final session = ref.watch(sessionProvider)!;
    final enCours = _visites.where((v) => v.statut == StatutVisite.ebauche || v.statut == StatutVisite.enregistre);
    return Scaffold(
      appBar: AppBar(title: const Text('Dossier de l\'élève'), actions: [
        if (e != null && session.droits.peutGererEleves)
          IconButton(onPressed: _modifier, icon: const Icon(Icons.edit), tooltip: 'Modifier le dossier'),
      ]),
      floatingActionButton: e != null && session.droits.peut(Permission.visiteSaisir) && e.inscriptionId != null
          ? FloatingActionButton.extended(
              onPressed: () => enCours.isEmpty ? _nouvelleVisite() : _ouvrir(visiteId: enCours.first.id),
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
                    leading: Icon(v.type == TypeVisite.aptitude ? Icons.directions_run : Icons.assignment),
                    title: Text('${formaterDateFr(lireDate(v.date))} · ${v.type.libelle}'),
                    subtitle: Text([
                      v.libelleStatut,
                      if (v.aptitude != null) v.aptitude!.libelle,
                      if (v.conclusion != null) ConclusionVisite.depuisCode(v.conclusion!).libelle,
                    ].join(' · ')),
                    onTap: () => _ouvrir(visiteId: v.id),
                  ),
                ),
            ]),
    );
  }
}
