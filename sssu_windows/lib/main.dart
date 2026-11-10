import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';
import 'services.dart';
import 'ui/ecran_accueil.dart';
import 'ui/ecran_connexion.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ServicesPoste? services;
  Object? erreur;
  try {
    services = await ServicesPoste.demarrer();
  } catch (e) {
    erreur = e;
  }
  String? cheminConfig;
  if (erreur != null) {
    try {
      cheminConfig = (await ConfigPoste.charger()).cheminFichier;
    } catch (_) {}
  }
  runApp(ProviderScope(
    overrides: [if (services != null) servicesProvider.overrideWithValue(services)],
    child: PosteCentral(erreurDemarrage: erreur, cheminConfig: cheminConfig),
  ));
}

class PosteCentral extends ConsumerWidget {
  final Object? erreurDemarrage;
  final String? cheminConfig;
  const PosteCentral({super.key, this.erreurDemarrage, this.cheminConfig});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget ecran;
    if (erreurDemarrage != null) {
      ecran = _EcranErreur(erreurDemarrage!, cheminConfig);
    } else if (ref.watch(sessionProvider) == null) {
      ecran = const EcranConnexion();
    } else {
      ecran = const EcranAccueil();
    }
    return MaterialApp(
      title: 'SSSU-SAJ VMS – Poste central',
      debugShowCheckedModeBanner: false,
      theme: themeSssu(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: ecran,
    );
  }
}

class _EcranErreur extends StatelessWidget {
  final Object erreur;
  final String? cheminConfig;
  const _EcranErreur(this.erreur, this.cheminConfig);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('SSSU-SAJ VMS – Poste central')),
        body: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Démarrage impossible', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('Vérifiez que PostgreSQL est démarré et que le fichier sssu_config.json contient le bon '
                  'mot de passe, et que le port du serveur de synchronisation (8443) est libre.'),
              if (cheminConfig != null) ...[
                const SizedBox(height: 16),
                SelectableText('Fichier de configuration : $cheminConfig'),
              ],
              const SizedBox(height: 16),
              SelectableText('$erreur'),
            ],
          ),
        ),
      );
}
