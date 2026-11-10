/// Appairage des téléphones et jetons de session (poste central).
library;

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../auth/permissions.dart';
import '../commun/commun.dart';
import 'depot_serveur.dart';
import 'enregistrement.dart';
import 'protocole.dart';

const _alphabetCode = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // sans 0/O, 1/I/L

Future<String> _sha256Hex(String texte) async {
  final h = await Sha256().hash(utf8.encode(texte));
  return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class ServiceAppairage {
  final DepotServeur depot;
  final Horloge horloge;
  final Duration validiteCode;
  final Random _aleatoire;

  ServiceAppairage({
    required this.depot,
    this.horloge = const HorlogeSysteme(),
    this.validiteCode = const Duration(minutes: 10),
    Random? aleatoire,
  }) : _aleatoire = aleatoire ?? Random.secure();

  /// Étape 1 (poste central) : l'administrateur déclare l'appareil, son
  /// titulaire et ses établissements. Retourne le contenu du QR code.
  Future<ContenuQrAppairage> preparer({
    required Droits acteur,
    required String nomAppareil,
    String? titulaireId,
    required List<String> etablissementIds,
    required String urlServeur,
    required String? empreinteCertificat,
    String? urlInternet,
  }) async {
    if (!acteur.peut(Permission.comptesGerer)) {
      throw StateError('Seul l\'administrateur peut appairer un téléphone.');
    }
    if (etablissementIds.isEmpty) throw ArgumentError('Affecter au moins un établissement au téléphone.');
    final code = List.generate(8, (_) => _alphabetCode[_aleatoire.nextInt(_alphabetCode.length)]).join();
    final appareilId = nouvelId();
    final maintenant = horloge.maintenant();
    Enregistrement nouveau(String table, Map<String, Object?> donnees, {String? id}) => Enregistrement(
          table: table,
          id: id ?? nouvelId(),
          version: 1,
          versionBase: 1,
          createdAt: maintenant,
          updatedAt: maintenant,
          createdBy: acteur.utilisateurId,
          updatedBy: acteur.utilisateurId,
          donnees: donnees,
        );
    await depot.transaction((tx) async {
      for (final etab in etablissementIds) {
        if (await tx.lire('etablissement', etab) == null) throw ArgumentError('Établissement inconnu : $etab');
      }
      await tx.ecrire(nouveau('appareil', {
        'nom': nomAppareil,
        'titulaire_id': titulaireId,
        'bloque': false,
      }, id: appareilId));
      for (final etab in etablissementIds) {
        await tx.ecrire(nouveau('appareil_etablissement', {'appareil_id': appareilId, 'etablissement_id': etab}));
      }
      await tx.ecrire(nouveau('appairage_code', {
        'appareil_id': appareilId,
        'code_hash': await _sha256Hex(code),
        'expire_le': formaterHorodatage(maintenant.add(validiteCode)),
        'utilise': false,
      }));
    });
    return ContenuQrAppairage(
      urlServeur: urlServeur,
      empreinteCertificat: empreinteCertificat,
      appareilId: appareilId,
      nomAppareil: nomAppareil,
      code: code,
      urlInternet: urlInternet,
    );
  }

  /// Étape 2 (appel du téléphone) : vérifie le code et enregistre la clé publique.
  Future<ReponseAppairage> finaliser(DemandeAppairage demande) async {
    final empreinte = await _sha256Hex(demande.code.trim().toUpperCase());
    final cle = base64.decode(demande.clePublique);
    if (cle.length != 32) throw const ErreurProtocole(400, 'cle_invalide', 'Clé publique Ed25519 invalide.');
    return depot.transaction((tx) async {
      final appareil = await tx.lire('appareil', demande.appareilId);
      final codes = await tx.chercher('appairage_code', {'appareil_id': demande.appareilId, 'utilise': false});
      final maintenant = horloge.maintenant();
      final valide = codes.where((c) =>
          c.donnees['code_hash'] == empreinte && lireHorodatage(c.donnees['expire_le']! as String).isAfter(maintenant));
      if (appareil == null || valide.isEmpty) {
        throw const ErreurProtocole(403, 'code_invalide', 'Code d\'appairage invalide ou expiré.');
      }
      if (appareil.donnees['cle_publique'] != null) {
        throw const ErreurProtocole(409, 'deja_appaire', 'Cet appareil est déjà appairé.');
      }
      final code = valide.first;
      await tx.ecrire(code.copier(
          version: code.version + 1, updatedAt: maintenant, donnees: {...code.donnees, 'utilise': true}));
      await tx.ecrire(appareil.copier(version: appareil.version + 1, updatedAt: maintenant, donnees: {
        ...appareil.donnees,
        'cle_publique': demande.clePublique,
        'modele': demande.modele,
        'date_appairage': formaterHorodatage(maintenant),
      }));
      final liens = await tx.chercher('appareil_etablissement', {'appareil_id': demande.appareilId});
      return ReponseAppairage(
        appareilId: demande.appareilId,
        nomAppareil: appareil.donnees['nom']! as String,
        etablissements: [for (final l in liens) l.donnees['etablissement_id']! as String],
      );
    });
  }

  /// Blocage d'un téléphone perdu ou volé : toutes ses requêtes seront refusées.
  Future<void> bloquer(String appareilId, Droits acteur) async {
    if (!acteur.peut(Permission.comptesGerer)) throw StateError('Action réservée à l\'administrateur.');
    await depot.transaction((tx) async {
      final a = await tx.lire('appareil', appareilId);
      if (a == null) throw ArgumentError('Appareil inconnu.');
      await tx.ecrire(a.copier(
          version: a.version + 1,
          updatedAt: horloge.maintenant(),
          updatedBy: acteur.utilisateurId,
          donnees: {...a.donnees, 'bloque': true}));
    });
  }
}

class _Jeton {
  final String appareilId;
  final DateTime expireLe;
  _Jeton(this.appareilId, this.expireLe);
}

/// Émission et contrôle des jetons de session (validité 1 heure).
/// Les jetons sont gardés en mémoire : un redémarrage du poste central
/// oblige simplement les téléphones à en redemander un.
class ServiceJetons {
  final DepotServeur depot;
  final Horloge horloge;
  final Duration validite;
  final Duration ecartHoraireMax;
  final Random _aleatoire;
  final Map<String, _Jeton> _jetons = {};
  final Map<String, DateTime> _noncesVus = {};

  ServiceJetons({
    required this.depot,
    this.horloge = const HorlogeSysteme(),
    this.validite = const Duration(hours: 1),
    this.ecartHoraireMax = const Duration(minutes: 5),
    Random? aleatoire,
  }) : _aleatoire = aleatoire ?? Random.secure();

  Future<ReponseJeton> emettre(DemandeJeton d) async {
    final maintenant = horloge.maintenant();
    _purger(maintenant);
    if (d.horodatage.difference(maintenant).abs() > ecartHoraireMax) {
      throw const ErreurProtocole(401, 'horloge',
          'L\'heure du téléphone diffère de plus de 5 minutes de celle du poste central.');
    }
    if (_noncesVus.containsKey('${d.appareilId}|${d.nonce}')) {
      throw const ErreurProtocole(401, 'rejeu', 'Demande déjà utilisée.');
    }
    final appareil = await depot.transaction((tx) => tx.lire('appareil', d.appareilId));
    final cle = appareil?.donnees['cle_publique'] as String?;
    if (appareil == null || cle == null) throw const ErreurProtocole(401, 'appareil_inconnu', 'Appareil non appairé.');
    if (appareil.donnees['bloque'] == true) throw const ErreurProtocole(403, 'appareil_bloque', 'Cet appareil est bloqué.');
    final valide = await Ed25519().verify(
      utf8.encode(DemandeJeton.messageASigner(d.appareilId, d.horodatage, d.nonce)),
      signature: Signature(base64.decode(d.signature),
          publicKey: SimplePublicKey(base64.decode(cle), type: KeyPairType.ed25519)),
    );
    if (!valide) throw const ErreurProtocole(401, 'signature', 'Signature invalide.');
    _noncesVus['${d.appareilId}|${d.nonce}'] = maintenant.add(ecartHoraireMax * 2);
    final jeton = base64Url.encode(List<int>.generate(32, (_) => _aleatoire.nextInt(256))).replaceAll('=', '');
    final expire = maintenant.add(validite);
    _jetons[jeton] = _Jeton(d.appareilId, expire);
    return ReponseJeton(jeton: jeton, expireLe: expire, generation: await depot.generation());
  }

  /// Appareil associé au jeton, après contrôle de validité et de blocage.
  Future<String> appareilDuJeton(String? jeton) async {
    final j = jeton == null ? null : _jetons[jeton];
    if (j == null || !j.expireLe.isAfter(horloge.maintenant())) {
      throw const ErreurProtocole(401, 'jeton', 'Jeton absent, invalide ou expiré.');
    }
    final appareil = await depot.transaction((tx) => tx.lire('appareil', j.appareilId));
    if (appareil == null || appareil.donnees['bloque'] == true) {
      _jetons.remove(jeton);
      throw const ErreurProtocole(403, 'appareil_bloque', 'Cet appareil est bloqué.');
    }
    return j.appareilId;
  }

  void _purger(DateTime maintenant) {
    _jetons.removeWhere((_, j) => !j.expireLe.isAfter(maintenant));
    _noncesVus.removeWhere((_, expire) => !expire.isAfter(maintenant));
  }
}
