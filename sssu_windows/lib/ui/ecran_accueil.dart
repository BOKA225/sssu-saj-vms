import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sssu_core/sssu_core.dart';

import '../services.dart';
import 'commun.dart';
import 'page_conflits.dart';
import 'page_inspections.dart';
import 'page_parametres.dart';
import 'page_rapports.dart';
import 'page_sauvegardes.dart';
import 'page_statistiques.dart';
import 'statistiques_commun.dart';
import 'page_eleves.dart';
import 'page_etablissements.dart';
import 'page_import.dart';
import 'page_journaux.dart';

/// Poste central : tableau de bord, établissements, dossiers, importation,
/// statistiques, inspections sanitaires, rapports, téléphones, comptes,
/// conflits de synchronisation, journaux et paramètres.
class EcranAccueil extends ConsumerStatefulWidget {
  const EcranAccueil({super.key});

  @override
  ConsumerState<EcranAccueil> createState() => _EcranAccueilState();
}

class _EcranAccueilState extends ConsumerState<EcranAccueil> {
  int _page = 0;
  Timer? _verrou;
  Duration _delai = const Duration(minutes: 15);

  @override
  void initState() {
    super.initState();
    _activite();
    // Délai réglé dans les paramètres (15 minutes par défaut).
    ref.read(servicesProvider).statistiques.parametres().then((p) {
      final m = int.tryParse(p['verrouillage_windows_minutes'] ?? '');
      if (m != null && m >= 1 && mounted) {
        _delai = Duration(minutes: m);
        _activite();
      }
    }).catchError((_) {});
  }

  /// Verrouillage après une période sans interaction.
  void _activite() {
    _verrou?.cancel();
    _verrou = Timer(_delai, () => ref.read(sessionProvider.notifier).state = null);
  }

  @override
  void dispose() {
    _verrou?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    final pages = <(NavigationRailDestination, Widget)>[
      (
        const NavigationRailDestination(icon: Icon(Icons.dashboard), label: Text('Tableau de bord')),
        const _PageEtat()
      ),
      (const NavigationRailDestination(icon: Icon(Icons.school), label: Text('Établissements')), const PageEtablissements()),
      (const NavigationRailDestination(icon: Icon(Icons.folder_shared), label: Text('Élèves et dossiers')), const PageEleves()),
      if (session.droits.peut(Permission.importExecuter))
        (const NavigationRailDestination(icon: Icon(Icons.upload_file), label: Text('Importer une liste')), const PageImport()),
      if (session.droits.peut(Permission.statistiquesConsulter))
        (const NavigationRailDestination(icon: Icon(Icons.bar_chart), label: Text('Statistiques')), const PageStatistiques()),
      if (session.droits.peut(Permission.inspectionRealiser) || session.droits.peut(Permission.statistiquesConsulter))
        (const NavigationRailDestination(icon: Icon(Icons.fact_check), label: Text('Inspections')), const PageInspections()),
      if (session.droits.peut(Permission.statistiquesConsulter))
        (const NavigationRailDestination(icon: Icon(Icons.description), label: Text('Rapports')), const PageRapports()),
      if (session.droits.peut(Permission.comptesGerer)) ...[
        (const NavigationRailDestination(icon: Icon(Icons.phone_android), label: Text('Téléphones')), const _PageAppareils()),
        (const NavigationRailDestination(icon: Icon(Icons.people), label: Text('Comptes')), const _PageComptes()),
      ],
      if (session.droits.peut(Permission.conflitResoudre))
        (const NavigationRailDestination(icon: Icon(Icons.call_split), label: Text('Conflits')), const PageConflits()),
      if (session.droits.peut(Permission.comptesGerer) || session.droits.peut(Permission.conflitResoudre))
        (const NavigationRailDestination(icon: Icon(Icons.sync), label: Text('Synchronisations')), const PageSynchronisations()),
      if (session.droits.peut(Permission.auditConsulter))
        (const NavigationRailDestination(icon: Icon(Icons.history), label: Text('Journal d\'audit')), const PageJournal()),
      if (session.droits.peut(Permission.parametresModifier))
        (const NavigationRailDestination(icon: Icon(Icons.settings), label: Text('Paramètres')), const PageParametres()),
      if (session.droits.peut(Permission.sauvegardeGerer))
        (const NavigationRailDestination(icon: Icon(Icons.backup), label: Text('Sauvegardes')), const PageSauvegardes()),
    ];
    final page = _page.clamp(0, pages.length - 1);
    return Listener(
      onPointerDown: (_) => _activite(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SSSU-SAJ VMS – Poste central'),
          actions: [
            Center(child: Text('${session.utilisateur.nomAffiche} · ${session.droits.role.libelle}')),
            IconButton(
              tooltip: 'Se déconnecter',
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(sessionProvider.notifier).state = null,
            ),
          ],
        ),
        body: Row(
          children: [
            // Menu défilant : il reste utilisable sur un petit écran.
            LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      selectedIndex: page,
                      labelType: NavigationRailLabelType.all,
                      onDestinationSelected: (i) => setState(() => _page = i),
                      destinations: [for (final p in pages) p.$1],
                    ),
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: pages[page].$2),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- État

class _PageEtat extends ConsumerStatefulWidget {
  const _PageEtat();
  @override
  ConsumerState<_PageEtat> createState() => _PageEtatState();
}

class _PageEtatState extends ConsumerState<_PageEtat> {
  late final ControleurStatistiques _c = ControleurStatistiques(ref.read(servicesProvider));
  Map<String, int>? _technique;

  @override
  void initState() {
    super.initState();
    _c.demarrer();
    _c.addListener(_chargerTechnique);
    _chargerTechnique();
  }

  @override
  void dispose() {
    _c.removeListener(_chargerTechnique);
    _c.dispose();
    super.dispose();
  }

  /// Téléphones et conflits (compteurs techniques, hors filtres).
  Future<void> _chargerTechnique() async {
    if (_c.chargement) return;
    final r = await ref.read(servicesProvider).depot.requete(
        'SELECT (SELECT COUNT(*) FROM appareil WHERE deleted_at IS NULL AND NOT bloque) AS telephones, '
        "(SELECT COUNT(*) FROM conflit WHERE statut = 'ouvert') AS conflits");
    final reglages = await ref.read(servicesProvider).sauvegardes.reglages();
    final derniere = reglages.derniereReussie?.toLocal();
    if (mounted) {
      setState(() {
        _technique = {
          'telephones': (r.single['telephones'] as num).toInt(),
          'conflits': (r.single['conflits'] as num).toInt(),
        };
        _sauvegarde = derniere == null
            ? 'Aucune sauvegarde réussie'
            : 'Dernière sauvegarde : ${derniere.day.toString().padLeft(2, '0')}/${derniere.month.toString().padLeft(2, '0')} '
                'à ${derniere.hour.toString().padLeft(2, '0')} h ${derniere.minute.toString().padLeft(2, '0')}';
        _sauvegardeRecente = derniere != null && DateTime.now().difference(derniere) < const Duration(hours: 36);
      });
    }
  }

  String? _sauvegarde;
  bool _sauvegardeRecente = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(servicesProvider);
    final session = ref.watch(sessionProvider)!;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final st = _c.statistiques;
        final jeu = _c.jeu;
        // Visites du périmètre par statut (les ébauches restent sur les téléphones).
        final parStatut = <StatutVisite, int>{};
        if (jeu != null) {
          final p = perimetre(jeu, _c.filtre);
          for (final l in p.visitesParEleve.values) {
            for (final v in l) {
              parStatut[v.statut] = (parStatut[v.statut] ?? 0) + 1;
            }
          }
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              _etat(s.serveurActif ? Colors.green : Colors.red,
                  s.serveurActif ? 'Serveur de synchronisation actif (port ${s.port})' : 'Serveur arrêté'),
              _etat(s.decouverteActive ? Colors.green : Colors.orange,
                  s.decouverteActive ? 'Découverte Wi-Fi active' : 'Découverte Wi-Fi indisponible'),
              _etat(s.config.adresseInternet == null ? Colors.grey : Colors.green,
                  s.config.adresseInternet == null ? 'Internet non configuré' : 'Internet : ${s.config.adresseInternet}'),
              if (_sauvegarde != null) _etat(_sauvegardeRecente ? Colors.green : Colors.red, _sauvegarde!),
              if (_technique != null) ...[
                _etat(Colors.blueGrey, '${_technique!['telephones']} téléphone(s) appairé(s)'),
                _etat(_technique!['conflits']! > 0 ? Colors.orange : Colors.green,
                    '${_technique!['conflits']} conflit(s) à examiner'),
              ],
            ]),
            const SizedBox(height: 4),
            SelectableText('Empreinte du certificat : ${s.certificat.empreinte}',
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
            const Divider(height: 24),
            BarreFiltres(_c, periode: false),
            const SizedBox(height: 8),
            if (_c.erreur != null)
              Text('Lecture impossible : ${_c.erreur}')
            else if (st == null)
              Center(child: _c.annee == null && !_c.chargement ? const Text('Aucune année scolaire.') : const CircularProgressIndicator())
            else if (!session.droits.peut(Permission.statistiquesConsulter))
              const Text('Votre profil ne donne pas accès aux statistiques.')
            else ...[
              Wrap(children: cartesGenerales(st)),
              Wrap(children: [
                CarteIndicateur('${parStatut[StatutVisite.enAttente] ?? 0}', 'Visites reçues à valider',
                    detail: 'transmises par les téléphones', icone: Icons.sync),
                CarteIndicateur('${parStatut[StatutVisite.synchronise] ?? 0}', 'Visites synchronisées', icone: Icons.cloud_done),
                CarteIndicateur('${parStatut[StatutVisite.valide] ?? 0}', 'Visites validées',
                    icone: Icons.verified, couleur: Colors.green.shade700),
              ]),
              Wrap(children: [
                Panneau(
                    'Couverture par ${_c.etablissementId == null && st.parEtablissement.length > 1 ? 'établissement' : 'classe'}',
                    histogrammeCouverture(
                        _c.etablissementId == null && _c.classeId == null && st.parEtablissement.length > 1
                            ? st.parEtablissement
                            : st.parClasse),
                    largeur: 620,
                    hauteur: 240),
                Panneau(
                    'Garçons et filles examinés',
                    camembert([
                      ('Garçons', st.generale.garconsExamines, couleurGarcons),
                      ('Filles', st.generale.fillesExamines, couleurFilles),
                    ]),
                    largeur: 360,
                    hauteur: 200),
                Panneau('Évolution de la couverture', courbeEvolution(st.evolution), largeur: 620, hauteur: 220),
              ]),
            ],
          ],
        );
      },
    );
  }

  Widget _etat(Color couleur, String texte) => Chip(
        avatar: Icon(Icons.circle, size: 12, color: couleur),
        label: Text(texte, style: const TextStyle(fontSize: 12)),
      );
}

// ----------------------------------------------------------------- Téléphones

class _PageAppareils extends ConsumerStatefulWidget {
  const _PageAppareils();
  @override
  ConsumerState<_PageAppareils> createState() => _PageAppareilsState();
}

class _PageAppareilsState extends ConsumerState<_PageAppareils> {
  List<Enregistrement> _appareils = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Map<String, String> _noms = const {};

  Future<void> _charger() async {
    final (l, comptes) = await ref.read(servicesProvider).depot.transaction(
        (tx) async => (await tx.chercher('appareil', const {}), await tx.chercher('utilisateur', const {})));
    // Téléphones en attente de validation en premier.
    l.sort((a, b) => (b.donnees['en_attente'] == true ? 1 : 0) - (a.donnees['en_attente'] == true ? 1 : 0));
    if (mounted) {
      setState(() {
        _appareils = l;
        _noms = {
          for (final u in comptes) u.id: '${u.donnees['prenoms'] ?? ''} ${u.donnees['nom']} (${u.donnees['identifiant']})'.trim()
        };
      });
    }
  }

  /// Téléphone enregistré par un agent : choix de ses établissements, puis
  /// validation. Il reçoit alors les données à sa prochaine synchronisation.
  Future<void> _accepter(Enregistrement a) async {
    if (!await _affecter(a, validation: true) || !context.mounted) return;
    final s = ref.read(servicesProvider);
    await executer(context, () => s.appairage.accepter(a.id, ref.read(sessionProvider)!.droits),
        succes: 'Téléphone accepté. Il recevra ses données à sa prochaine synchronisation.');
    await _charger();
  }

  Future<void> _refuser(Enregistrement a) async {
    final ok = await confirmer(context, 'Refuser « ${a.donnees['nom']} » ?',
        'Ce téléphone ne pourra pas se synchroniser. L\'agent devra recommencer l\'enregistrement si c\'est une erreur.',
        bouton: 'Refuser');
    if (!ok || !mounted) return;
    await executer(context, () => ref.read(servicesProvider).appairage.refuser(a.id, ref.read(sessionProvider)!.droits),
        succes: 'Téléphone refusé.');
    await _charger();
  }

  /// Retrait d'un téléphone de la liste ; il sera effacé à son prochain
  /// contact et pourra être appairé ou enregistré de nouveau.
  Future<void> _supprimer(Enregistrement a) async {
    final appaire = a.donnees['cle_publique'] != null && a.donnees['bloque'] != true;
    final ok = await confirmer(
      context,
      'Supprimer « ${a.donnees['nom']} » ?',
      appaire
          ? 'Le téléphone ne pourra plus se synchroniser. À son prochain contact avec le poste, ses données seront '
              'effacées : les visites qu\'il n\'a pas encore envoyées seront perdues. Synchronisez-le d\'abord si '
              'possible. Il pourra ensuite être appairé de nouveau (QR code ou identifiant).'
          : 'Le téléphone est retiré de la liste. Il pourra être appairé de nouveau (QR code ou identifiant).',
      bouton: 'Supprimer',
    );
    if (!ok || !mounted) return;
    await executer(context, () => ref.read(servicesProvider).appairage.supprimer(a.id, ref.read(sessionProvider)!.droits),
        succes: 'Téléphone supprimé.');
    await _charger();
  }

  Future<void> _nouvelAppairage() async {
    final s = ref.read(servicesProvider);
    final session = ref.read(sessionProvider)!;
    final (etabs, comptes) = await s.depot.transaction((tx) async =>
        (await tx.chercher('etablissement', const {}), await tx.chercher('utilisateur', {'actif': true})));
    final adresses = await ServicesPoste.adressesLocales();
    if (!mounted) return;
    final qr = await showDialog<ContenuQrAppairage>(
      context: context,
      builder: (_) => _DialogueAppairage(
        etablissements: etabs,
        comptes: comptes,
        adresses: adresses,
        preparer: (nom, titulaire, choisis, adresse) => s.appairage.preparer(
          acteur: session.droits,
          nomAppareil: nom,
          titulaireId: titulaire,
          etablissementIds: choisis,
          urlServeur: 'https://$adresse:${s.port}',
          empreinteCertificat: s.certificat.empreinte,
          urlInternet: s.config.adresseInternet,
        ),
      ),
    );
    if (qr == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Appairer « ${qr.nomAppareil} »'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            QrImageView(data: qr.versTexte(), size: 300),
            const SizedBox(height: 8),
            const Text('Scannez ce code avec le téléphone. Il est valable 10 minutes et ne sert qu\'une fois.'),
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer'))],
      ),
    );
    await _charger();
  }

  Future<void> _bloquer(Enregistrement a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Bloquer ce téléphone ?'),
        content: Text('« ${a.donnees['nom']} » ne pourra plus se synchroniser. À utiliser en cas de perte ou de vol.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Bloquer')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(servicesProvider).appairage.bloquer(a.id, ref.read(sessionProvider)!.droits);
    await _charger();
  }

  /// Établissements affectés au téléphone ; un établissement ajouté lui est
  /// envoyé en entier à la prochaine synchronisation.
  Future<bool> _affecter(Enregistrement a, {bool validation = false}) async {
    final s = ref.read(servicesProvider);
    final droits = ref.read(sessionProvider)!.droits;
    final (etabs, liens) = await s.depot.transaction((tx) async =>
        (await tx.chercher('etablissement', const {}), await tx.chercher('appareil_etablissement', {'appareil_id': a.id})));
    final choisis = {for (final l in liens) l.donnees['etablissement_id']! as String};
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, maj) => AlertDialog(
          title: Text(validation
              ? 'Accepter « ${a.donnees['nom']} » : établissements'
              : 'Établissements de « ${a.donnees['nom']} »'),
          content: SizedBox(
            width: 420,
            child: ListView(shrinkWrap: true, children: [
              for (final e in etabs)
                CheckboxListTile(
                  value: choisis.contains(e.id),
                  title: Text('${e.donnees['nom']}'),
                  onChanged: (v) => maj(() => v == true ? choisis.add(e.id) : choisis.remove(e.id)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true), child: Text(validation ? 'Accepter' : 'Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return false;
    final fait = await executer(context, () => s.gestion.affecterEtablissements(droits, a.id, choisis),
        succes: validation ? null : 'Affectation enregistrée. Le téléphone recevra les données à sa prochaine synchronisation.');
    if (!validation) await _charger();
    return fait;
  }

  /// Code de sécurité du poste, affiché aussi sur le téléphone lors d'un
  /// enregistrement sans QR code : les deux doivent être identiques.
  Widget _codeSecurite() {
    final s = ref.read(servicesProvider);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.verified_user),
        title: Text('Code de sécurité du poste : ${codeSecuriteCertificat(s.certificat.empreinte)}',
            style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1)),
        subtitle: Text('Sans QR code, l\'agent enregistre son téléphone avec son identifiant à l\'adresse '
            '${s.config.adresseInternet ?? 'https://<adresse du poste>:${s.port}'}. Le téléphone affiche ce même code : '
            's\'il est différent, ne validez pas le téléphone.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _nouvelAppairage,
          icon: const Icon(Icons.qr_code),
          label: const Text('Appairer un téléphone'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _codeSecurite(),
            const SizedBox(height: 8),
            for (final a in _appareils)
              if (a.donnees['en_attente'] == true)
                Card(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.hourglass_top),
                    title: Text('${a.donnees['nom']} — en attente de validation'),
                    subtitle: Text('Enregistré par ${_noms[a.donnees['titulaire_id']] ?? '?'}'
                        ' le ${dateFr(a.createdAt.toLocal())}'
                        '${a.donnees['modele'] == null ? '' : ' · ${a.donnees['modele']}'}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      FilledButton(onPressed: () => _accepter(a), child: const Text('Accepter')),
                      const SizedBox(width: 8),
                      TextButton(onPressed: () => _refuser(a), child: const Text('Refuser')),
                    ]),
                  ),
                )
              else
                Card(
                  child: ListTile(
                    leading: Icon(a.donnees['bloque'] == true ? Icons.block : Icons.phone_android),
                    title: Text('${a.donnees['nom']}'),
                    subtitle: Text(a.donnees['cle_publique'] == null
                        ? 'En attente d\'appairage'
                        : 'Appairé le ${a.donnees['date_appairage']}${a.donnees['modele'] == null ? '' : ' · ${a.donnees['modele']}'}'
                            '${a.donnees['titulaire_id'] == null ? '' : ' · ${_noms[a.donnees['titulaire_id']] ?? ''}'}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (a.donnees['bloque'] == true)
                        const Padding(padding: EdgeInsets.only(right: 8), child: Text('Bloqué'))
                      else ...[
                        TextButton(onPressed: () => _affecter(a), child: const Text('Établissements')),
                        TextButton(onPressed: () => _bloquer(a), child: const Text('Bloquer')),
                      ],
                      IconButton(
                        tooltip: 'Supprimer le téléphone',
                        onPressed: () => _supprimer(a),
                        icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                      ),
                    ]),
                  ),
                ),
          ],
        ),
      );
}

class _DialogueAppairage extends StatefulWidget {
  final List<Enregistrement> etablissements;
  final List<Enregistrement> comptes;
  final List<String> adresses;
  final Future<ContenuQrAppairage> Function(String nom, String? titulaire, List<String> etabs, String adresse) preparer;

  const _DialogueAppairage({
    required this.etablissements,
    required this.comptes,
    required this.adresses,
    required this.preparer,
  });

  @override
  State<_DialogueAppairage> createState() => _DialogueAppairageState();
}

class _DialogueAppairageState extends State<_DialogueAppairage> {
  final _nom = TextEditingController();
  late final _adresse = TextEditingController(text: widget.adresses.isEmpty ? '' : widget.adresses.first);
  String? _titulaire;
  final Set<String> _choisis = {};
  String? _erreur;

  @override
  void dispose() {
    _nom.dispose();
    _adresse.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_nom.text.trim().isEmpty || _choisis.isEmpty || _adresse.text.trim().isEmpty) {
      setState(() => _erreur = 'Nom, adresse du poste et au moins un établissement sont obligatoires.');
      return;
    }
    try {
      final qr = await widget.preparer(_nom.text.trim(), _titulaire, _choisis.toList(), _adresse.text.trim());
      if (mounted) Navigator.pop(context, qr);
    } catch (e) {
      setState(() => _erreur = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nouveau téléphone'),
        content: SizedBox(
          width: 480,
          child: ListView(shrinkWrap: true, children: [
            TextField(controller: _nom, decoration: const InputDecoration(labelText: 'Nom du téléphone (ex. Équipe 1)')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: _titulaire,
              decoration: const InputDecoration(labelText: 'Titulaire'),
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                for (final u in widget.comptes)
                  DropdownMenuItem(value: u.id, child: Text('${u.donnees['nom']} (${u.donnees['identifiant']})')),
              ],
              onChanged: (v) => setState(() => _titulaire = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _adresse,
              decoration: InputDecoration(
                labelText: 'Adresse IP du poste central sur le Wi-Fi',
                helperText: widget.adresses.isEmpty ? null : 'Détectées : ${widget.adresses.join(', ')}',
              ),
            ),
            const SizedBox(height: 12),
            const Text('Établissements affectés'),
            for (final e in widget.etablissements)
              CheckboxListTile(
                value: _choisis.contains(e.id),
                title: Text('${e.donnees['nom']}'),
                onChanged: (v) => setState(() => v == true ? _choisis.add(e.id) : _choisis.remove(e.id)),
              ),
            if (_erreur != null) Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: _valider, child: const Text('Générer le QR code')),
        ],
      );
}

// ----------------------------------------------------------------- Comptes

class _PageComptes extends ConsumerStatefulWidget {
  const _PageComptes();
  @override
  ConsumerState<_PageComptes> createState() => _PageComptesState();
}

class _PageComptesState extends ConsumerState<_PageComptes> {
  List<Enregistrement> _comptes = [];
  Map<String, String> _roles = {};

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final (comptes, roles) = await ref
        .read(servicesProvider)
        .depot
        .transaction((tx) async => (await tx.chercher('utilisateur', const {}), await tx.chercher('role', const {})));
    if (mounted) {
      setState(() {
        _comptes = comptes;
        _roles = {for (final r in roles) r.id: RoleCode.depuisCode(r.donnees['code']! as String).libelle};
      });
    }
  }

  Future<void> _nouveauCompte() async {
    final ident = TextEditingController(), nom = TextEditingController(), prenoms = TextEditingController();
    final fonction = TextEditingController(), mdp = TextEditingController();
    var role = RoleCode.agent;
    String? erreur;
    final cree = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, maj) => AlertDialog(
          title: const Text('Nouveau compte'),
          content: SizedBox(
            width: 420,
            child: ListView(shrinkWrap: true, children: [
              TextField(controller: ident, decoration: const InputDecoration(labelText: 'Identifiant')),
              const SizedBox(height: 8),
              TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom')),
              const SizedBox(height: 8),
              TextField(controller: prenoms, decoration: const InputDecoration(labelText: 'Prénoms')),
              const SizedBox(height: 8),
              TextField(controller: fonction, decoration: const InputDecoration(labelText: 'Fonction')),
              const SizedBox(height: 8),
              DropdownButtonFormField<RoleCode>(
                value: role,
                decoration: const InputDecoration(labelText: 'Rôle'),
                items: [for (final r in RoleCode.values) DropdownMenuItem(value: r, child: Text(r.libelle))],
                onChanged: (v) => maj(() => role = v ?? role),
              ),
              const SizedBox(height: 8),
              TextField(
                  controller: mdp,
                  decoration: const InputDecoration(
                      labelText: 'Mot de passe temporaire', helperText: 'À changer à la première connexion')),
              if (erreur != null) Text(erreur!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                try {
                  final s = ref.read(servicesProvider);
                  final session = ref.read(sessionProvider)!;
                  s.depotUtilisateurs.auteurId = session.utilisateur.id;
                  await s.auth.creerUtilisateur(session.droits,
                      identifiant: ident.text,
                      nom: nom.text,
                      prenoms: prenoms.text.isEmpty ? null : prenoms.text,
                      fonction: fonction.text.isEmpty ? null : fonction.text,
                      role: role,
                      motDePasseTemporaire: mdp.text);
                  if (c.mounted) Navigator.pop(c, true);
                } on ErreurSaisie catch (e) {
                  maj(() => erreur = e.message);
                } on ErreurAutorisation catch (e) {
                  maj(() => erreur = e.message);
                }
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
    for (final t in [ident, nom, prenoms, fonction, mdp]) {
      t.dispose();
    }
    if (cree == true) await _charger();
  }

  Future<void> _action(Enregistrement u, String action) async {
    final s = ref.read(servicesProvider);
    final droits = ref.read(sessionProvider)!.droits;
    switch (action) {
      case 'actif':
        await executer(context, () => s.gestion.definirActif(droits, u.id, actif: u.donnees['actif'] != true),
            succes: 'Compte mis à jour (appliqué aux téléphones à leur prochaine synchronisation).');
      case 'mdp':
        final mdp = await saisir(context, 'Mot de passe temporaire', 'Au moins 8 caractères, lettres et chiffres');
        if (mdp == null || !mounted) return;
        await executer(context, () => s.gestion.reinitialiserMotDePasse(droits, u.id, mdp),
            succes: 'Mot de passe réinitialisé : il devra être changé à la prochaine connexion sur le poste central.');
      case 'role':
        final role = await showDialog<RoleCode>(
          context: context,
          builder: (c) => SimpleDialog(
            title: const Text('Nouveau rôle'),
            children: [
              for (final r in RoleCode.values) SimpleDialogOption(onPressed: () => Navigator.pop(c, r), child: Text(r.libelle)),
            ],
          ),
        );
        if (role == null || !mounted) return;
        await executer(context, () => s.gestion.changerRole(droits, u.id, role), succes: 'Rôle modifié.');
      case 'supprimer':
        final nom = '${u.donnees['prenoms'] ?? ''} ${u.donnees['nom']}'.trim();
        final ok = await confirmer(
          context,
          'Supprimer le compte de $nom ?',
          'Le compte « ${u.donnees['identifiant']} » ne pourra plus se connecter, ni sur le poste ni sur les '
              'téléphones (à leur prochaine synchronisation), et disparaîtra de la liste. Les visites, '
              'inspections et le journal d\'audit gardent son nom. Cette suppression est définitive : pour une '
              'absence temporaire, préférez « Désactiver le compte ».',
          bouton: 'Supprimer',
        );
        if (!ok || !mounted) return;
        final motif = await saisir(context, 'Motif de la suppression', 'Par exemple : départ du service');
        if (motif == null || !mounted) return;
        await executer(context, () => s.gestion.supprimerCompte(droits, u.id, motif: motif),
            succes: 'Compte supprimé. Son identifiant peut être attribué à un nouveau compte.');
    }
    await _charger();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _nouveauCompte,
          icon: const Icon(Icons.person_add),
          label: const Text('Nouveau compte'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final u in _comptes)
              Card(
                child: ListTile(
                  leading: Icon(u.donnees['actif'] == true ? Icons.person : Icons.person_off),
                  title: Text('${u.donnees['prenoms'] ?? ''} ${u.donnees['nom']}'.trim()),
                  subtitle: Text('${u.donnees['identifiant']} · ${_roles[u.donnees['role_id']] ?? '?'}'
                      '${u.donnees['doit_changer_mdp'] == true ? ' · mot de passe temporaire' : ''}'
                      '${u.donnees['actif'] == true ? '' : ' · désactivé'}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) => _action(u, action),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'actif', child: Text(u.donnees['actif'] == true ? 'Désactiver le compte' : 'Réactiver le compte')),
                      const PopupMenuItem(value: 'mdp', child: Text('Réinitialiser le mot de passe')),
                      const PopupMenuItem(value: 'role', child: Text('Changer le rôle')),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'supprimer',
                        child: Text('Supprimer le compte', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}
