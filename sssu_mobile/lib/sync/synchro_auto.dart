/// Synchronisation automatique pendant que l'application est ouverte :
/// au retour du réseau (Wi-Fi ou données mobiles) et toutes les 15 minutes.
/// Elle complète le bouton SYNCHRONISER MES DONNÉES, qui reste disponible.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sssu_core/sssu_core.dart';

import '../services.dart';

class SynchroAutomatique {
  final ServicesMobile services;
  final Duration intervalle;

  /// Appelé après chaque passage (réussi ou non), pour rafraîchir l'affichage.
  final void Function(RapportSync? rapport, Object? erreur)? apres;

  final Connectivity _connectivite;
  StreamSubscription<List<ConnectivityResult>>? _abonnement;
  Timer? _minuterie;
  bool _connecte = false;

  SynchroAutomatique(
    this.services, {
    this.intervalle = const Duration(minutes: 15),
    this.apres,
    Connectivity? connectivite,
  }) : _connectivite = connectivite ?? Connectivity();

  Future<void> demarrer() async {
    _connecte = _estConnecte(await _connectivite.checkConnectivity());
    _abonnement = _connectivite.onConnectivityChanged.listen((etat) {
      final avant = _connecte;
      _connecte = _estConnecte(etat);
      // Le réseau vient de revenir (ou a changé de type) : on synchronise.
      if (_connecte && (!avant || etat.contains(ConnectivityResult.wifi))) _lancer();
    });
    _minuterie = Timer.periodic(intervalle, (_) {
      if (_connecte) _lancer();
    });
    if (_connecte) _lancer();
  }

  static bool _estConnecte(List<ConnectivityResult> etat) =>
      etat.any((r) => r == ConnectivityResult.wifi || r == ConnectivityResult.mobile || r == ConnectivityResult.ethernet);

  Future<void> _lancer() async {
    if (services.bloque.value) {
      arreter();
      return;
    }
    if (services.synchronisationEnCours) return;
    try {
      final r = await services.synchroniser();
      apres?.call(r, null);
    } catch (e) {
      // Poste injoignable ou erreur réseau : nouvel essai au prochain changement
      // de réseau ou à la prochaine échéance. Les données restent sur le téléphone.
      debugPrint('Synchronisation automatique : $e');
      apres?.call(null, e);
    }
  }

  void arreter() {
    _abonnement?.cancel();
    _minuterie?.cancel();
    _abonnement = null;
    _minuterie = null;
  }
}
