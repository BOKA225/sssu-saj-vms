/// Messages échangés entre les téléphones et le poste central (API REST, JSON).
library;

import 'dart:convert';

import '../commun/commun.dart';
import 'enregistrement.dart';

const String versionProtocole = '1';

Map<String, Object?> _map(Object? o) => Map<String, Object?>.from(o! as Map);

/// Contenu du QR code affiché sur le poste central pour appairer un téléphone.
class ContenuQrAppairage {
  final String urlServeur;

  /// Empreinte SHA-256 (hexadécimal) du certificat TLS du poste central,
  /// épinglée par le téléphone.
  final String? empreinteCertificat;
  final String appareilId;
  final String nomAppareil;
  final String code;

  /// Adresse du poste joignable par Internet (facultative), utilisée quand le
  /// téléphone n'est pas sur le même Wi-Fi.
  final String? urlInternet;

  const ContenuQrAppairage({
    required this.urlServeur,
    required this.empreinteCertificat,
    required this.appareilId,
    required this.nomAppareil,
    required this.code,
    this.urlInternet,
  });

  String versTexte() => jsonEncode({
        'sssu': versionProtocole,
        'url': urlServeur,
        'cert': empreinteCertificat,
        'appareil': appareilId,
        'nom': nomAppareil,
        'code': code,
        if (urlInternet != null) 'internet': urlInternet,
      });

  factory ContenuQrAppairage.depuisTexte(String texte) {
    final j = _map(jsonDecode(texte));
    if (j['sssu'] != versionProtocole) {
      throw const FormatException('Ce QR code n\'est pas un code d\'appairage SSSU-SAJ VMS.');
    }
    return ContenuQrAppairage(
      urlServeur: j['url']! as String,
      empreinteCertificat: j['cert'] as String?,
      appareilId: j['appareil']! as String,
      nomAppareil: j['nom']! as String,
      code: j['code']! as String,
      urlInternet: j['internet'] as String?,
    );
  }
}

class DemandeAppairage {
  final String appareilId;
  final String code;

  /// Clé publique Ed25519 du téléphone, en base64.
  final String clePublique;
  final String? modele;

  const DemandeAppairage({required this.appareilId, required this.code, required this.clePublique, this.modele});

  Map<String, Object?> versJson() =>
      {'appareil_id': appareilId, 'code': code, 'cle_publique': clePublique, 'modele': modele};

  factory DemandeAppairage.depuisJson(Map<String, Object?> j) => DemandeAppairage(
        appareilId: j['appareil_id']! as String,
        code: j['code']! as String,
        clePublique: j['cle_publique']! as String,
        modele: j['modele'] as String?,
      );
}

class ReponseAppairage {
  final String appareilId;
  final String nomAppareil;
  final List<String> etablissements;

  const ReponseAppairage({required this.appareilId, required this.nomAppareil, required this.etablissements});

  Map<String, Object?> versJson() =>
      {'appareil_id': appareilId, 'nom': nomAppareil, 'etablissements': etablissements};

  factory ReponseAppairage.depuisJson(Map<String, Object?> j) => ReponseAppairage(
        appareilId: j['appareil_id']! as String,
        nomAppareil: j['nom']! as String,
        etablissements: (j['etablissements']! as List).cast<String>(),
      );
}

/// Demande de jeton : le téléphone prouve son identité en signant
/// [messageASigner] avec sa clé privée.
class DemandeJeton {
  final String appareilId;
  final DateTime horodatage;
  final String nonce;

  /// Signature Ed25519 en base64.
  final String signature;

  const DemandeJeton({required this.appareilId, required this.horodatage, required this.nonce, required this.signature});

  static String messageASigner(String appareilId, DateTime horodatage, String nonce) =>
      'SSSU-SAJ-VMS|jeton|$appareilId|${formaterHorodatage(horodatage)}|$nonce';

  Map<String, Object?> versJson() => {
        'appareil_id': appareilId,
        'horodatage': formaterHorodatage(horodatage),
        'nonce': nonce,
        'signature': signature,
      };

  factory DemandeJeton.depuisJson(Map<String, Object?> j) => DemandeJeton(
        appareilId: j['appareil_id']! as String,
        horodatage: lireHorodatage(j['horodatage']! as String),
        nonce: j['nonce']! as String,
        signature: j['signature']! as String,
      );
}

class ReponseJeton {
  final String jeton;
  final DateTime expireLe;

  /// Génération des données du poste central : elle change à chaque
  /// restauration d'une sauvegarde. Un téléphone qui la voit changer renvoie
  /// ses données et recharge tout (reprise après restauration).
  final String? generation;

  const ReponseJeton({required this.jeton, required this.expireLe, this.generation});

  Map<String, Object?> versJson() =>
      {'jeton': jeton, 'expire_le': formaterHorodatage(expireLe), if (generation != null) 'generation': generation};

  factory ReponseJeton.depuisJson(Map<String, Object?> j) => ReponseJeton(
      jeton: j['jeton']! as String,
      expireLe: lireHorodatage(j['expire_le']! as String),
      generation: j['generation'] as String?);
}

class DemandeEnvoi {
  final List<Enregistrement> enregistrements;

  /// `wifi` ou `internet` (pour le journal de synchronisation).
  final String canal;

  /// Renvoi des données du téléphone après une restauration du poste central.
  final bool reprise;

  const DemandeEnvoi({required this.enregistrements, this.canal = 'wifi', this.reprise = false});

  Map<String, Object?> versJson() => {
        'canal': canal,
        if (reprise) 'reprise': true,
        'enregistrements': [for (final e in enregistrements) e.versJson()],
      };

  factory DemandeEnvoi.depuisJson(Map<String, Object?> j) => DemandeEnvoi(
        canal: (j['canal'] as String?) ?? 'wifi',
        reprise: j['reprise'] == true,
        enregistrements: [for (final e in j['enregistrements']! as List) Enregistrement.depuisJson(_map(e))],
      );
}

enum StatutAccuse {
  /// Enregistré par le poste central.
  accepte('accepte'),

  /// Déjà reçu auparavant (accusé perdu puis renvoi) : rien n'a changé.
  dejaRecu('deja_recu'),

  /// Modification concurrente ou doublon : conservé dans la table des
  /// conflits, en attente de décision sur le poste central.
  conflit('conflit'),

  /// Refusé (droits insuffisants, visite validée, données invalides).
  refuse('refuse');

  final String code;
  const StatutAccuse(this.code);
  static StatutAccuse depuisCode(String c) => values.firstWhere((v) => v.code == c);
}

class Accuse {
  final String table;
  final String id;
  final StatutAccuse statut;

  /// Version enregistrée sur le poste central (accepté ou déjà reçu).
  final int? version;
  final String? motif;

  const Accuse({required this.table, required this.id, required this.statut, this.version, this.motif});

  Map<String, Object?> versJson() =>
      {'table': table, 'id': id, 'statut': statut.code, 'version': version, 'motif': motif};

  factory Accuse.depuisJson(Map<String, Object?> j) => Accuse(
        table: j['table']! as String,
        id: j['id']! as String,
        statut: StatutAccuse.depuisCode(j['statut']! as String),
        version: (j['version'] as num?)?.toInt(),
        motif: j['motif'] as String?,
      );
}

class ReponseEnvoi {
  final List<Accuse> accuses;
  const ReponseEnvoi(this.accuses);

  Map<String, Object?> versJson() => {'accuses': [for (final a in accuses) a.versJson()]};

  factory ReponseEnvoi.depuisJson(Map<String, Object?> j) =>
      ReponseEnvoi([for (final a in j['accuses']! as List) Accuse.depuisJson(_map(a))]);
}

/// Changement transmis au téléphone.
class ChangementRecu {
  final Enregistrement enregistrement;

  /// Vrai lorsque ce changement tranche un conflit signalé par ce téléphone :
  /// la version du poste central remplace alors la version locale en conflit.
  final bool resolutionConflit;

  const ChangementRecu(this.enregistrement, {this.resolutionConflit = false});

  Map<String, Object?> versJson() =>
      {...enregistrement.versJson(), if (resolutionConflit) 'resolution_conflit': true};

  factory ChangementRecu.depuisJson(Map<String, Object?> j) =>
      ChangementRecu(Enregistrement.depuisJson(j), resolutionConflit: j['resolution_conflit'] == true);
}

class ReponseReception {
  final List<ChangementRecu> changements;

  /// Curseur à mémoriser et à renvoyer à la prochaine demande.
  final int curseur;

  /// Vrai s'il reste des changements à demander.
  final bool suite;

  const ReponseReception({required this.changements, required this.curseur, required this.suite});

  Map<String, Object?> versJson() =>
      {'curseur': curseur, 'suite': suite, 'changements': [for (final c in changements) c.versJson()]};

  factory ReponseReception.depuisJson(Map<String, Object?> j) => ReponseReception(
        curseur: (j['curseur']! as num).toInt(),
        suite: j['suite']! as bool,
        changements: [for (final c in j['changements']! as List) ChangementRecu.depuisJson(_map(c))],
      );
}

/// Erreur renvoyée par l'API avec un code HTTP.
class ErreurProtocole implements Exception {
  final int codeHttp;
  final String code;
  final String message;

  const ErreurProtocole(this.codeHttp, this.code, this.message);

  Map<String, Object?> versJson() => {'erreur': code, 'message': message};

  @override
  String toString() => 'ErreurProtocole($codeHttp, $code) : $message';
}
