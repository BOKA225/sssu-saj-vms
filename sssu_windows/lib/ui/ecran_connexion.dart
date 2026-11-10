import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../services.dart';

/// Connexion au poste central. Au tout premier lancement (aucun
/// administrateur), l'écran propose de créer le compte administrateur.
/// Un mot de passe temporaire doit être changé avant d'accéder à l'application.
class EcranConnexion extends ConsumerStatefulWidget {
  const EcranConnexion({super.key});

  @override
  ConsumerState<EcranConnexion> createState() => _EcranConnexionState();
}

enum _Mode { chargement, premierAdmin, connexion, changementMotDePasse }

class _EcranConnexionState extends ConsumerState<EcranConnexion> {
  _Mode _mode = _Mode.chargement;
  final _identifiant = TextEditingController();
  final _nom = TextEditingController();
  final _mdp = TextEditingController();
  final _mdp2 = TextEditingController();
  Session? _sessionTemporaire;
  String? _motDePasseTemporaire;
  String? _message;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    ref.read(servicesProvider).auth.depot.existeAdministrateurActif().then((existe) {
      if (mounted) setState(() => _mode = existe ? _Mode.connexion : _Mode.premierAdmin);
    });
  }

  @override
  void dispose() {
    for (final c in [_identifiant, _nom, _mdp, _mdp2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _executer(Future<void> Function() action) async {
    setState(() {
      _enCours = true;
      _message = null;
    });
    try {
      await action();
    } on ErreurSaisie catch (e) {
      _message = e.message;
    } on ErreurAutorisation catch (e) {
      _message = e.message;
    }
    if (mounted) setState(() => _enCours = false);
  }

  Future<void> _creerAdmin() => _executer(() async {
        if (_mdp.text != _mdp2.text) throw const ErreurSaisie('Les deux mots de passe sont différents.');
        await ref.read(servicesProvider).auth.creerPremierAdministrateur(
              identifiant: _identifiant.text,
              nom: _nom.text,
              motDePasse: _mdp.text,
            );
        _mdp.clear();
        _mdp2.clear();
        _mode = _Mode.connexion;
        _message = 'Compte administrateur créé. Connectez-vous.';
      });

  Future<void> _connecter() => _executer(() async {
        final saisi = _mdp.text;
        final r = await ref.read(servicesProvider).auth.connecter(_identifiant.text, saisi);
        _mdp.clear();
        if (!r.reussie) throw ErreurSaisie(r.message);
        if (r.session!.doitChangerMotDePasse) {
          _sessionTemporaire = r.session;
          _motDePasseTemporaire = saisi;
          _mode = _Mode.changementMotDePasse;
          _message = 'Mot de passe temporaire : choisissez votre mot de passe personnel.';
          return;
        }
        ref.read(sessionProvider.notifier).state = r.session;
      });

  Future<void> _changer() => _executer(() async {
        if (_mdp.text != _mdp2.text) throw const ErreurSaisie('Les deux mots de passe sont différents.');
        final s = await ref.read(servicesProvider).auth.changerMotDePasse(
              _sessionTemporaire!,
              ancien: _motDePasseTemporaire!,
              nouveau: _mdp.text,
            );
        _motDePasseTemporaire = null;
        ref.read(sessionProvider.notifier).state = s;
      });

  @override
  Widget build(BuildContext context) {
    final List<Widget> champs;
    final String titre;
    final VoidCallback? action;
    switch (_mode) {
      case _Mode.chargement:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _Mode.premierAdmin:
        titre = 'Premier lancement : création du compte administrateur';
        champs = [
          _champ(_identifiant, 'Identifiant'),
          _champ(_nom, 'Nom'),
          _champ(_mdp, 'Mot de passe (8 caractères minimum, lettres et chiffres)', secret: true),
          _champ(_mdp2, 'Confirmer le mot de passe', secret: true),
        ];
        action = _creerAdmin;
      case _Mode.connexion:
        titre = 'Connexion';
        champs = [_champ(_identifiant, 'Identifiant'), _champ(_mdp, 'Mot de passe', secret: true, valider: _connecter)];
        action = _connecter;
      case _Mode.changementMotDePasse:
        titre = 'Nouveau mot de passe';
        champs = [
          _champ(_mdp, 'Nouveau mot de passe', secret: true),
          _champ(_mdp2, 'Confirmer le nouveau mot de passe', secret: true),
        ];
        action = _changer;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('SSSU-SAJ VMS – Poste central')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(titre, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 24),
              ...champs,
              FilledButton(onPressed: _enCours ? null : action, child: const Text('Valider')),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(_message!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _champ(TextEditingController c, String libelle, {bool secret = false, VoidCallback? valider}) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextField(
          controller: c,
          obscureText: secret,
          decoration: InputDecoration(labelText: libelle),
          onSubmitted: valider == null ? null : (_) => valider(),
        ),
      );
}
