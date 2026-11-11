import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../services.dart';

/// Enregistrement du téléphone sans QR code : adresse du poste central
/// (Wi-Fi ou Internet), identifiant et mot de passe de l'agent. Le téléphone
/// attend ensuite sa validation par l'administrateur.
class EcranEnregistrement extends ConsumerStatefulWidget {
  final VoidCallback onEnregistre;
  const EcranEnregistrement({super.key, required this.onEnregistre});

  @override
  ConsumerState<EcranEnregistrement> createState() => _EcranEnregistrementState();
}

class _EcranEnregistrementState extends ConsumerState<EcranEnregistrement> {
  final _adresse = TextEditingController(text: 'https://');
  final _nom = TextEditingController();
  final _identifiant = TextEditingController();
  final _motDePasse = TextEditingController();
  final _nouveau = TextEditingController();
  final _confirmation = TextEditingController();

  /// Identité gardée entre deux essais (réponse perdue, mot de passe à changer).
  IdentiteAppareil? _identite;

  /// Certificat accepté par l'agent pour cette adresse.
  String? _empreinte;
  String? _adresseVerifiee;
  bool _nouveauDemande = false;
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    for (final c in [_adresse, _nom, _identifiant, _motDePasse, _nouveau, _confirmation]) {
      c.dispose();
    }
    super.dispose();
  }

  Uri? _uri() {
    var t = _adresse.text.trim();
    if (!t.contains('://')) t = 'https://$t';
    final u = Uri.tryParse(t);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) return null;
    return u.replace(path: '');
  }

  Future<void> _continuer() async {
    final uri = _uri();
    if (uri == null) return setState(() => _erreur = 'Adresse invalide. Exemple : https://sssu-saj.example.ci:8443');
    if (_nom.text.trim().isEmpty || _identifiant.text.trim().isEmpty || _motDePasse.text.isEmpty) {
      return setState(() => _erreur = 'Nom du téléphone, identifiant et mot de passe sont obligatoires.');
    }
    if (_nouveauDemande) {
      final e = controlerMotDePasse(_nouveau.text);
      if (e != null) return setState(() => _erreur = e);
      if (_nouveau.text != _confirmation.text) return setState(() => _erreur = 'Les deux mots de passe diffèrent.');
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      // 1. Certificat du poste : son code est montré à l'agent avant d'envoyer
      //    le mot de passe (à comparer avec le code affiché sur le poste).
      if (_empreinte == null || _adresseVerifiee != uri.toString()) {
        final empreinte = await lireEmpreinteCertificat(uri);
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (c) => AlertDialog(
            title: const Text('Code de sécurité du poste'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText(codeSecuriteCertificat(empreinte),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(height: 12),
              const Text('Ce code doit être identique à celui affiché sur le poste central (page Téléphones). '
                  'En cas de doute, appelez l\'administrateur avant de continuer.'),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Le code est correct')),
            ],
          ),
        );
        if (ok != true) return;
        _empreinte = empreinte;
        _adresseVerifiee = uri.toString();
      }
      // 2. Enregistrement avec le compte de l'agent.
      _identite ??= await IdentiteAppareil.generer(nouvelId());
      await ref.read(servicesProvider).enregistrer(
            adresse: uri,
            empreinte: _empreinte!,
            identite: _identite!,
            identifiant: _identifiant.text.trim(),
            motDePasse: _motDePasse.text,
            nouveauMotDePasse: _nouveauDemande ? _nouveau.text : null,
            nomAppareil: _nom.text.trim(),
          );
      if (mounted) widget.onEnregistre();
    } on ErreurProtocole catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'mot_de_passe_temporaire') {
          _nouveauDemande = true;
          _erreur = 'Votre mot de passe est temporaire : choisissez votre mot de passe personnel ci-dessous.';
        } else {
          _erreur = e.message;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _erreur = 'Poste central injoignable à cette adresse. Vérifiez l\'adresse et la connexion '
            'Internet ou Wi-Fi du téléphone.');
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Widget _champ(TextEditingController c, String libelle,
          {bool secret = false, String? aide, TextInputType? clavier}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: secret,
          autocorrect: false,
          keyboardType: clavier,
          decoration: InputDecoration(labelText: libelle, helperText: aide, helperMaxLines: 3),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Enregistrer ce téléphone')),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const Text(
              'Sans QR code : saisissez l\'adresse du poste central (donnée par l\'administrateur) et votre compte. '
              'Le téléphone pourra travailler une fois validé par l\'administrateur.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            _champ(_adresse, 'Adresse du poste central',
                aide: 'Par Internet ou sur le Wi-Fi du poste, par exemple https://192.168.1.10:8443',
                clavier: TextInputType.url),
            _champ(_nom, 'Nom du téléphone', aide: 'Par exemple : Équipe 2 – Kouassikro'),
            _champ(_identifiant, 'Identifiant'),
            _champ(_motDePasse, 'Mot de passe', secret: true),
            if (_nouveauDemande) ...[
              _champ(_nouveau, 'Nouveau mot de passe', secret: true, aide: 'Au moins 8 caractères, lettres et chiffres'),
              _champ(_confirmation, 'Confirmer le nouveau mot de passe', secret: true),
            ],
            if (_erreur != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 15)),
              ),
            FilledButton(
              onPressed: _enCours ? null : _continuer,
              child: _enCours
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enregistrer le téléphone'),
            ),
          ]),
        ),
      );
}

/// Téléphone enregistré, en attente de validation sur le poste central.
/// Vérification automatique toutes les minutes tant que l'écran est ouvert.
class EcranAttenteValidation extends ConsumerStatefulWidget {
  final VoidCallback onValide;
  final VoidCallback onRefuse;
  const EcranAttenteValidation({super.key, required this.onValide, required this.onRefuse});

  @override
  ConsumerState<EcranAttenteValidation> createState() => _EcranAttenteValidationState();
}

class _EcranAttenteValidationState extends ConsumerState<EcranAttenteValidation> {
  Timer? _minuterie;
  bool _enCours = false;
  bool _refuse = false;
  String _etat = 'Demande envoyée. L\'administrateur doit accepter ce téléphone sur le poste central et lui '
      'attribuer ses établissements.';

  @override
  void initState() {
    super.initState();
    _minuterie = Timer.periodic(const Duration(minutes: 1), (_) => _verifier(automatique: true));
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  Future<void> _verifier({bool automatique = false}) async {
    if (_enCours || _refuse) return;
    setState(() => _enCours = true);
    final s = ref.read(servicesProvider);
    String? etat;
    try {
      final r = await s.verifierValidation();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Téléphone accepté. ${r.recus} éléments reçus du poste central.')));
      widget.onValide();
      return;
    } on ErreurProtocole catch (e) {
      if (e.code == 'appareil_en_attente') {
        etat = 'Toujours en attente de validation par l\'administrateur.';
      } else if (e.code == 'appareil_inconnu') {
        _refuse = true;
        etat = 'L\'administrateur a refusé ce téléphone. Vous pouvez recommencer l\'enregistrement.';
      } else {
        etat = e.message;
      }
    } on TelephoneBloque {
      return;
    } catch (_) {
      etat = 'Poste central injoignable pour le moment. Nouvel essai automatique dans une minute.';
    }
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _etat = etat ?? _etat;
    });
  }

  Future<void> _recommencer() async {
    await ref.read(servicesProvider).coffre.annulerAppairage();
    widget.onRefuse();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('SSSU-SAJ VMS')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_refuse ? Icons.block : Icons.hourglass_top, size: 72),
              const SizedBox(height: 24),
              Text(_refuse ? 'Téléphone refusé' : 'En attente de validation',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(_etat, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 32),
              if (_refuse)
                FilledButton(onPressed: _recommencer, child: const Text('Recommencer l\'enregistrement'))
              else
                FilledButton.icon(
                  onPressed: _enCours ? null : _verifier,
                  icon: _enCours
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: const Text('Vérifier maintenant'),
                ),
            ]),
          ),
        ),
      );
}
