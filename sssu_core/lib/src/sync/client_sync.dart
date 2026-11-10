/// Synchronisation côté téléphone : envoi des modifications locales par lots,
/// application des accusés, puis réception des changements du poste central.
library;

import '../commun/chiffrement.dart';
import '../commun/commun.dart';
import 'enregistrement.dart';
import 'fichiers.dart';
import 'identite_appareil.dart';
import 'protocole.dart';

/// Fichier (photographie) à transmettre au poste central.
class FichierLocal {
  final String table;
  final String id;
  final String empreinte;
  const FichierLocal(this.table, this.id, this.empreinte);
}

/// Base locale du téléphone vue par la synchronisation.
abstract class DepotLocalSync {
  /// Enregistrements à transmettre (`sync_status = en_attente`), parents
  /// avant enfants (ordre d'envoi du registre), au plus [limite].
  Future<List<Enregistrement>> enAttente({required int limite});

  /// Le poste central a enregistré [envoye] en version [versionServeur].
  /// Si l'enregistrement a été modifié localement depuis l'envoi, il reste
  /// à transmettre, sur la base de cette nouvelle version.
  Future<void> marquerSynchronise(Enregistrement envoye, int versionServeur);

  /// Refus ou conflit : l'enregistrement est conservé tel quel avec l'état
  /// « conflit » et le motif, en attente de décision sur le poste central.
  Future<void> marquerConflit(Enregistrement envoye, String motif);

  /// Applique un changement reçu. Une modification locale non encore
  /// transmise (ou en conflit) n'est jamais écrasée, sauf par la décision
  /// du Médecin-Chef sur ce conflit ([resolutionConflit]).
  Future<void> appliquerDistant(Enregistrement e, {required bool resolutionConflit});

  Future<int> curseur();
  Future<void> definirCurseur(int curseur);

  /// Exécute [action] dans une transaction (une page de réception) : sur le
  /// téléphone, les contrôles de clés étrangères y sont différés, si bien
  /// qu'un enfant reçu avant son parent dans la même page est accepté.
  Future<void> enTransaction(Future<void> Function() action);

  /// Photographies dont les données sont synchronisées mais dont le fichier
  /// n'a pas encore été confirmé par le poste central.
  Future<List<FichierLocal>> fichiersATransferer();

  /// Contenu en clair du fichier, ou `null` s'il est introuvable.
  Future<List<int>?> lireFichier(FichierLocal f);

  /// Réception confirmée : statut « confirme » ; la copie du téléphone peut être effacée.
  Future<void> marquerFichierTransfere(FichierLocal f);

  /// Dernière génération connue du poste central (`null` avant la première synchronisation).
  Future<String?> generationServeur();
  Future<void> definirGenerationServeur(String generation);

  /// Reprise après restauration du poste central : les enregistrements
  /// synchronisés des tables que le téléphone peut envoyer repassent « en
  /// attente » (version inchangée), pour être renvoyés. Retourne leurs clés
  /// `table/id`.
  Future<Set<String>> preparerReprise();
}

/// Canal de communication avec le poste central (HTTP en production,
/// appel direct possible dans les tests).
abstract class TransportSync {
  Future<ReponseAppairage> appairer(DemandeAppairage demande);
  Future<ReponseJeton> obtenirJeton(DemandeJeton demande);
  Future<ReponseEnvoi> envoyer(String jeton, DemandeEnvoi demande);
  Future<ReponseReception> recevoir(String jeton, int curseur);
  Future<EtatFichier> etatFichier(String jeton, String table, String id);
  Future<void> envoyerMorceau(String jeton, String table, String id, int numero, List<int> octets);
  Future<void> terminerFichier(String jeton, String table, String id, int nombreMorceaux);
}

class RapportSync {
  int envoyes = 0;
  int acceptes = 0;
  int dejaRecus = 0;
  int conflits = 0;
  int refuses = 0;
  int recus = 0;
  int fichiers = 0;
  int fichiersEnEchec = 0;

  /// Synchronisation de reprise après une restauration du poste central.
  bool reprise = false;

  /// Reprise : copies renvoyées que le poste n'a pas reprises (refus).
  int nonRepris = 0;
  final List<String> motifs = [];
  DateTime? debut;
  DateTime? fin;

  bool get sansIncident => conflits == 0 && refuses == 0 && fichiersEnEchec == 0;

  @override
  String toString() => '${reprise ? 'reprise après restauration du poste central — ' : ''}envoyés $envoyes (acceptés $acceptes, déjà reçus $dejaRecus, conflits $conflits, '
      'refusés $refuses), reçus $recus, photos transférées $fichiers'
      '${fichiersEnEchec == 0 ? '' : ' ($fichiersEnEchec en échec)'}';
}

class ClientSynchronisation {
  final DepotLocalSync depot;
  final TransportSync transport;
  final IdentiteAppareil identite;
  final Horloge horloge;
  final String canal;
  final int tailleLot;

  String? _jeton;
  DateTime? _expiration;
  String? _generation;

  ClientSynchronisation({
    required this.depot,
    required this.transport,
    required this.identite,
    this.horloge = const HorlogeSysteme(),
    this.canal = 'wifi',
    this.tailleLot = 200,
  });

  Future<String> _jetonValide() async {
    final maintenant = horloge.maintenant();
    if (_jeton == null || _expiration == null || !_expiration!.isAfter(maintenant.add(const Duration(minutes: 1)))) {
      final r = await transport.obtenirJeton(await identite.demandeJeton(horloge));
      _jeton = r.jeton;
      _expiration = r.expireLe;
      _generation = r.generation;
    }
    return _jeton!;
  }

  /// Cycle complet : envoi puis réception. En cas d'interruption (réseau),
  /// une nouvelle synchronisation reprend là où la précédente s'est arrêtée :
  /// les enregistrements non acquittés restent « en attente » et le curseur
  /// n'avance qu'après application des changements reçus.
  Future<RapportSync> synchroniser() async {
    final rapport = RapportSync()..debut = horloge.maintenant();
    // Nouveau jeton à chaque synchronisation : il porte la génération actuelle
    // du poste central (et le poste a pu redémarrer depuis la précédente).
    _jeton = null;
    final jeton = await _jetonValide();

    // Le poste central a été restauré depuis une sauvegarde : le téléphone
    // renvoie ce qu'il détient, puis recharge tout depuis le début.
    final generation = _generation;
    final connue = await depot.generationServeur();
    final reprise = generation != null && connue != null && connue != generation;
    var renvoyes = const <String>{};
    if (reprise) {
      rapport.reprise = true;
      renvoyes = await depot.preparerReprise();
      await depot.definirCurseur(0);
    }

    // Envoi par lots.
    final dejaEnvoyes = <String>{};
    while (true) {
      final lot = (await depot.enAttente(limite: tailleLot))
          .where((e) => !dejaEnvoyes.contains('${e.table}/${e.id}'))
          .toList();
      if (lot.isEmpty) break;
      final reponse =
          await transport.envoyer(jeton, DemandeEnvoi(enregistrements: lot, canal: canal, reprise: reprise));
      final parCle = {for (final e in lot) '${e.table}/${e.id}': e};
      for (final a in reponse.accuses) {
        final envoye = parCle['${a.table}/${a.id}'];
        if (envoye == null) continue;
        dejaEnvoyes.add('${a.table}/${a.id}');
        switch (a.statut) {
          case StatutAccuse.accepte:
            rapport.acceptes++;
            await depot.marquerSynchronise(envoye, a.version!);
          case StatutAccuse.dejaRecu:
            rapport.dejaRecus++;
            await depot.marquerSynchronise(envoye, a.version!);
          case StatutAccuse.conflit:
            rapport.conflits++;
            rapport.motifs.add('${a.table} : ${a.motif}');
            await depot.marquerConflit(envoye, a.motif ?? 'conflit');
          case StatutAccuse.refuse when reprise && renvoyes.contains('${a.table}/${a.id}'):
            // Copie déjà synchronisée avant la restauration, que le poste ne
            // reprend pas : elle redevient « synchronisée » ; la réception
            // complète qui suit apporte la version du poste, s'il en a une.
            rapport.nonRepris++;
            await depot.marquerSynchronise(envoye, envoye.versionBase);
          case StatutAccuse.refuse:
            rapport.refuses++;
            rapport.motifs.add('${a.table} : ${a.motif}');
            await depot.marquerConflit(envoye, a.motif ?? 'refus');
        }
      }
      rapport.envoyes += lot.length;
      // Garde-fou : un lot sans aucun accusé exploitable arrête la boucle.
      if (lot.every((e) => !dejaEnvoyes.contains('${e.table}/${e.id}'))) {
        throw StateError('Le poste central n\'a renvoyé aucun accusé pour ce lot.');
      }
    }

    // Photographies : après leurs données, morceau par morceau, en reprenant
    // un transfert interrompu là où il s'était arrêté.
    for (final f in await depot.fichiersATransferer()) {
      try {
        await _transferer(jeton, f);
        rapport.fichiers++;
      } on ErreurProtocole catch (e) {
        rapport.fichiersEnEchec++;
        rapport.motifs.add('Photo ${f.id.substring(0, 8)} : ${e.message}');
      } catch (e) {
        // Coupure réseau pendant un transfert : les morceaux déjà reçus sont
        // gardés par le poste ; la suite partira à la prochaine synchronisation.
        rapport.fichiersEnEchec++;
        rapport.motifs.add('Photo ${f.id.substring(0, 8)} : transfert interrompu.');
        break;
      }
    }

    // Réception.
    var curseur = await depot.curseur();
    while (true) {
      final r = await transport.recevoir(jeton, curseur);
      await depot.enTransaction(() async {
        for (final c in r.changements) {
          await depot.appliquerDistant(c.enregistrement, resolutionConflit: c.resolutionConflit);
        }
        await depot.definirCurseur(r.curseur);
      });
      rapport.recus += r.changements.length;
      curseur = r.curseur;
      if (!r.suite) break;
    }
    if (generation != null && generation != connue) await depot.definirGenerationServeur(generation);
    rapport.fin = horloge.maintenant();
    return rapport;
  }

  Future<void> _transferer(String jeton, FichierLocal f) async {
    final contenu = await depot.lireFichier(f);
    if (contenu == null || contenu.isEmpty) {
      throw const ErreurProtocole(0, 'fichier_absent', 'fichier introuvable sur le téléphone.');
    }
    if (sha256Hex(contenu) != f.empreinte) {
      throw const ErreurProtocole(0, 'fichier_altere', 'fichier altéré sur le téléphone.');
    }
    final etat = await transport.etatFichier(jeton, f.table, f.id);
    if (!etat.complet) {
      final n = (contenu.length + tailleMorceau - 1) ~/ tailleMorceau;
      for (var i = 0; i < n; i++) {
        if (etat.morceauxRecus.contains(i)) continue;
        final fin = (i + 1) * tailleMorceau;
        await transport.envoyerMorceau(
            jeton, f.table, f.id, i, contenu.sublist(i * tailleMorceau, fin > contenu.length ? contenu.length : fin));
      }
      await transport.terminerFichier(jeton, f.table, f.id, n);
    }
    await depot.marquerFichierTransfere(f);
  }
}
