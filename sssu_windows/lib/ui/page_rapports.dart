/// Rapports et exportation (section 13) : listes des élèves examinés et non
/// examinés, élèves référés et à suivre, rapports par établissement, par
/// classe et annuels, rapport des pathologies, synthèse des inspections.
/// Formats PDF et Excel. Les fiches individuelles de visite s'éditent depuis
/// le dossier de l'élève, les rapports d'inspection depuis la page Inspections.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../rapports/service_rapports.dart';
import '../services.dart';
import 'commun.dart';
import 'statistiques_commun.dart';

/// Demande où enregistrer le rapport, le rend et trace l'export.
Future<void> exporterRapport(BuildContext context, ServicesPoste s, Droits acteur, DocumentRapport Function() composer,
    FormatRapport format, {String? table, String? id}) async {
  final DocumentRapport d;
  try {
    d = composer();
  } on RapportRefuse catch (e) {
    message(context, e.message);
    return;
  }
  final chemin = await FilePicker.platform.saveFile(
    dialogTitle: 'Enregistrer le rapport (${format.libelle})',
    fileName: nomFichierRapport(d, format.extension),
    type: FileType.custom,
    allowedExtensions: [format.extension],
  );
  if (chemin == null) return;
  final complet = chemin.toLowerCase().endsWith('.${format.extension}') ? chemin : '$chemin.${format.extension}';
  try {
    await s.rapports.enregistrer(d, format, complet, acteur: acteur, table: table, id: id);
    if (context.mounted) message(context, 'Rapport enregistré : $complet');
  } catch (e) {
    if (context.mounted) message(context, 'Échec de l\'enregistrement : $e');
  }
}

enum TypeRapport {
  annuel('Rapport annuel (district)', 'Indicateurs, couverture par établissement et par classe, conclusions, pathologies, inspections, évolution.', false),
  etablissement('Rapport par établissement', 'Même contenu, pour l\'établissement choisi.', false),
  classe('Rapport par classe', 'Couverture, conclusions et pathologies de la classe choisie.', false),
  pathologies('Rapport statistique des pathologies', 'Cas, sexe, tranches d\'âge, établissements, classes, prévalence.', false),
  inspections('Synthèse des inspections sanitaires', 'Établissements inspectés, niveaux, insuffisances, historique.', false),
  examines('Liste des élèves examinés', 'Liste nominative, avec la date de la dernière visite.', true),
  nonExamines('Liste des élèves non examinés', 'Liste nominative des élèves restant à voir.', true),
  suivis('Élèves référés et à suivre', 'Diagnostic, structure de référence ou date de contrôle, contact.', true);

  final String titre;
  final String description;
  final bool nominatif;
  const TypeRapport(this.titre, this.description, this.nominatif);
}

class PageRapports extends ConsumerStatefulWidget {
  const PageRapports({super.key});
  @override
  ConsumerState<PageRapports> createState() => _PageRapportsState();
}

class _PageRapportsState extends ConsumerState<PageRapports> {
  late final Droits _droits = ref.read(sessionProvider)!.droits;
  late final ControleurStatistiques _c = ControleurStatistiques(ref.read(servicesProvider),
      identite: _droits.peut(Permission.rapportExporterNominatif));
  TypeRapport _type = TypeRapport.annuel;
  FormatRapport _format = FormatRapport.pdf;
  bool _occupe = false;

  @override
  void initState() {
    super.initState();
    _c.demarrer();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  DocumentRapport _composer(EnteteRapport entete) {
    final jeu = _c.jeu!;
    final f = _c.filtre;
    final m = DateTime.now().toUtc();
    return switch (_type) {
      TypeRapport.annuel =>
        rapportStatistique(jeu, f, portee: PorteeRapport.annuel, entete: entete, acteur: _droits, genereLe: m),
      TypeRapport.etablissement =>
        rapportStatistique(jeu, f, portee: PorteeRapport.etablissement, entete: entete, acteur: _droits, genereLe: m),
      TypeRapport.classe =>
        rapportStatistique(jeu, f, portee: PorteeRapport.classe, entete: entete, acteur: _droits, genereLe: m),
      TypeRapport.pathologies => rapportPathologies(jeu, f, entete: entete, acteur: _droits, genereLe: m),
      TypeRapport.inspections => rapportHistoriqueInspections(jeu,
          etablissementId: f.etablissementId, entete: entete, acteur: _droits, genereLe: m),
      TypeRapport.examines => rapportListeEleves(jeu, f, examines: true, entete: entete, acteur: _droits, genereLe: m),
      TypeRapport.nonExamines => rapportListeEleves(jeu, f, examines: false, entete: entete, acteur: _droits, genereLe: m),
      TypeRapport.suivis => rapportSuivis(jeu, f, entete: entete, acteur: _droits, genereLe: m),
    };
  }

  Future<void> _generer() async {
    final s = ref.read(servicesProvider);
    setState(() => _occupe = true);
    try {
      final entete = await s.rapports.entete();
      if (!mounted) return;
      await exporterRapport(context, s, _droits, () => _composer(entete), _format,
          table: _c.etablissementId == null ? 'annee_scolaire' : 'etablissement',
          id: _c.etablissementId ?? _c.annee?.id);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final types = TypeRapport.values.where((t) => !t.nominatif || _droits.peut(Permission.rapportExporterNominatif));
          return ListView(padding: const EdgeInsets.all(24), children: [
            Text('Rapports et exportation', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text('L\'en-tête institutionnel, le logo et le nom du Médecin-Chef se règlent dans les Paramètres. '
                'Les fiches individuelles s\'éditent depuis le dossier de l\'élève ; les rapports d\'inspection depuis '
                'la page Inspections.'),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('1. Rapport', style: Theme.of(context).textTheme.titleMedium),
                  for (final t in types)
                    RadioListTile<TypeRapport>(
                      value: t,
                      groupValue: _type,
                      onChanged: (v) => setState(() => _type = v!),
                      title: Text(t.titre + (t.nominatif ? '  (nominatif, confidentiel)' : '')),
                      subtitle: Text(t.description),
                      dense: true,
                    ),
                ]),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('2. Périmètre', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  BarreFiltres(_c,
                      classe: _type != TypeRapport.inspections,
                      sexe: _type != TypeRapport.inspections,
                      periode: _type != TypeRapport.inspections),
                  if (_type == TypeRapport.etablissement && _c.etablissementId == null)
                    const Text('Choisissez l\'établissement.', style: TextStyle(color: Colors.red)),
                  if (_type == TypeRapport.classe && _c.classeId == null)
                    const Text('Choisissez la classe.', style: TextStyle(color: Colors.red)),
                ]),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Text('3. Format', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: 24),
                  SegmentedButton<FormatRapport>(
                    segments: const [
                      ButtonSegment(value: FormatRapport.pdf, label: Text('PDF'), icon: Icon(Icons.picture_as_pdf)),
                      ButtonSegment(value: FormatRapport.word, label: Text('Word'), icon: Icon(Icons.description)),
                      ButtonSegment(value: FormatRapport.excel, label: Text('Excel'), icon: Icon(Icons.table_chart)),
                    ],
                    selected: {_format},
                    onSelectionChanged: (s) => setState(() => _format = s.first),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _occupe || _c.jeu == null || _c.chargement ? null : _generer,
                    icon: _occupe
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download),
                    label: const Text('Générer et enregistrer'),
                  ),
                ]),
              ),
            ),
            if (_type.nominatif)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Document nominatif couvert par le secret médical : son édition est tracée dans le journal '
                    'd\'audit. Conservez-le en lieu sûr.', style: TextStyle(fontStyle: FontStyle.italic)),
              ),
          ]);
        },
      );
}
