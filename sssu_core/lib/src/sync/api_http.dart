/// API REST du poste central (shelf). Le serveur HTTPS lui-même est démarré
/// par l'application Windows ; les tests l'exécutent en HTTP sur localhost.
library;

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../commun/commun.dart';
import 'appairage.dart';
import 'fichiers.dart';
import 'protocole.dart';
import 'service_sync.dart';

const int tailleMaxRequete = 10 * 1024 * 1024;

Response _json(int code, Object? corps) =>
    Response(code, body: jsonEncode(corps), headers: {'content-type': 'application/json; charset=utf-8'});

Future<Map<String, Object?>> _lireJson(Request r) async {
  final taille = r.contentLength;
  if (taille != null && taille > tailleMaxRequete) {
    throw const ErreurProtocole(413, 'trop_volumineux', 'Requête trop volumineuse.');
  }
  final texte = await r.readAsString(utf8);
  if (texte.length > tailleMaxRequete) throw const ErreurProtocole(413, 'trop_volumineux', 'Requête trop volumineuse.');
  try {
    final v = jsonDecode(texte);
    if (v is! Map) throw const FormatException();
    return Map<String, Object?>.from(v);
  } on FormatException {
    throw const ErreurProtocole(400, 'json_invalide', 'Corps JSON invalide.');
  }
}

String? _jetonDe(Request r) {
  final h = r.headers['authorization'];
  if (h == null || !h.startsWith('Bearer ')) return null;
  return h.substring(7).trim();
}

ServiceFichiers _fichiers(ServiceFichiers? f) =>
    f ?? (throw const ErreurProtocole(503, 'indisponible', 'Réception des fichiers non configurée.'));

/// Construit le gestionnaire HTTP de l'API.
Handler construireApi({
  required ServiceSynchronisation sync,
  required ServiceAppairage appairage,
  required ServiceJetons jetons,
  ServiceFichiers? fichiers,
  Horloge horloge = const HorlogeSysteme(),
  void Function(Object erreur, StackTrace pile)? journalErreurs,
}) {
  final routes = Router()
    ..get('/api/v1/etat', (Request r) {
      return _json(200, {
        'statut': 'ok',
        'service': 'SSSU-SAJ VMS',
        'protocole': versionProtocole,
        'heure': formaterHorodatage(horloge.maintenant()),
      });
    })
    ..post('/api/v1/appairage', (Request r) async {
      final rep = await appairage.finaliser(DemandeAppairage.depuisJson(await _lireJson(r)));
      return _json(200, rep.versJson());
    })
    ..post('/api/v1/auth/jeton', (Request r) async {
      final rep = await jetons.emettre(DemandeJeton.depuisJson(await _lireJson(r)));
      return _json(200, rep.versJson());
    })
    ..post('/api/v1/sync/envoi', (Request r) async {
      final appareilId = await jetons.appareilDuJeton(_jetonDe(r));
      final rep = await sync.recevoirEnvoi(appareilId, DemandeEnvoi.depuisJson(await _lireJson(r)));
      return _json(200, rep.versJson());
    })
    ..get('/api/v1/sync/reception', (Request r) async {
      final appareilId = await jetons.appareilDuJeton(_jetonDe(r));
      final curseur = int.tryParse(r.url.queryParameters['curseur'] ?? '0');
      if (curseur == null || curseur < 0) throw const ErreurProtocole(400, 'curseur', 'Curseur invalide.');
      final rep = await sync.preparerReception(appareilId, curseur);
      return _json(200, rep.versJson());
    })
    ..get('/api/v1/sync/fichiers/<table>/<id>', (Request r, String table, String id) async {
      final appareilId = await jetons.appareilDuJeton(_jetonDe(r));
      return _json(200, (await _fichiers(fichiers).etat(appareilId, table, id)).versJson());
    })
    ..put('/api/v1/sync/fichiers/<table>/<id>/<n>', (Request r, String table, String id, String n) async {
      final appareilId = await jetons.appareilDuJeton(_jetonDe(r));
      final numero = int.tryParse(n);
      if (numero == null) throw const ErreurProtocole(400, 'morceau', 'Numéro de morceau invalide.');
      final octets = <int>[];
      await for (final bloc in r.read()) {
        octets.addAll(bloc);
        if (octets.length > tailleMorceau) throw const ErreurProtocole(413, 'trop_volumineux', 'Morceau trop volumineux.');
      }
      await _fichiers(fichiers).recevoirMorceau(appareilId, table, id, numero, octets);
      return _json(200, {'recu': numero});
    })
    ..post('/api/v1/sync/fichiers/<table>/<id>/fin', (Request r, String table, String id) async {
      final appareilId = await jetons.appareilDuJeton(_jetonDe(r));
      final n = (await _lireJson(r))['morceaux'];
      if (n is! int || n < 0) throw const ErreurProtocole(400, 'morceaux', 'Nombre de morceaux invalide.');
      await _fichiers(fichiers).terminer(appareilId, table, id, n);
      return _json(200, {'confirme': true});
    });

  Middleware gestionErreurs() => (Handler interne) => (Request r) async {
        try {
          return await interne(r);
        } on ErreurProtocole catch (e) {
          return _json(e.codeHttp, e.versJson());
        } on FormatException catch (e) {
          return _json(400, {'erreur': 'format', 'message': e.message});
        } on TypeError catch (e, pile) {
          // Champ manquant ou de mauvais type dans le JSON reçu.
          journalErreurs?.call(e, pile);
          return _json(400, {'erreur': 'format', 'message': 'Message mal formé.'});
        } catch (e, pile) {
          journalErreurs?.call(e, pile);
          return _json(500, {'erreur': 'interne', 'message': 'Erreur interne du poste central.'});
        }
      };

  return const Pipeline().addMiddleware(gestionErreurs()).addHandler(routes.call);
}
