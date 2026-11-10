/// Rubrique « PHOTOGRAPHIES CLINIQUES – JOINDRE UNE PHOTO » du formulaire.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sssu_core/sssu_core.dart';

import 'service_photo.dart';

/// Pathologie dépistée à laquelle une photo peut être associée.
class PathologieLiable {
  final String visitePathologieId;
  final String libelle;
  const PathologieLiable(this.visitePathologieId, this.libelle);
}

class SectionPhotos extends StatefulWidget {
  final ServicePhoto service;
  final String visiteId;
  final String eleveId;
  final String? etablissementId;
  final Session session;
  final bool lectureSeule;

  /// Les éléments créés sont-ils à transmettre (visite déjà validée par l'agent) ?
  final bool aTransmettre;
  final List<PathologieLiable> pathologies;

  const SectionPhotos({
    super.key,
    required this.service,
    required this.visiteId,
    required this.eleveId,
    required this.etablissementId,
    required this.session,
    required this.lectureSeule,
    required this.aTransmettre,
    required this.pathologies,
  });

  @override
  State<SectionPhotos> createState() => _SectionPhotosState();
}

class _SectionPhotosState extends State<SectionPhotos> {
  Enregistrement? _consentement;
  List<Enregistrement> _photos = const [];
  final Map<String, Uint8List> _apercus = {};
  bool _charge = false;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final c = await widget.service.consentement(widget.visiteId);
    final p = (await widget.service.photos(widget.visiteId))
        .where((ph) => widget.session.droits.peutVoirPhoto(auteurId: ph.donnees['auteur_id']! as String))
        .toList();
    for (final ph in p) {
      if (!_apercus.containsKey(ph.id)) {
        try {
          _apercus[ph.id] = await widget.service.lire(ph);
        } catch (_) {
          // Fichier absent (photo transférée) ou illisible : pas d'aperçu.
        }
      }
    }
    if (mounted) {
      setState(() {
        _consentement = c;
        _photos = p;
        _charge = true;
      });
    }
  }

  static bool _transferee(Enregistrement ph) => ph.donnees['statut_transfert'] == 'confirme';

  bool get _peutPrendre => !widget.lectureSeule && widget.session.droits.peut(Permission.photoPrendre);

  Future<void> _saisirConsentement() async {
    final nom = TextEditingController();
    final lien = TextEditingController();
    var forme = 'oral';
    var obtenu = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, maj) => AlertDialog(
          title: const Text('Consentement du parent ou tuteur'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Les photographies médicales d\'un mineur exigent l\'accord de son parent ou tuteur. '
                  'Photographier uniquement la zone concernée, sans le visage sauf nécessité clinique.'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Consentement obtenu'),
                value: obtenu,
                onChanged: (v) => maj(() => obtenu = v),
              ),
              if (obtenu) ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'oral', label: Text('Oral')),
                    ButtonSegment(value: 'ecrit', label: Text('Écrit')),
                  ],
                  selected: {forme},
                  onSelectionChanged: (s) => maj(() => forme = s.first),
                ),
                const SizedBox(height: 8),
                TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom de la personne qui consent')),
                const SizedBox(height: 8),
                TextField(controller: lien, decoration: const InputDecoration(labelText: 'Lien avec l\'élève (mère, tuteur…)')),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(
              onPressed: () => Navigator.pop(c, !obtenu || nom.text.trim().isNotEmpty),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    final n = nom.text, l = lien.text;
    nom.dispose();
    lien.dispose();
    if (ok != true) return;
    await widget.service.enregistrerConsentement(
      visiteId: widget.visiteId,
      eleveId: widget.eleveId,
      etablissementId: widget.etablissementId,
      obtenu: obtenu,
      forme: forme,
      nomRepondant: n,
      lienParente: l.trim().isEmpty ? null : l.trim(),
      utilisateurId: widget.session.utilisateur.id,
      aTransmettre: widget.aTransmettre,
    );
    await _charger();
  }

  Future<void> _ajouter({Enregistrement? remplace}) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Prendre une photo'),
            onTap: () => Navigator.pop(c, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Joindre une photo de la galerie'),
            onTap: () => Navigator.pop(c, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    setState(() => _enCours = true);
    try {
      final ph = await widget.service.ajouter(
        source: source,
        visiteId: widget.visiteId,
        eleveId: widget.eleveId,
        etablissementId: widget.etablissementId,
        consentementId: _consentement!.id,
        auteurId: widget.session.utilisateur.id,
        aTransmettre: widget.aTransmettre,
        commentaire: remplace?.donnees['commentaire'] as String?,
        visitePathologieId: remplace?.donnees['visite_pathologie_id'] as String?,
      );
      if (ph != null && remplace != null) {
        await widget.service.supprimer(remplace, utilisateurId: widget.session.utilisateur.id);
        _apercus.remove(remplace.id);
      }
    } on FormatException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
    await _charger();
  }

  Future<void> _detail(Enregistrement ph) async {
    final commentaire = TextEditingController(text: (ph.donnees['commentaire'] as String?) ?? '');
    String? lien = ph.donnees['visite_pathologie_id'] as String?;
    if (lien != null && !widget.pathologies.any((p) => p.visitePathologieId == lien)) lien = null;
    final action = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, maj) => AlertDialog(
          contentPadding: const EdgeInsets.all(8),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              if (_apercus[ph.id] != null)
                InteractiveViewer(maxScale: 6, child: Image.memory(_apercus[ph.id]!, fit: BoxFit.contain))
              else
                Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_transferee(ph)
                        ? 'Photographie transférée au poste central et effacée du téléphone. '
                            'Elle se consulte sur le poste central.'
                        : 'Aperçu indisponible.')),
              const SizedBox(height: 8),
              TextField(
                controller: commentaire,
                enabled: _peutPrendre,
                decoration: const InputDecoration(labelText: 'Commentaire / description'),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: lien,
                decoration: const InputDecoration(labelText: 'Pathologie ou anomalie associée'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final p in widget.pathologies) DropdownMenuItem(value: p.visitePathologieId, child: Text(p.libelle)),
                ],
                onChanged: _peutPrendre ? (v) => maj(() => lien = v) : null,
              ),
            ]),
          ),
          actions: [
            if (_peutPrendre) ...[
              TextButton(onPressed: () => Navigator.pop(c, 'supprimer'), child: const Text('Supprimer')),
              TextButton(onPressed: () => Navigator.pop(c, 'remplacer'), child: const Text('Remplacer')),
              FilledButton(onPressed: () => Navigator.pop(c, 'enregistrer'), child: const Text('Enregistrer')),
            ] else
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
          ],
        ),
      ),
    );
    final texte = commentaire.text.trim();
    commentaire.dispose();
    final utilisateurId = widget.session.utilisateur.id;
    switch (action) {
      case 'enregistrer':
        await widget.service.modifier(ph,
            commentaire: texte.isEmpty ? null : texte,
            visitePathologieId: lien,
            utilisateurId: utilisateurId,
            aTransmettre: widget.aTransmettre);
      case 'supprimer':
        await widget.service.supprimer(ph, utilisateurId: utilisateurId);
        _apercus.remove(ph.id);
      case 'remplacer':
        await _ajouter(remplace: ph);
        return;
    }
    await _charger();
  }

  @override
  Widget build(BuildContext context) {
    if (!_charge) return const Center(child: CircularProgressIndicator());
    final consentementObtenu = _consentement != null;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        color: consentementObtenu ? Colors.green.shade50 : Colors.orange.shade50,
        child: ListTile(
          leading: Icon(consentementObtenu ? Icons.verified_user : Icons.gpp_maybe),
          title: Text(consentementObtenu
              ? 'Consentement obtenu (${_consentement!.donnees['forme'] == 'ecrit' ? 'écrit' : 'oral'}) : '
                  '${_consentement!.donnees['nom_repondant']}'
              : 'Consentement du parent ou tuteur non renseigné'),
          trailing: !consentementObtenu && _peutPrendre
              ? TextButton(onPressed: _saisirConsentement, child: const Text('Renseigner'))
              : null,
        ),
      ),
      const SizedBox(height: 12),
      if (_peutPrendre)
        FilledButton.icon(
          onPressed: consentementObtenu && !_enCours ? _ajouter : null,
          icon: _enCours
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_a_photo),
          label: const Text('+ PRENDRE UNE PHOTO / JOINDRE UNE PHOTO'),
        ),
      const SizedBox(height: 12),
      if (_photos.isEmpty) const Text('Aucune photographie pour cette visite.'),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (final ph in _photos)
            InkWell(
              onTap: () => _detail(ph),
              child: Stack(fit: StackFit.expand, children: [
                if (_apercus[ph.id] != null)
                  Image.memory(_apercus[ph.id]!, fit: BoxFit.cover, cacheWidth: 300)
                else if (_transferee(ph))
                  const ColoredBox(
                    color: Colors.black12,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.cloud_done),
                      Padding(
                        padding: EdgeInsets.all(4),
                        child: Text('Transférée au poste central', textAlign: TextAlign.center, style: TextStyle(fontSize: 11)),
                      ),
                    ]),
                  )
                else
                  const ColoredBox(color: Colors.black12, child: Icon(Icons.image_not_supported)),
                if (ph.donnees['commentaire'] != null)
                  const Positioned(right: 4, bottom: 4, child: Icon(Icons.comment, color: Colors.white, size: 18)),
              ]),
            ),
        ],
      ),
    ]);
  }
}
