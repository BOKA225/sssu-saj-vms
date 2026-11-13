import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../import/ecran_import.dart';
import '../inspection/ecran_inspection.dart';
import '../services.dart';
import '../statistiques/ecran_statistiques.dart';
import '../sync/synchro_auto.dart';
import 'ecran_a_verifier.dart';
import 'ecran_appairage.dart';
import 'ecran_ebauches.dart';
import 'etablissements.dart';

/// Accueil : accès aux établissements et aux élèves, à l'importation des
/// listes et aux ébauches ; état de connexion et de synchronisation, bouton
/// SYNCHRONISER MES DONNÉES, code PIN.
class EcranAccueil extends ConsumerStatefulWidget {
  const EcranAccueil({super.key});

  @override
  ConsumerState<EcranAccueil> createState() => _EcranAccueilState();
}

class _EcranAccueilState extends ConsumerState<EcranAccueil> {
  bool? _joignable;
  Map<EtatSync, int> _etats = const {};
  bool _synchro = false;
  String? _dernierRapport;
  SynchroAutomatique? _auto;

  @override
  void initState() {
    super.initState();
    _actualiser();
    // Synchronisation automatique au retour du réseau et toutes les 15 minutes.
    _auto = SynchroAutomatique(ref.read(servicesProvider), apres: (r, e) {
      if (!mounted || ref.read(servicesProvider).bloque.value) return;
      if (r != null) _dernierRapport = 'Synchronisation automatique : $r';
      // Refus du poste (mise à jour de l'application requise…) : affiché ;
      // une simple absence de réseau reste silencieuse.
      if (e is ErreurProtocole) _dernierRapport = 'Synchronisation automatique impossible : ${e.message}';
      _actualiser();
    })
      ..demarrer();
  }

  @override
  void dispose() {
    _auto?.arreter();
    super.dispose();
  }

  Future<void> _actualiser() async {
    final s = ref.read(servicesProvider);
    // Compte supprimé ou désactivé sur le poste central (reçu à la
    // synchronisation) : la session en cours est fermée.
    final session = ref.read(sessionProvider);
    if (session != null) {
      final u = await s.auth.depot.parId(session.utilisateur.id);
      if (u == null || !u.actif) {
        if (mounted) ref.read(sessionProvider.notifier).state = null;
        return;
      }
    }
    final etats = await s.depot.compterEtats();
    final joignable = await s.posteCentralJoignable();
    if (!mounted) return;
    setState(() {
      _etats = etats;
      _joignable = joignable;
    });
  }

  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ecran));
    _actualiser();
  }

  Widget _entree(IconData icone, String titre, String sousTitre, Widget ecran) => Card(
        child: ListTile(
          leading: Icon(icone, size: 32),
          title: Text(titre, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          subtitle: Text(sousTitre),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _ouvrir(ecran),
        ),
      );

  Future<void> _synchroniser() async {
    setState(() => _synchro = true);
    try {
      final r = await ref.read(servicesProvider).synchroniser();
      _dernierRapport = 'Synchronisation terminée : $r'
          '${r.motifs.isEmpty ? '' : '\nÀ vérifier sur le poste central :\n${r.motifs.join('\n')}'}';
    } on ErreurProtocole catch (e) {
      _dernierRapport = 'Échec : ${e.message}';
      if (e.code == 'appareil_inconnu' && mounted) {
        setState(() => _synchro = false);
        await _proposerReappairage();
        return;
      }
    } on TelephoneBloque {
      return; // l'écran « Téléphone bloqué » remplace l'application
    } catch (e) {
      _dernierRapport = 'Échec : ${messageErreurSynchronisation(e)}';
    }
    if (!mounted) return;
    setState(() => _synchro = false);
    await _actualiser();
  }

  /// Le poste central ne reconnaît plus ce téléphone (restauration d'une
  /// sauvegarde antérieure à son appairage) : nouvel appairage, données gardées.
  Future<void> _proposerReappairage() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Téléphone non reconnu'),
        content: const Text('Le poste central ne reconnaît plus ce téléphone, sans doute après la restauration d\'une '
            'sauvegarde. Demandez un nouveau QR code d\'appairage à l\'administrateur. Les données du téléphone '
            'sont conservées et seront transmises après l\'appairage.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Plus tard')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Appairer de nouveau')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (c) => EcranAppairage(onAppaire: () => Navigator.pop(c))));
    if (mounted) await _actualiser();
  }

  Future<void> _definirPin(Session session) async {
    final ctrl = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Code PIN de déverrouillage'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          decoration: const InputDecoration(labelText: '6 chiffres'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Enregistrer')),
        ],
      ),
    );
    ctrl.dispose();
    if (pin == null || !mounted) return;
    try {
      final maj = await ref.read(servicesProvider).auth.definirPin(session, pin);
      ref.read(sessionProvider.notifier).state = maj;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code PIN enregistré.')));
    } on ErreurSaisie catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    final u = session.utilisateur;
    final couleurs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SSSU-SAJ VMS'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              _joignable == true ? Icons.wifi : Icons.wifi_off,
              semanticLabel: _joignable == true ? 'Poste central joignable' : 'Hors connexion',
            ),
          ),
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(sessionProvider.notifier).state = null,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _actualiser,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(u.nomAffiche),
                subtitle: Text('${session.droits.role.libelle}${u.fonction == null ? '' : ' · ${u.fonction}'}'),
              ),
            ),
            _entree(Icons.school, 'Établissements et élèves', 'Classes, effectifs, visites, nouvelle visite',
                const EcranEtablissements()),
            _entree(Icons.search, 'Rechercher un élève', 'Par nom, prénoms ou matricule', const EcranRechercheEleve()),
            if (session.droits.peut(Permission.visiteSaisir))
              _entree(Icons.edit_note, 'Ébauches', 'Visites commencées ou non transmises', const EcranEbauches()),
            if ((_etats[EtatSync.conflit] ?? 0) > 0)
              _entree(Icons.report_problem, 'Éléments à vérifier',
                  '${_etats[EtatSync.conflit]} élément(s) non accepté(s) par le poste central', const EcranAVerifier()),
            if (session.droits.peut(Permission.inspectionRealiser))
              _entree(Icons.fact_check, 'Inspection sanitaire', 'Grille d\'inspection des établissements scolaires',
                  const EcranInspections()),
            if (session.droits.peut(Permission.statistiquesConsulter))
              _entree(Icons.bar_chart, 'Statistiques', 'Couverture, pathologies, inspections (données du téléphone)',
                  const EcranStatistiques()),
            if (session.droits.peut(Permission.importExecuter))
              _entree(Icons.upload_file, 'Importer une liste d\'élèves', 'Excel, CSV, PDF ou photo d\'une liste',
                  const EcranImport()),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Données du téléphone', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('En attente de synchronisation : ${_etats[EtatSync.enAttente] ?? 0}'),
                    Text('Synchronisées : ${_etats[EtatSync.synchronise] ?? 0}'),
                    Text('Enregistrées localement (ébauches) : ${_etats[EtatSync.local] ?? 0}'),
                    if ((_etats[EtatSync.conflit] ?? 0) > 0)
                      Text('En conflit : ${_etats[EtatSync.conflit]}', style: TextStyle(color: couleurs.error)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _synchro ? null : _synchroniser,
              icon: _synchro
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
              label: const Text('SYNCHRONISER MES DONNÉES'),
            ),
            if (_dernierRapport != null) Padding(padding: const EdgeInsets.all(8), child: Text(_dernierRapport!)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _definirPin(session),
              icon: const Icon(Icons.pin),
              label: Text(u.hashPin == null ? 'Définir mon code PIN' : 'Changer mon code PIN'),
            ),
          ],
        ),
      ),
    );
  }
}
