import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services.dart';
import 'ui/ecran_accueil.dart';
import 'ui/ecran_appairage.dart';
import 'ui/ecran_connexion.dart';
import 'ui/ecran_enregistrement.dart';
import 'ui/theme.dart';
import 'ui/verrou_inactivite.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Chiffrement AES et hachages accélérés par le système Android quand c'est possible.
  final services = await ServicesMobile.demarrer();
  final appaire = await services.estAppaire();
  final enAttente = appaire && await services.coffre.enAttenteValidation();
  runApp(ProviderScope(
    overrides: [servicesProvider.overrideWithValue(services)],
    child: ApplicationMobile(appaireAuDemarrage: appaire, enAttenteAuDemarrage: enAttente),
  ));
}

class ApplicationMobile extends ConsumerStatefulWidget {
  final bool appaireAuDemarrage;
  final bool enAttenteAuDemarrage;
  const ApplicationMobile({super.key, required this.appaireAuDemarrage, this.enAttenteAuDemarrage = false});

  @override
  ConsumerState<ApplicationMobile> createState() => _ApplicationMobileState();
}

class _ApplicationMobileState extends ConsumerState<ApplicationMobile> {
  late bool _appaire = widget.appaireAuDemarrage;
  late bool _enAttente = widget.enAttenteAuDemarrage;
  Duration _verrou = const Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _lireDelaiVerrouillage();
  }

  /// Délai de verrouillage réglé sur le poste central (paramètre reçu à la synchronisation).
  Future<void> _lireDelaiVerrouillage() async {
    try {
      final m = int.tryParse(await ref.read(servicesProvider).requetes.parametre('verrouillage_mobile_minutes') ?? '');
      if (m != null && m >= 1 && m <= 120 && mounted && Duration(minutes: m) != _verrou) {
        setState(() => _verrou = Duration(minutes: m));
      }
    } catch (_) {
      // Base pas encore initialisée (téléphone non appairé) : délai par défaut.
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: ref.read(servicesProvider).bloque,
        builder: (context, bloque, _) => _application(bloque),
      );

  Widget _application(bool bloque) {
    final session = ref.watch(sessionProvider);
    final Widget ecran;
    if (bloque) {
      ecran = const _EcranTelephoneBloque();
    } else if (!_appaire) {
      ecran = EcranAppairage(
        onAppaire: () => setState(() => _appaire = true),
        onEnregistre: () => setState(() {
          _appaire = true;
          _enAttente = true;
        }),
      );
    } else if (_enAttente) {
      ecran = EcranAttenteValidation(
        onValide: () => setState(() => _enAttente = false),
        onRefuse: () => setState(() {
          _appaire = false;
          _enAttente = false;
        }),
      );
    } else if (session == null) {
      _lireDelaiVerrouillage();
      ecran = const EcranConnexion();
    } else {
      ecran = VerrouInactivite(
        duree: _verrou,
        onVerrouillage: () => ref.read(sessionProvider.notifier).state = null,
        child: const EcranAccueil(),
      );
    }
    return MaterialApp(
      title: 'SSSU-SAJ VMS',
      debugShowCheckedModeBanner: false,
      theme: themeSssu(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: ecran,
    );
  }
}

/// Téléphone bloqué par le poste central (perte ou vol) : ses données ont
/// été effacées. Au prochain lancement, l'application repart de l'appairage.
class _EcranTelephoneBloque extends StatelessWidget {
  const _EcranTelephoneBloque();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.phonelink_lock, size: 72, color: Colors.red),
              const SizedBox(height: 24),
              const Text('Téléphone bloqué', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                'Le poste central a bloqué ce téléphone (perte, vol ou retrait). Toutes les données SSSU-SAJ '
                'qu\'il contenait ont été effacées : dossiers, photographies et clés.\n\n'
                'Pour le réutiliser, demandez à l\'administrateur de l\'appairer de nouveau.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(onPressed: SystemNavigator.pop, child: const Text('Fermer l\'application')),
            ]),
          ),
        ),
      );
}
