/// Consultation d'une visite médicale (rubriques A à F), validation et
/// réouverture par les personnes habilitées.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../rapports/service_rapports.dart';
import '../services.dart';
import 'commun.dart';
import 'page_rapports.dart';

class DetailVisite extends ConsumerStatefulWidget {
  final String visiteId;
  const DetailVisite({super.key, required this.visiteId});
  @override
  ConsumerState<DetailVisite> createState() => _DetailVisiteState();
}

class _DetailVisiteState extends ConsumerState<DetailVisite> {
  Enregistrement? _visite;
  Enregistrement? _eleve;
  List<Enregistrement> _antecedents = const [];
  List<Enregistrement> _examens = const [];
  List<Enregistrement> _pathologies = const [];
  List<Enregistrement> _consentements = const [];
  Map<String, String> _libelles = const {};
  Map<String, String> _noms = const {};

  ServicesPoste get _s => ref.read(servicesProvider);
  Droits get _droits => ref.read(sessionProvider)!.droits;

  @override
  void initState() {
    super.initState();
    _s.gestion.noterAcces(_droits, 'consultation', table: 'visite', id: widget.visiteId);
    _charger();
  }

  Future<void> _charger() async {
    final r = await _s.depot.transaction((tx) async {
      final v = await tx.lire('visite', widget.visiteId);
      return (
        v,
        v == null ? null : await tx.lire('eleve', v.donnees['eleve_id']! as String),
        await tx.chercher('antecedent', {'visite_id': widget.visiteId}),
        await tx.chercher('examen_appareil', {'visite_id': widget.visiteId}),
        await tx.chercher('visite_pathologie', {'visite_id': widget.visiteId}),
        await tx.chercher('consentement', {'visite_id': widget.visiteId}),
      );
    });
    final libelles = await _s.requetes.libellesPathologies();
    final noms = await _s.requetes.nomsUtilisateurs();
    if (!mounted) return;
    final (visite, eleve, antecedents, examens, pathologies, consentements) = r;
    setState(() {
      _visite = visite;
      _eleve = eleve;
      _antecedents = antecedents;
      _examens = examens;
      _pathologies = pathologies;
      _consentements = consentements;
      _libelles = libelles;
      _noms = noms;
    });
  }

  Future<void> _valider() async {
    if (!await confirmer(context, 'Valider cette visite ?', 'Une visite validée ne peut plus être modifiée sur les téléphones.')) return;
    if (!mounted) return;
    await executer(context, () => _s.gestion.validerVisite(_droits, widget.visiteId), succes: 'Visite validée.');
    _charger();
  }

  Future<void> _rouvrir() async {
    final motif = await saisir(context, 'Rouvrir la visite', 'Motif de la réouverture (obligatoire)');
    if (motif == null || !mounted) return;
    await executer(context, () => _s.gestion.rouvrirVisite(_droits, widget.visiteId, motif: motif),
        succes: 'Visite rouverte : l\'agent pourra la corriger sur son téléphone puis la valider de nouveau.');
    _charger();
  }

  Widget _ligne(String libelle, Object? valeur) => valeur == null || '$valeur'.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 230, child: Text(libelle, style: const TextStyle(color: Colors.black54))),
            Expanded(child: Text('$valeur')),
          ]),
        );

  /// Fiche individuelle de visite (PDF). Les photographies n'y sont
  /// intégrées que sur demande, pour les profils qui voient les photos.
  Future<void> _fiche() async {
    final fv = await _s.depot.transaction((tx) => FicheVisite.charger(tx, widget.visiteId));
    var avecPhotos = false;
    if (fv.photos.isNotEmpty && _droits.peut(Permission.photoVoirToutes) && mounted) {
      final r = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Fiche individuelle de visite'),
          content: Text('Cette visite comporte ${fv.photos.length} photographie(s) clinique(s). '
              'Les intégrer à la fiche ? (l\'édition est tracée dans le journal d\'audit)'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
            OutlinedButton(onPressed: () => Navigator.pop(d, false), child: const Text('Sans les photos')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Avec les photos')),
          ],
        ),
      );
      if (r == null) return;
      avecPhotos = r;
    }
    final commentaires = <String, String?>{};
    if (avecPhotos) {
      await _s.depot.transaction((tx) async {
        for (final id in fv.photos) {
          final p = await tx.lire('photo', id);
          commentaires[id] = [dateFr(p?.donnees['pris_le']), p?.donnees['commentaire']].whereType<String>().join(' – ');
        }
      });
    }
    final photos = avecPhotos ? await _s.rapports.photosVisite(fv, commentaires) : const <PhotoRapport>[];
    final entete = await _s.rapports.entete();
    if (!mounted) return;
    await exporterRapport(
      context,
      _s,
      _droits,
      () => ficheVisite(fv, entete: entete, acteur: _droits, genereLe: DateTime.now().toUtc(), photos: photos),
      FormatRapport.pdf,
      table: 'visite',
      id: widget.visiteId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _visite;
    if (v == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final d = v.donnees;
    final e = _eleve?.donnees ?? const {};
    final statut = d['statut'] as String;
    final imc = d['imc'] == null
        ? null
        : '${d['imc']} kg/m²${d['imc_interpretation'] == null ? '' : ' · ${CategorieImc.values.firstWhere((c) => c.code == d['imc_interpretation']).libelle}'}';
    return Scaffold(
      appBar: AppBar(
        title: Text('Visite du ${dateFr(d['date_visite'])} · ${e['nom'] ?? ''} ${e['prenoms'] ?? ''}'),
        actions: [
          if (_droits.peut(Permission.rapportExporterNominatif))
            TextButton.icon(
              onPressed: _fiche,
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              label: const Text('Fiche individuelle', style: TextStyle(color: Colors.white)),
            ),
          if (statut != 'valide' && statut != 'ebauche' && _droits.peut(Permission.visiteValider))
            TextButton.icon(
              onPressed: _valider,
              icon: const Icon(Icons.verified, color: Colors.white),
              label: const Text('Valider', style: TextStyle(color: Colors.white)),
            ),
          if (statut == 'valide' && _droits.peut(Permission.visiteRouvrir))
            TextButton.icon(
              onPressed: _rouvrir,
              icon: const Icon(Icons.lock_open, color: Colors.white),
              label: const Text('Rouvrir', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Bloc(titre: 'A. Identification', enfants: [
          _ligne('Statut', libelleStatutVisite(statut)),
          _ligne('Élève', '${e['nom'] ?? ''} ${e['prenoms'] ?? ''} · ${e['matricule'] ?? 'sans matricule'}'),
          if (e['date_naissance'] != null)
            _ligne('Âge à la visite',
                '${calculerAge(lireDate(e['date_naissance'] as String), lireDate(d['date_visite'] as String))}'),
          _ligne('Agent de santé', _noms[d['agent_id']]),
          _ligne('Structure d\'origine', d['structure_origine']),
          if (statut == 'valide') _ligne('Validée par', '${_noms[d['validateur_id']] ?? '?'} le ${dateHeureFr(d['valide_le'])}'),
        ]),
        Bloc(titre: 'B. Antécédents', enfants: [
          if (_antecedents.isEmpty) const Text('Aucun antécédent renseigné.'),
          for (final a in _antecedents)
            _ligne(TypeAntecedent.depuisCode(a.donnees['type']! as String).libelle,
                [if (a.donnees['coche'] == true) 'Oui', a.donnees['commentaire']].whereType<String>().join(' · ')),
        ]),
        Bloc(titre: 'C. Examen clinique', enfants: [
          _ligne('Poids', d['poids_kg'] == null ? null : '${d['poids_kg']} kg'),
          _ligne('Taille', d['taille_cm'] == null ? null : '${d['taille_cm']} cm'),
          _ligne('IMC', imc),
          _ligne('Tension artérielle', d['ta_sys'] == null ? null : '${d['ta_sys']} / ${d['ta_dia']} mmHg'),
          _ligne('Température', d['temperature_c'] == null ? null : '${d['temperature_c']} °C'),
          _ligne('Fréquence cardiaque', d['fc'] == null ? null : '${d['fc']} battements/min'),
          _ligne('Fréquence respiratoire', d['fr'] == null ? null : '${d['fr']} cycles/min'),
        ]),
        Bloc(titre: 'D. Examen physique par appareil', enfants: [
          if (_examens.isEmpty) const Text('Aucun appareil examiné.'),
          for (final x in _examens)
            _ligne(AppareilExamen.depuisCode(x.donnees['appareil']! as String).libelle,
                [ResultatExamen.depuisCode(x.donnees['resultat']! as String).libelle, x.donnees['observation']].whereType<String>().join(' · ')),
        ]),
        Bloc(titre: 'E. Pathologies dépistées', enfants: [
          if (_pathologies.isEmpty) const Text('Aucune.'),
          for (final p in _pathologies)
            _ligne(_libelles[p.donnees['pathologie_id']] ?? 'Pathologie', p.donnees['precision'] ?? ''),
        ]),
        Bloc(titre: 'F. Conclusion', enfants: [
          _ligne('Conclusion', libelleConclusion(d['conclusion'] as String?)),
          _ligne('Diagnostic', d['diagnostic']),
          _ligne('Conduite à tenir', d['conduite_a_tenir']),
          _ligne('Traitement ou conseils', d['traitement_conseils']),
          _ligne('Structure de référence', d['structure_reference']),
          _ligne('Rendez-vous de contrôle', d['date_controle'] == null ? null : dateFr(d['date_controle'])),
          _ligne('Observations', d['observations']),
        ]),
        Bloc(titre: 'Consentement aux photographies', enfants: [
          if (_consentements.isEmpty) const Text('Non renseigné.'),
          for (final c in _consentements)
            Text(c.donnees['obtenu'] == true
                ? 'Obtenu (${c.donnees['forme']}) de ${c.donnees['nom_repondant']}'
                    '${c.donnees['lien_parente'] == null ? '' : ' (${c.donnees['lien_parente']})'} le ${dateFr(c.donnees['date_consentement'])}'
                : 'Refusé le ${dateFr(c.donnees['date_consentement'])}'),
        ]),
      ]),
    );
  }
}
