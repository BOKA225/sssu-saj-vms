/// Sauvegardes et restauration (droit `sauvegarde.gerer`, Administrateur).
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sssu_core/sssu_core.dart';

import '../sauvegarde/archive_chiffree.dart';
import '../sauvegarde/service_sauvegarde.dart';
import '../services.dart';
import 'commun.dart';

class PageSauvegardes extends ConsumerStatefulWidget {
  const PageSauvegardes({super.key});
  @override
  ConsumerState<PageSauvegardes> createState() => _PageSauvegardesState();
}

class _PageSauvegardesState extends ConsumerState<PageSauvegardes> {
  ReglagesSauvegarde? _r;
  List<File> _liste = const [];
  bool _occupe = false;
  String? _etape;

  ServiceSauvegarde get _s => ref.read(servicesProvider).sauvegardes;
  Droits get _droits => ref.read(sessionProvider)!.droits;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final r = await _s.reglages();
    final l = await _s.sauvegardes();
    if (mounted) {
      setState(() {
        _r = r;
        _liste = l;
      });
    }
  }

  Future<void> _tache(String etape, Future<void> Function() action) async {
    setState(() {
      _occupe = true;
      _etape = etape;
    });
    try {
      await action();
    } on ErreurSauvegarde catch (e) {
      if (mounted) message(context, e.message);
    } on ArchiveInvalide catch (e) {
      if (mounted) message(context, e.message);
    } catch (e) {
      if (mounted) message(context, 'Erreur : $e');
    } finally {
      if (mounted) {
        setState(() {
          _occupe = false;
          _etape = null;
        });
      }
      await _charger();
    }
  }

  Future<String?> _demanderPhrase({required String titre, bool nouvelle = false, String? texte}) async {
    final a = TextEditingController();
    final b = TextEditingController();
    String? erreur;
    final r = await showDialog<String>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: Text(titre),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (texte != null) Text(texte),
              TextField(controller: a, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Phrase de passe')),
              if (nouvelle)
                TextField(controller: b, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmation')),
              if (erreur != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(erreur!, style: const TextStyle(color: Colors.red))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (nouvelle) {
                  final e = ServiceSauvegarde.controlerPhrase(a.text) ?? (a.text != b.text ? 'Les deux saisies diffèrent.' : null);
                  if (e != null) {
                    setD(() => erreur = e);
                    return;
                  }
                }
                Navigator.pop(d, a.text);
              },
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
    a.dispose();
    b.dispose();
    return r;
  }

  Future<void> _definirPhrase() async {
    final phrase = await _demanderPhrase(
      titre: _r!.phraseDefinie ? 'Changer la phrase de passe' : 'Phrase de passe des sauvegardes',
      nouvelle: true,
      texte: 'Elle chiffre les sauvegardes. Notez-la et conservez-la en lieu sûr, hors du poste : sans elle, aucune '
          'sauvegarde ne peut être restaurée sur un autre ordinateur. Au moins 12 caractères (plusieurs mots).'
          '${_r!.phraseDefinie ? '\n\nLes sauvegardes déjà faites gardent leur ancienne phrase.' : ''}',
    );
    if (phrase == null) return;
    await _tache('Préparation de la clé…', () async {
      await _s.definirPhrase(_droits, phrase);
      if (mounted) message(context, 'Phrase de passe enregistrée.');
    });
  }

  Future<void> _sauvegarder() => _tache('Sauvegarde en cours…', () async {
        final r = await _s.sauvegarder(motif: 'manuelle');
        if (mounted) {
          message(context, 'Sauvegarde réussie : ${p.basename(r.fichier.path)} '
              '(${(r.taille / 1048576).toStringAsFixed(1)} Mo, ${r.photos} photo(s)).');
        }
      });

  Future<void> _verifier(File f) async {
    final phrase = await _demanderPhrase(titre: 'Vérifier ${p.basename(f.path)}');
    if (phrase == null) return;
    await _tache('Vérification complète…', () async {
      final m = await _s.verifier(f, phrase);
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Sauvegarde intacte'),
            content: Text('Créée le ${dateHeureFr(m['cree_le'])} sur « ${m['poste']} ».\n'
                'Base : ${(((m['base']! as Map)['taille']! as num) / 1048576).toStringAsFixed(1)} Mo · '
                '${m['photos']} photographie(s).\nMises à jour du schéma : ${(m['migrations'] as List?)?.length ?? 0}.'),
            actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Fermer'))],
          ),
        );
      }
    });
  }

  Future<void> _restaurer(File f) async {
    final confirmation = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Restaurer cette sauvegarde ?'),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Fichier : ${p.basename(f.path)}'),
            const SizedBox(height: 8),
            const Text(
                '• Toutes les données actuelles du poste sont remplacées par celles de la sauvegarde '
                '(une sauvegarde de sécurité de l\'état actuel est faite d\'abord).\n'
                '• Le serveur de synchronisation est arrêté ; l\'application se ferme à la fin : relancez-la.\n'
                '• À leur synchronisation suivante, les téléphones renvoient d\'eux-mêmes leurs données plus récentes.\n'
                '• Les téléphones appairés après la date de la sauvegarde devront être appairés de nouveau.'),
            const SizedBox(height: 12),
            const Text('Tapez RESTAURER pour confirmer :'),
            TextField(controller: confirmation, autofocus: true),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(d, confirmation.text.trim().toUpperCase() == 'RESTAURER'),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
    confirmation.dispose();
    if (ok != true) return;
    if (!mounted) return;
    final phrase = await _demanderPhrase(titre: 'Phrase de passe de cette sauvegarde');
    if (phrase == null) return;
    final services = ref.read(servicesProvider);
    var reussi = false;
    await _tache('Restauration en cours… ne fermez pas l\'application.', () async {
      await _s.restaurer(f, phrase, _droits, arreterPoste: services.arreter);
      reussi = true;
    });
    if (reussi && mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (d) => AlertDialog(
          title: const Text('Restauration terminée'),
          content: const Text('L\'application va se fermer. Relancez-la pour reprendre le travail.'),
          actions: [FilledButton(onPressed: () => exit(0), child: const Text('Fermer l\'application'))],
        ),
      );
    }
  }

  Future<void> _restaurerFichier() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['sssubak']);
    final chemin = r?.files.single.path;
    if (chemin != null) await _restaurer(File(chemin));
  }

  Future<void> _choisirDossier() async {
    final d = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Dossier des sauvegardes');
    if (d == null) return;
    await _tache('Enregistrement…', () => _s.modifierReglages(_droits, dossier: d));
  }

  Future<void> _choisirHeure() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: _r!.heure, minute: _r!.minute));
    if (t == null) return;
    await _tache('Enregistrement…', () => _s.modifierReglages(_droits, heure: t.hour, minute: t.minute));
  }

  Future<void> _choisirConservation() async {
    final c = TextEditingController(text: '${_r!.conservation}');
    final n = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Nombre de sauvegardes conservées'),
        content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, int.tryParse(c.text.trim())), child: const Text('Valider')),
        ],
      ),
    );
    c.dispose();
    if (n == null) return;
    await _tache('Enregistrement…', () => _s.modifierReglages(_droits, conservation: n));
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) return const Center(child: CircularProgressIndicator());
    final ok = r.derniereReussie != null && DateTime.now().difference(r.derniereReussie!.toLocal()) < const Duration(hours: 36);
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('Sauvegardes et restauration', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      if (_occupe) ...[
        LinearProgressIndicator(minHeight: 6),
        Padding(padding: const EdgeInsets.all(8), child: Text(_etape ?? '')),
      ],
      Card(
        child: ListTile(
          leading: Icon(ok ? Icons.verified_user : Icons.warning, color: ok ? Colors.green : Colors.orange, size: 36),
          title: Text(r.derniereReussie == null
              ? 'Aucune sauvegarde réussie'
              : 'Dernière sauvegarde réussie : ${dateHeureFr(r.derniereReussie)}'),
          subtitle: Text([
            if (!r.phraseDefinie) 'La phrase de passe n\'est pas définie : aucune sauvegarde ne peut être faite.',
            if (r.dernierMessage != null) r.dernierMessage!,
          ].join('\n')),
          trailing: FilledButton.icon(
            onPressed: _occupe || !r.phraseDefinie ? null : _sauvegarder,
            icon: const Icon(Icons.backup),
            label: const Text('Sauvegarder maintenant'),
          ),
        ),
      ),
      Card(
        child: Column(children: [
          SwitchListTile(
            value: r.active,
            onChanged: _occupe ? null : (v) => _tache('Enregistrement…', () => _s.modifierReglages(_droits, active: v)),
            title: const Text('Sauvegarde automatique quotidienne'),
            subtitle: Text('Chaque jour à ${r.heure.toString().padLeft(2, '0')} h ${r.minute.toString().padLeft(2, '0')} '
                '(rattrapée au démarrage si le poste était éteint).'),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Heure'),
            trailing: TextButton(onPressed: _occupe ? null : _choisirHeure, child: const Text('Modifier')),
          ),
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('Dossier'),
            subtitle: SelectableText(r.dossier),
            trailing: TextButton(onPressed: _occupe ? null : _choisirDossier, child: const Text('Modifier')),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Conseil : choisissez un disque externe ou un dossier réseau, et emportez régulièrement une copie '
                'hors du bureau. Une sauvegarde gardée sur le même disque que le poste ne protège pas d\'une panne du disque.',
                style: TextStyle(fontSize: 12)),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text('Conservation : ${r.conservation} dernières sauvegardes'),
            trailing: TextButton(onPressed: _occupe ? null : _choisirConservation, child: const Text('Modifier')),
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: Text(r.phraseDefinie ? 'Phrase de passe définie' : 'Phrase de passe à définir'),
            trailing: OutlinedButton(
                onPressed: _occupe ? null : _definirPhrase, child: Text(r.phraseDefinie ? 'Changer' : 'Définir')),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Text('Sauvegardes du dossier (${_liste.length})', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        OutlinedButton.icon(
            onPressed: _occupe ? null : _restaurerFichier,
            icon: const Icon(Icons.restore),
            label: const Text('Restaurer depuis un autre fichier…')),
      ]),
      const SizedBox(height: 8),
      if (_liste.isEmpty) const Text('Aucune sauvegarde dans ce dossier.'),
      for (final f in _liste)
        Card(
          child: ListTile(
            leading: Icon(p.basename(f.path).contains('avant_restauration') ? Icons.shield : Icons.archive),
            title: Text(p.basename(f.path)),
            subtitle: Text('${(f.lengthSync() / 1048576).toStringAsFixed(1)} Mo · ${dateHeureFr(f.lastModifiedSync())}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(onPressed: _occupe ? null : () => _verifier(f), child: const Text('Vérifier')),
              TextButton(
                onPressed: _occupe ? null : () => _restaurer(f),
                child: Text('Restaurer', style: TextStyle(color: Colors.red.shade700)),
              ),
            ]),
          ),
        ),
    ]);
  }
}
