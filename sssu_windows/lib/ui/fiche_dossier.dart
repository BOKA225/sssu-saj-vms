/// Dossier de l'élève : identité et inscriptions, visites médicales,
/// galerie photographique sécurisée (photos de toutes les visites).
/// Chaque ouverture du dossier, consultation et téléchargement de photo est
/// tracé dans le journal d'audit.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../donnees/requetes_poste.dart';
import '../services.dart';
import 'commun.dart';
import 'detail_visite.dart';
import 'dialogue_eleve.dart';

class FicheDossier extends ConsumerStatefulWidget {
  final String eleveId;
  const FicheDossier({super.key, required this.eleveId});
  @override
  ConsumerState<FicheDossier> createState() => _FicheDossierState();
}

class _FicheDossierState extends ConsumerState<FicheDossier> {
  Enregistrement? _eleve;
  List<LigneInscription> _inscriptions = const [];
  List<LigneVisite> _visites = const [];
  List<LignePhoto> _photos = const [];
  Annee? _annee;

  ServicesPoste get _s => ref.read(servicesProvider);
  Droits get _droits => ref.read(sessionProvider)!.droits;

  @override
  void initState() {
    super.initState();
    _s.gestion.noterAcces(_droits, 'consultation', table: 'eleve', id: widget.eleveId);
    _charger();
  }

  Future<void> _charger() async {
    final e = await _s.depot.transaction((tx) => tx.lire('eleve', widget.eleveId));
    final ins = await _s.requetes.inscriptions(widget.eleveId);
    final annee = await _s.requetes.anneeCourante();
    final medical = accesMedical(_droits);
    final v = medical ? await _s.requetes.visites(widget.eleveId) : <LigneVisite>[];
    final p = medical ? await _s.requetes.photos(widget.eleveId) : <LignePhoto>[];
    if (!mounted) return;
    setState(() {
      _eleve = e;
      _annee = annee;
      _inscriptions = ins;
      _visites = v;
      _photos = p.where((ph) => _droits.peutVoirPhoto(auteurId: ph.auteurId)).toList();
    });
  }

  bool get _peutModifier => _droits.peutGererEleves;

  Future<void> _modifierIdentite() async {
    final saisie = await showDialog<SaisieEleve>(
      context: context,
      builder: (_) => DialogueEleve(titre: 'Identité de l\'élève', actuel: _eleve!.donnees),
    );
    if (saisie == null || !mounted) return;
    // Même matricule ou mêmes nom, prénoms et date qu'un autre dossier : signalé.
    final existants = await _s.depot.transaction((tx) => tx.chercher('eleve', const {}));
    final semblable = eleveSemblable(saisie.identite, existants, sauf: widget.eleveId);
    if (semblable != null && mounted) {
      final continuer = await confirmer(
          context,
          'Un autre dossier ressemble à celui-ci',
          '${semblable.nom} ${semblable.prenoms}'
              '${semblable.matricule == null ? '' : ' · matricule ${semblable.matricule}'}'
              '${semblable.dateNaissance == null ? '' : ' · né(e) le ${dateFr(semblable.dateNaissance)}'}\n\n'
              'Vérifiez qu\'il ne s\'agit pas du même élève : un élève ne doit avoir qu\'un seul dossier. '
              'Enregistrer quand même ?',
          bouton: 'Enregistrer');
      if (!continuer) return;
    }
    if (!mounted) return;
    await executer(context, () => _s.gestion.modifierEleve(_droits, widget.eleveId, saisie.identite),
        succes: 'Dossier mis à jour.');
    _charger();
  }

  /// Classe de l'année en cours, choisie parmi tous les établissements.
  Future<String?> _choisirClasse({String? exclue}) async {
    final annee = _annee;
    if (annee == null) return null;
    final etabs = await _s.requetes.etablissements(annee);
    final choix = <(String, String)>[];
    for (final e in etabs) {
      for (final c in await _s.requetes.classes(e.id, annee)) {
        if (c.id != exclue) choix.add((c.id, '${e.nom} · ${c.libelle}'));
      }
    }
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text('Classe (${annee.libelle})'),
        children: [for (final (id, lib) in choix) SimpleDialogOption(onPressed: () => Navigator.pop(d, id), child: Text(lib))],
      ),
    );
  }

  /// Inscription dans une classe de l'année, ou changement de classe (et
  /// d'établissement : le dossier suit l'élève).
  Future<void> _inscrire({String? classeActuelle}) async {
    final classe = await _choisirClasse(exclue: classeActuelle);
    if (classe == null || !mounted) return;
    await executer(context, () => _s.gestion.inscrireEleve(_droits, widget.eleveId, classe),
        succes: classeActuelle == null
            ? 'Élève inscrit.'
            : 'Classe modifiée. Le dossier de l\'élève est transmis aux téléphones de son établissement.');
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    final e = _eleve;
    if (e == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final d = e.donnees;
    final medical = accesMedical(_droits);
    return DefaultTabController(
      length: medical ? 3 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${d['nom']} ${d['prenoms']}'),
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              const Tab(text: 'Identité et scolarité'),
              if (medical) Tab(text: 'Visites médicales (${_visites.length})'),
              if (medical) Tab(text: 'Photographies (${_photos.length})'),
            ],
          ),
        ),
        body: TabBarView(children: [
          ListView(padding: const EdgeInsets.all(16), children: [
            Bloc(
              titre: 'Identité',
              action: _peutModifier
                  ? TextButton.icon(onPressed: _modifierIdentite, icon: const Icon(Icons.edit), label: const Text('Modifier'))
                  : null,
              enfants: [
                Text('Matricule : ${d['matricule'] ?? 'non renseigné'}'),
                Text('Sexe : ${Sexe.depuisCode(d['sexe'] as String).libelle}'),
                if (d['date_naissance'] != null)
                  Text('Né(e) le ${dateFr(d['date_naissance'])} · '
                      '${calculerAge(lireDate(d['date_naissance'] as String), DateTime.now())}'),
                if (d['telephone_contact'] != null) Text('Téléphone : ${d['telephone_contact']}'),
              ],
            ),
            Bloc(
              titre: 'Scolarité',
              action: _peutModifier && _annee != null && !_inscriptions.any((i) => i.annee == _annee!.libelle)
                  ? TextButton.icon(
                      onPressed: _inscrire,
                      icon: const Icon(Icons.how_to_reg),
                      label: Text('Inscrire en ${_annee!.libelle}'),
                    )
                  : null,
              enfants: [
                if (_inscriptions.isEmpty) const Text('Aucune inscription.'),
                for (final i in _inscriptions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${i.annee} · ${i.classe}'),
                    subtitle: Text('${i.etablissement} · ${i.statut}'),
                    trailing: _peutModifier && i.annee == _annee?.libelle
                        ? TextButton(onPressed: () => _inscrire(classeActuelle: i.classeId), child: const Text('Changer de classe'))
                        : null,
                  ),
              ],
            ),
          ]),
          if (medical)
            ListView(padding: const EdgeInsets.all(16), children: [
              if (_visites.isEmpty) const Text('Aucune visite médicale.'),
              for (final v in _visites)
                Card(
                  child: ListTile(
                    leading: Icon(v.statut == 'valide' ? Icons.verified : Icons.assignment),
                    title: Text('${dateFr(v.date)} · ${libelleStatutVisite(v.statut)}'),
                    subtitle: Text('${libelleConclusion(v.conclusion)}'
                        '${v.diagnostic == null ? '' : ' · ${v.diagnostic}'} · agent : ${v.agent}'
                        '${v.photos == 0 ? '' : ' · ${v.photos} photo(s)'}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => DetailVisite(visiteId: v.id)));
                      _charger();
                    },
                  ),
                ),
            ]),
          if (medical) GaleriePhotos(photos: _photos),
        ]),
      ),
    );
  }
}

/// Galerie sécurisée : vignettes déchiffrées à la demande, agrandissement,
/// commentaires, téléchargement réservé et tracé.
class GaleriePhotos extends ConsumerStatefulWidget {
  final List<LignePhoto> photos;
  const GaleriePhotos({super.key, required this.photos});
  @override
  ConsumerState<GaleriePhotos> createState() => _GaleriePhotosState();
}

class _GaleriePhotosState extends ConsumerState<GaleriePhotos> {
  final Map<String, Uint8List?> _images = {};

  ServicesPoste get _s => ref.read(servicesProvider);
  Droits get _droits => ref.read(sessionProvider)!.droits;

  Future<Uint8List?> _image(String id) async {
    if (_images.containsKey(id)) return _images[id];
    Uint8List? octets;
    if (await _s.photos.disponible(id)) {
      try {
        octets = await _s.photos.lire(id);
      } catch (_) {
        octets = null;
      }
    }
    _images[id] = octets;
    return octets;
  }

  Future<void> _ouvrir(LignePhoto p) async {
    final octets = await _image(p.id);
    if (octets == null || !mounted) return;
    await _s.gestion.noterAcces(_droits, 'consultation', table: 'photo', id: p.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (d) => Dialog(
        child: SizedBox(
          width: 900,
          height: 720,
          child: Column(children: [
            Expanded(child: InteractiveViewer(maxScale: 8, child: Image.memory(octets, fit: BoxFit.contain))),
            ListTile(
              title: Text(p.commentaire ?? 'Sans commentaire'),
              subtitle: Text('Visite du ${dateFr(p.dateVisite)}${p.pathologie == null ? '' : ' · ${p.pathologie}'} · '
                  'prise le ${dateHeureFr(p.prisLe)} par ${p.auteur}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_droits.peut(Permission.photoTelecharger))
                  TextButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Télécharger'),
                    onPressed: () async {
                      final chemin = await FilePicker.platform.saveFile(
                          dialogTitle: 'Enregistrer la photographie', fileName: 'photo_${p.dateVisite}_${p.id.substring(0, 8)}.jpg');
                      if (chemin == null) return;
                      await _s.photos.exporter(p.id, chemin);
                      await _s.gestion.noterAcces(_droits, 'telechargement', table: 'photo', id: p.id);
                      if (d.mounted) message(d, 'Photographie enregistrée (téléchargement tracé).');
                    },
                  ),
                TextButton(onPressed: () => Navigator.pop(d), child: const Text('Fermer')),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) return const Center(child: Text('Aucune photographie.'));
    final parVisite = <String, List<LignePhoto>>{};
    for (final p in widget.photos) {
      parVisite.putIfAbsent(p.dateVisite, () => []).add(p);
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Données de santé sensibles : chaque consultation et téléchargement est enregistré dans le journal.'),
      const SizedBox(height: 8),
      for (final e in parVisite.entries) ...[
        Text('Visite du ${dateFr(e.key)}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final p in e.value)
            SizedBox(
              width: 200,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _ouvrir(p),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      height: 150,
                      width: 200,
                      child: FutureBuilder<Uint8List?>(
                        future: _image(p.id),
                        builder: (c, s) => s.connectionState != ConnectionState.done
                            ? const Center(child: CircularProgressIndicator())
                            : s.data == null
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Text('En attente de transfert depuis le téléphone', textAlign: TextAlign.center),
                                    ),
                                  )
                                : Image.memory(s.data!, fit: BoxFit.cover, cacheWidth: 400),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text([p.pathologie, p.commentaire].whereType<String>().join(' · ').ifEmpty('—'),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 16),
      ],
    ]);
  }
}

extension on String {
  String ifEmpty(String autre) => isEmpty ? autre : this;
}
