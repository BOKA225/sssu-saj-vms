import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../services.dart';

/// Connexion hors ligne : identifiant et mot de passe, ou code PIN du
/// dernier utilisateur du téléphone.
///
/// La synchronisation est aussi possible sans être connecté (elle utilise
/// l'identité du téléphone, pas celle d'un utilisateur) : un agent dont le
/// mot de passe temporaire a été changé sur le poste central, ou un nouveau
/// compte créé après l'appairage, est ainsi reçu sur le téléphone.
class EcranConnexion extends ConsumerStatefulWidget {
  const EcranConnexion({super.key});

  @override
  ConsumerState<EcranConnexion> createState() => _EcranConnexionState();
}

class _EcranConnexionState extends ConsumerState<EcranConnexion> {
  final _identifiant = TextEditingController();
  final _secret = TextEditingController();
  Utilisateur? _dernier;
  bool _parPin = false;
  bool _enCours = false;
  bool _synchro = false;
  String? _message;
  String? _info;

  @override
  void initState() {
    super.initState();
    _chargerDernier();
  }

  Future<void> _chargerDernier() async {
    final s = ref.read(servicesProvider);
    final id = await s.coffre.dernierUtilisateur();
    if (id == null) return;
    final u = await s.auth.depot.parId(id);
    if (!mounted || u == null) return;
    setState(() {
      _dernier = u;
      _parPin = u.hashPin != null;
      _identifiant.text = u.identifiant;
    });
  }

  @override
  void dispose() {
    _identifiant.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _connecter() async {
    setState(() {
      _enCours = true;
      _message = null;
    });
    final s = ref.read(servicesProvider);
    final r = _parPin && _dernier != null
        ? await s.auth.connecterParPin(_dernier!.id, _secret.text)
        : await s.auth.connecter(_identifiant.text, _secret.text);
    if (!mounted) return;
    _secret.clear();
    if (!r.reussie) {
      setState(() {
        _enCours = false;
        _message = r.message;
      });
      return;
    }
    if (r.session!.doitChangerMotDePasse) {
      setState(() {
        _enCours = false;
        _message = 'Mot de passe temporaire : connectez-vous d\'abord sur le poste central pour choisir '
            'votre mot de passe, puis touchez « Synchroniser » ci-dessous.';
      });
      return;
    }
    await s.coffre.definirDernierUtilisateur(r.session!.utilisateur.id);
    ref.read(sessionProvider.notifier).state = r.session;
  }

  Future<void> _synchroniser() async {
    setState(() {
      _synchro = true;
      _message = null;
      _info = null;
    });
    String? info;
    String? erreur;
    try {
      final r = await ref.read(servicesProvider).synchroniser();
      info = 'Synchronisation terminée : $r';
    } on TelephoneBloque {
      return; // l'écran « Téléphone bloqué » remplace l'application
    } on ErreurProtocole catch (e) {
      erreur = e.code == 'appareil_inconnu'
          ? 'Le poste central ne reconnaît plus ce téléphone. Connectez-vous puis appairez-le de nouveau '
              '(QR code à demander à l\'administrateur).'
          : 'Échec : ${e.message}';
    } catch (e) {
      erreur = messageErreurSynchronisation(e);
    }
    if (!mounted) return;
    setState(() {
      _synchro = false;
      _info = info;
      _message = erreur;
    });
    // Mot de passe, PIN ou nom du dernier utilisateur ont pu changer.
    await _chargerDernier();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SSSU-SAJ VMS')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.health_and_safety, size: 72),
            const SizedBox(height: 8),
            const Text('Visites médicales scolaires', textAlign: TextAlign.center, style: TextStyle(fontSize: 20)),
            const SizedBox(height: 32),
            if (!_parPin)
              TextField(
                controller: _identifiant,
                decoration: const InputDecoration(labelText: 'Identifiant'),
                autocorrect: false,
                textInputAction: TextInputAction.next,
              )
            else
              Text('Code PIN de ${_dernier!.nomAffiche}', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            TextField(
              controller: _secret,
              obscureText: true,
              keyboardType: _parPin ? TextInputType.number : TextInputType.visiblePassword,
              maxLength: _parPin ? 6 : null,
              decoration: InputDecoration(labelText: _parPin ? 'Code PIN' : 'Mot de passe'),
              onSubmitted: (_) => _connecter(),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _enCours ? null : _connecter, child: const Text('Se connecter')),
            if (_dernier?.hashPin != null)
              TextButton(
                onPressed: () => setState(() => _parPin = !_parPin),
                child: Text(_parPin ? 'Utiliser le mot de passe' : 'Utiliser le code PIN'),
              ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 16)),
            ],
            if (_info != null) ...[
              const SizedBox(height: 16),
              Text(_info!, style: const TextStyle(fontSize: 16)),
            ],
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: _synchro || _enCours ? null : _synchroniser,
              icon: _synchro
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
              label: Text(_synchro ? 'Synchronisation…' : 'Synchroniser avec le poste central'),
            ),
            const Text(
              'Nouveau compte ou mot de passe changé sur le poste central : synchronisez avant de vous connecter.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
