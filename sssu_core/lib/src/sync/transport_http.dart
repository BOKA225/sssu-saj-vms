/// Transport HTTP(S) du téléphone vers le poste central, avec épinglage du
/// certificat : seul le certificat dont l'empreinte a été lue dans le QR code
/// d'appairage est accepté.
library;

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'client_sync.dart';
import 'fichiers.dart';
import 'protocole.dart';

String empreinteSha256Hex(List<int> octets) =>
    const DartSha256().hashSync(octets).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

class TransportHttp implements TransportSync {
  final Uri base;
  final http.Client _client;
  final Duration delai;

  TransportHttp._(this.base, this._client, this.delai);

  /// [empreinteCertificat] : SHA-256 hexadécimal du certificat (DER) du poste
  /// central. Obligatoire en HTTPS ; `null` uniquement en HTTP local de test.
  factory TransportHttp(Uri base, {String? empreinteCertificat, Duration delai = const Duration(seconds: 30)}) {
    if (base.scheme == 'https' && empreinteCertificat == null) {
      throw ArgumentError('Empreinte du certificat obligatoire en HTTPS.');
    }
    final io = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..badCertificateCallback = (X509Certificate cert, String hote, int port) =>
          empreinteCertificat != null && empreinteSha256Hex(cert.der) == empreinteCertificat.toLowerCase();
    return TransportHttp._(base, IOClient(io), delai);
  }

  /// Transport utilisant un client HTTP fourni (tests).
  TransportHttp.avecClient(this.base, this._client, {this.delai = const Duration(seconds: 30)});

  Uri _uri(String chemin, [Map<String, String>? params]) =>
      base.replace(path: '${base.path.replaceAll(RegExp(r'/$'), '')}$chemin', queryParameters: params);

  Future<Map<String, Object?>> _traiter(Future<http.Response> requete) async {
    final r = await requete.timeout(delai);
    final Object? corps;
    try {
      corps = jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      throw ErreurProtocole(r.statusCode, 'reponse_invalide', 'Réponse illisible du poste central.');
    }
    final j = Map<String, Object?>.from(corps! as Map);
    if (r.statusCode != 200) {
      throw ErreurProtocole(r.statusCode, (j['erreur'] as String?) ?? 'erreur', (j['message'] as String?) ?? '');
    }
    return j;
  }

  Map<String, String> _entetes([String? jeton]) => {
        'content-type': 'application/json; charset=utf-8',
        if (jeton != null) 'authorization': 'Bearer $jeton',
      };

  Future<bool> etat() async {
    final j = await _traiter(_client.get(_uri('/api/v1/etat')));
    return j['statut'] == 'ok';
  }

  @override
  Future<ReponseAppairage> appairer(DemandeAppairage d) async => ReponseAppairage.depuisJson(
      await _traiter(_client.post(_uri('/api/v1/appairage'), headers: _entetes(), body: jsonEncode(d.versJson()))));

  @override
  Future<ReponseJeton> obtenirJeton(DemandeJeton d) async => ReponseJeton.depuisJson(
      await _traiter(_client.post(_uri('/api/v1/auth/jeton'), headers: _entetes(), body: jsonEncode(d.versJson()))));

  @override
  Future<ReponseEnvoi> envoyer(String jeton, DemandeEnvoi d) async => ReponseEnvoi.depuisJson(await _traiter(
      _client.post(_uri('/api/v1/sync/envoi'), headers: _entetes(jeton), body: jsonEncode(d.versJson()))));

  @override
  Future<ReponseReception> recevoir(String jeton, int curseur) async => ReponseReception.depuisJson(await _traiter(
      _client.get(_uri('/api/v1/sync/reception', {'curseur': '$curseur'}), headers: _entetes(jeton))));

  @override
  Future<EtatFichier> etatFichier(String jeton, String table, String id) async =>
      EtatFichier.depuisJson(await _traiter(_client.get(_uri('/api/v1/sync/fichiers/$table/$id'), headers: _entetes(jeton))));

  @override
  Future<void> envoyerMorceau(String jeton, String table, String id, int numero, List<int> octets) async {
    await _traiter(_client.put(_uri('/api/v1/sync/fichiers/$table/$id/$numero'),
        headers: {..._entetes(jeton), 'content-type': 'application/octet-stream'}, body: octets));
  }

  @override
  Future<void> terminerFichier(String jeton, String table, String id, int nombreMorceaux) async {
    await _traiter(_client.post(_uri('/api/v1/sync/fichiers/$table/$id/fin'),
        headers: _entetes(jeton), body: jsonEncode({'morceaux': nombreMorceaux})));
  }

  void fermer() => _client.close();
}
