/// Découverte du poste central sur le réseau Wi-Fi local, sans Internet :
/// le téléphone diffuse une question sur le port UDP 8444, le poste répond
/// avec son port HTTPS et l'empreinte de son certificat. Le téléphone ne
/// retient que le poste dont il connaît déjà l'empreinte (appairage), ce
/// qui rend inoffensive toute réponse d'un autre ordinateur.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const int portDecouverte = 8444;
const String _question = 'SSSU-SAJ-VMS?v1';

class PosteDecouvert {
  final InternetAddress adresse;
  final int port;
  final String empreinteCertificat;
  final String nom;
  const PosteDecouvert(this.adresse, this.port, this.empreinteCertificat, this.nom);

  Uri get url => Uri(scheme: 'https', host: adresse.address, port: port);
}

/// Répondeur du poste central.
class RepondeurDecouverte {
  final RawDatagramSocket _socket;
  RepondeurDecouverte._(this._socket);

  static Future<RepondeurDecouverte> demarrer({
    required int portHttps,
    required String empreinteCertificat,
    String nom = 'SSSU-SAJ VMS',
    int port = portDecouverte,
    InternetAddress? adresse,
  }) async {
    final s = await RawDatagramSocket.bind(adresse ?? InternetAddress.anyIPv4, port, reuseAddress: true);
    final reponse = utf8.encode(jsonEncode({'sssu': '1', 'port': portHttps, 'cert': empreinteCertificat, 'nom': nom}));
    s.listen((evt) {
      if (evt != RawSocketEvent.read) return;
      final d = s.receive();
      if (d == null) return;
      if (utf8.decode(d.data, allowMalformed: true).trim() == _question) {
        s.send(reponse, d.address, d.port);
      }
    });
    return RepondeurDecouverte._(s);
  }

  void arreter() => _socket.close();
}

/// Cherche les postes centraux du réseau local pendant [duree].
/// [destination] : adresse de diffusion (255.255.255.255 par défaut ; une
/// adresse précise dans les tests).
Future<List<PosteDecouvert>> decouvrirPostes({
  Duration duree = const Duration(seconds: 2),
  InternetAddress? destination,
  int port = portDecouverte,
}) async {
  final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  s.broadcastEnabled = true;
  final trouves = <String, PosteDecouvert>{};
  final fin = Completer<void>();
  final abonnement = s.listen((evt) {
    if (evt != RawSocketEvent.read) return;
    final d = s.receive();
    if (d == null) return;
    try {
      final j = jsonDecode(utf8.decode(d.data)) as Map<String, dynamic>;
      if (j['sssu'] != '1') return;
      trouves['${d.address.address}:${j['port']}'] =
          PosteDecouvert(d.address, (j['port'] as num).toInt(), j['cert'] as String, (j['nom'] as String?) ?? '');
    } catch (_) {
      // Réponse illisible : ignorée.
    }
  });
  s.send(utf8.encode(_question), destination ?? InternetAddress('255.255.255.255'), port);
  Timer(duree, () => fin.complete());
  await fin.future;
  await abonnement.cancel();
  s.close();
  return trouves.values.toList();
}
