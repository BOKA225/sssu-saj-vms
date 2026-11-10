import 'package:sssu_core/sssu_core.dart';

/// Transport direct vers les services du poste central (sans réseau).
class TransportDirect implements TransportSync {
  final ServiceSynchronisation sync;
  final ServiceAppairage appairage;
  final ServiceJetons jetons;
  final ServiceFichiers? fichiers;
  TransportDirect(this.sync, this.appairage, this.jetons, {this.fichiers});

  ServiceFichiers get _f => fichiers ?? (throw const ErreurProtocole(404, 'fichiers', 'Réception des fichiers absente.'));

  @override
  Future<ReponseAppairage> appairer(DemandeAppairage d) => appairage.finaliser(d);
  @override
  Future<ReponseJeton> obtenirJeton(DemandeJeton d) => jetons.emettre(d);
  @override
  Future<ReponseEnvoi> envoyer(String jeton, DemandeEnvoi d) async =>
      sync.recevoirEnvoi(await jetons.appareilDuJeton(jeton), d);
  @override
  Future<ReponseReception> recevoir(String jeton, int curseur) async =>
      sync.preparerReception(await jetons.appareilDuJeton(jeton), curseur);
  @override
  Future<EtatFichier> etatFichier(String jeton, String table, String id) async =>
      _f.etat(await jetons.appareilDuJeton(jeton), table, id);
  @override
  Future<void> envoyerMorceau(String jeton, String table, String id, int numero, List<int> octets) async =>
      _f.recevoirMorceau(await jetons.appareilDuJeton(jeton), table, id, numero, octets);
  @override
  Future<void> terminerFichier(String jeton, String table, String id, int nombreMorceaux) async =>
      _f.terminer(await jetons.appareilDuJeton(jeton), table, id, nombreMorceaux);
}
