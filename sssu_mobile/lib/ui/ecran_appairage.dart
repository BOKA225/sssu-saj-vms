import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sssu_core/sssu_core.dart';

import '../services.dart';
import 'ecran_enregistrement.dart';

/// Premier lancement : lecture du QR code affiché sur le poste central, ou
/// enregistrement sans QR code avec le compte de l'agent ([onEnregistre]).
class EcranAppairage extends ConsumerStatefulWidget {
  final VoidCallback onAppaire;

  /// Téléphone enregistré sans QR code (en attente de validation). Absent :
  /// seul le QR code est proposé.
  final VoidCallback? onEnregistre;
  const EcranAppairage({super.key, required this.onAppaire, this.onEnregistre});

  @override
  ConsumerState<EcranAppairage> createState() => _EcranAppairageState();
}

class _EcranAppairageState extends ConsumerState<EcranAppairage> {
  final _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _surDetection(BarcodeCapture capture) async {
    if (_enCours) return;
    final texte = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (texte == null) return;
    final ContenuQrAppairage qr;
    try {
      qr = ContenuQrAppairage.depuisTexte(texte);
    } on FormatException catch (e) {
      setState(() => _erreur = e.message);
      return;
    }
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    await _scanner.stop();
    if (!mounted) return;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Appairer ce téléphone ?'),
        content: Text('Nom : ${qr.nomAppareil}\nPoste central : ${qr.urlServeur}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Appairer')),
        ],
      ),
    );
    if (confirme != true) {
      setState(() => _enCours = false);
      await _scanner.start();
      return;
    }
    try {
      final rapport = await ref.read(servicesProvider).appairer(qr);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Téléphone appairé. ${rapport.recus} éléments reçus du poste central.')));
      widget.onAppaire();
    } on PremiereSynchronisationAFaire {
      // Appairage enregistré, réception des données à terminer : écran
      // d'attente avec nouvel essai (le QR code est déjà utilisé).
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Téléphone appairé. La première synchronisation n\'a pas abouti : nouvel essai en cours.')));
      (widget.onEnregistre ?? widget.onAppaire)();
    } catch (e) {
      setState(() {
        _enCours = false;
        _erreur = e is ErreurProtocole
            ? e.message
            : 'Poste central injoignable. Vérifiez que le téléphone est sur le même Wi-Fi que le poste (et non sur '
                'un réseau « invité »), que l\'application du poste est ouverte, puis réessayez. Loin du poste, '
                'utilisez « Pas de QR code ».';
      });
      await _scanner.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Appairage du téléphone')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Sur le poste central, l\'administrateur crée l\'appareil et affiche un QR code, à scanner sur le '
              'même réseau Wi-Fi. Loin du poste, utilisez le bouton en bas de l\'écran.',
              style: TextStyle(fontSize: 16),
            ),
          ),
          Expanded(
            child: _enCours
                ? const Center(child: CircularProgressIndicator())
                : MobileScanner(controller: _scanner, onDetect: _surDetection),
          ),
          if (widget.onEnregistre != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: _enCours
                    ? null
                    : () async {
                        await _scanner.stop();
                        if (!mounted) return;
                        var enregistre = false;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => EcranEnregistrement(onEnregistre: () {
                              enregistre = true;
                              Navigator.pop(c);
                            }),
                          ),
                        );
                        if (enregistre) {
                          widget.onEnregistre!();
                        } else {
                          await _scanner.start();
                        }
                      },
                icon: const Icon(Icons.person),
                label: const Text('Pas de QR code : m\'enregistrer avec mon identifiant'),
              ),
            ),
          if (_erreur != null)
            Container(
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(16),
              child: Text(_erreur!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
            ),
        ],
      ),
    );
  }
}
