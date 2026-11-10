import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:path/path.dart' as p;
import 'package:sssu_core/sssu_core.dart';

import '../securite/protection_cles.dart';

/// Certificat TLS auto-signé du poste central, créé au premier lancement
/// (validité 10 ans). Son empreinte SHA-256 est transmise aux téléphones dans
/// le QR code d'appairage : ils n'acceptent que ce certificat.
class CertificatPoste {
  final String certificatPem;
  final String clePriveePem;

  CertificatPoste(this.certificatPem, this.clePriveePem);

  static Future<CertificatPoste> chargerOuCreer(Directory dossier, {ProtectionCles? protection}) async {
    final prot = protection ?? ProtectionCles.systeme();
    final fCert = File(p.join(dossier.path, 'certificat.pem'));
    final fCle = File(p.join(dossier.path, 'cle_privee.pem'));
    if (fCert.existsSync() && fCle.existsSync()) {
      // Clé privée protégée par DPAPI (un ancien fichier en clair est converti).
      return CertificatPoste(fCert.readAsStringSync(), utf8.decode(await lireCle(fCle, prot)));
    }
    final paire = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privee = paire.privateKey as RSAPrivateKey;
    final publique = paire.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem({'CN': 'SSSU-SAJ VMS poste central', 'O': 'SSSU-SAJ'}, privee, publique);
    final cert = X509Utils.generateSelfSignedCertificate(privee, csr, 3650);
    final cle = CryptoUtils.encodeRSAPrivateKeyToPem(privee);
    fCert.writeAsStringSync(cert);
    await ecrireCle(fCle, utf8.encode(cle), prot);
    return CertificatPoste(cert, cle);
  }

  /// SHA-256 (hexadécimal) du certificat au format DER.
  String get empreinte {
    final b64 = certificatPem
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll(RegExp(r'\s'), '');
    return empreinteSha256Hex(base64.decode(b64));
  }

  SecurityContext contexte() => SecurityContext()
    ..useCertificateChainBytes(utf8.encode(certificatPem))
    ..usePrivateKeyBytes(utf8.encode(clePriveePem));
}
