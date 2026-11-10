import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sssu_core/sssu_core.dart';

import 'data/base_locale.dart' hide Utilisateur, Eleve;
import 'data/depot_local_drift.dart';
import 'data/depot_utilisateurs_drift.dart';
import 'data/ouverture.dart';
import 'data/requetes.dart';
import 'fichiers/stockage_chiffre.dart';
import 'securite/coffre.dart';

/// Services de l'application mobile, créés au démarrage.
class ServicesMobile {
  final BaseLocale base;
  final Coffre coffre;
  final DepotLocalDrift depot;
  final ServiceAuthentification auth;
  final Horloge horloge;
  final Requetes requetes;
  final StockageChiffre fichiers;

  ServicesMobile._(this.base, this.coffre, this.depot, this.auth, this.horloge, this.requetes, this.fichiers);

  static Future<ServicesMobile> demarrer() async {
    final coffre = Coffre();
    final base = await ouvrirBaseLocale(coffre);
    return ServicesMobile.avec(base, coffre);
  }

  static Future<ServicesMobile> avec(BaseLocale base, Coffre coffre,
      {Horloge horloge = const HorlogeSysteme(), Directory? dossierFichiers}) async {
    final depot = DepotLocalDrift(base, horloge: horloge, appareilId: await coffre.appareilId());
    final auth = ServiceAuthentification(depot: DepotUtilisateursDrift(base), horloge: horloge);
    final dossier = dossierFichiers ?? Directory(p.join((await getApplicationSupportDirectory()).path, 'fichiers'));
    final fichiers = StockageChiffre(dossier, ChiffreurFichiers(await coffre.cleFichiers()));
    depot.fichiers = fichiers;
    return ServicesMobile._(base, coffre, depot, auth, horloge, Requetes(base), fichiers);
  }

  Future<bool> estAppaire() async => await coffre.appareilId() != null;

  /// Appairage à partir du QR code lu sur le poste central, puis première
  /// synchronisation (comptes, référentiels, élèves de l'établissement).
  Future<RapportSync> appairer(ContenuQrAppairage qr, {String? modele}) async {
    final transport = TransportHttp(Uri.parse(qr.urlServeur), empreinteCertificat: qr.empreinteCertificat);
    final identite = await IdentiteAppareil.generer(qr.appareilId);
    await transport.appairer(DemandeAppairage(
      appareilId: qr.appareilId,
      code: qr.code,
      clePublique: await identite.clePubliqueBase64(),
      modele: modele,
    ));
    await coffre.enregistrerAppairage(
      appareilId: qr.appareilId,
      graine: await identite.graine(),
      urlServeur: qr.urlServeur,
      empreinteCertificat: qr.empreinteCertificat,
      urlInternet: qr.urlInternet,
    );
    depot.appareilId = qr.appareilId;
    // Nouvel appairage d'un téléphone déjà utilisé (par exemple après une
    // restauration du poste) : ses données sont gardées et tout est rechargé.
    await depot.definirCurseur(0);
    return synchroniser();
  }

  /// Adresses à essayer, dans l'ordre : la dernière adresse locale qui a
  /// répondu ; le poste trouvé sur le Wi-Fi (s'il a changé d'adresse), à
  /// condition que son certificat soit celui de l'appairage ; l'adresse
  /// Internet du poste, si elle a été fournie. La recherche sur le Wi-Fi
  /// (2 secondes) n'a lieu que si la dernière adresse ne répond pas.
  Stream<Uri> _adressesCandidates() async* {
    final derniere = await coffre.urlServeur();
    final internet = await coffre.urlInternet();
    final empreinte = (await coffre.empreinteCertificat())?.toLowerCase();
    final derniereUri = derniere == null ? null : Uri.tryParse(derniere);
    final internetUri = internet == null ? null : Uri.tryParse(internet);
    if (derniereUri != null && estAdresseLocale(derniereUri.host)) yield derniereUri;
    if (empreinte != null) {
      var trouves = const <PosteDecouvert>[];
      try {
        trouves = await decouvrirPostes();
      } catch (_) {
        // Pas de Wi-Fi ou diffusion bloquée : on passe aux adresses suivantes.
      }
      for (final p in trouves) {
        if (p.empreinteCertificat.toLowerCase() == empreinte && p.url != derniereUri) yield p.url;
      }
    }
    if (internetUri != null) yield internetUri;
    if (derniereUri != null && !estAdresseLocale(derniereUri.host) && derniereUri != internetUri) yield derniereUri;
  }

  /// Première adresse à laquelle le poste central répond ; une adresse
  /// locale qui répond est mémorisée pour la fois suivante.
  Future<Uri?> trouverPosteCentral() async {
    final empreinte = await coffre.empreinteCertificat();
    await for (final u in _adressesCandidates()) {
      final t = TransportHttp(u, empreinteCertificat: empreinte, delai: const Duration(seconds: 4));
      try {
        if (await t.etat()) {
          if (estAdresseLocale(u.host)) await coffre.definirUrlServeur(u.toString());
          _derniereAdresse = u;
          return u;
        }
      } catch (_) {
        // Adresse injoignable : suivante.
      } finally {
        t.fermer();
      }
    }
    _derniereAdresse = null;
    return null;
  }

  Uri? _derniereAdresse;

  /// Adresse utilisée lors de la dernière synchronisation ou vérification.
  Uri? get derniereAdresse => _derniereAdresse;

  static bool estAdresseLocale(String hote) =>
      hote.startsWith('192.168.') || hote.startsWith('10.') || RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(hote);

  /// Vrai après un effacement à distance (téléphone bloqué par le poste central).
  final ValueNotifier<bool> bloque = ValueNotifier(false);

  /// Téléphone déclaré perdu ou volé : la base, les photos et les clés sont
  /// effacées. Au prochain lancement, l'application repart de l'appairage.
  Future<void> effacerTelephone() async {
    bloque.value = true;
    try {
      await base.close();
    } catch (_) {}
    await supprimerBaseLocale();
    if (await fichiers.racine.exists()) await fichiers.racine.delete(recursive: true);
    await coffre.effacerTout();
  }

  Future<RapportSync>? _synchroEnCours;

  /// Synchronise avec le poste central. Un seul passage à la fois : un appel
  /// pendant une synchronisation en cours en attend le résultat.
  Future<RapportSync> synchroniser() => _synchroEnCours ??= _synchroniser().whenComplete(() => _synchroEnCours = null);

  bool get synchronisationEnCours => _synchroEnCours != null;

  Future<RapportSync> _synchroniser() async {
    final appareilId = await coffre.appareilId();
    final graine = await coffre.graine();
    if (appareilId == null || graine == null) throw StateError('Ce téléphone n\'est pas appairé.');
    final uri = await trouverPosteCentral();
    if (uri == null) throw const PosteInjoignable();
    final transport = TransportHttp(uri, empreinteCertificat: await coffre.empreinteCertificat());
    try {
      final identite = await IdentiteAppareil.depuisGraine(appareilId, graine);
      return await _effacerSiBloque(() => ClientSynchronisation(
        depot: depot,
        transport: transport,
        identite: identite,
        horloge: horloge,
        canal: estAdresseLocale(uri.host) ? 'wifi' : 'internet',
      ).synchroniser());
    } finally {
      transport.fermer();
    }
  }

  Future<RapportSync> _effacerSiBloque(Future<RapportSync> Function() action) async {
    try {
      return await action();
    } on ErreurProtocole catch (e) {
      if (e.code == 'appareil_bloque') {
        await effacerTelephone();
        throw const TelephoneBloque();
      }
      rethrow;
    }
  }

  /// Vérifie que le poste central répond (indicateur de connexion).
  Future<bool> posteCentralJoignable() async => await trouverPosteCentral() != null;
}

/// Le poste central a bloqué ce téléphone : ses données ont été effacées.
class TelephoneBloque implements Exception {
  const TelephoneBloque();
  @override
  String toString() => 'Ce téléphone a été bloqué par le poste central : ses données ont été effacées.';
}

/// Aucune adresse du poste central n'a répondu.
class PosteInjoignable implements Exception {
  const PosteInjoignable();
  @override
  String toString() => 'Poste central injoignable (ni sur le Wi-Fi, ni par Internet).';
}

final servicesProvider = Provider<ServicesMobile>((ref) => throw UnimplementedError('Fourni au démarrage'));

/// Session de l'utilisateur connecté (`null` = écran de connexion).
final sessionProvider = StateProvider<Session?>((ref) => null);
