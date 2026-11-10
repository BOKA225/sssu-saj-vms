/// Transfert des photographies du téléphone vers le poste central, par
/// morceaux de 512 Ko qui peuvent être renvoyés après une interruption.
/// Le poste vérifie l'empreinte SHA-256 avant de confirmer la réception ;
/// le téléphone ne supprime sa copie qu'après cette confirmation.
library;

import '../commun/chiffrement.dart';
import '../commun/commun.dart';
import 'depot_serveur.dart';
import 'protocole.dart';

const int tailleMorceau = 512 * 1024;
const int tailleMaxFichier = 15 * 1024 * 1024;

/// Tables dont les enregistrements portent un fichier (photographie).
const Set<String> tablesAvecFichier = {'photo', 'inspection_photo'};

/// Stockage des fichiers reçus sur le poste central (chiffré sur disque dans
/// l'application Windows, en mémoire dans les tests).
abstract class StockageFichiersServeur {
  Future<bool> disponible(String id);
  Future<void> ecrire(String id, List<int> clair, {required String empreinteAttendue});
}

class StockageFichiersMemoire implements StockageFichiersServeur {
  final Map<String, List<int>> fichiers = {};

  @override
  Future<bool> disponible(String id) async => fichiers.containsKey(id);

  @override
  Future<void> ecrire(String id, List<int> clair, {required String empreinteAttendue}) async {
    if (sha256Hex(clair) != empreinteAttendue) throw StateError('Empreinte incorrecte.');
    fichiers[id] = List.of(clair);
  }
}

class _Reception {
  final Map<int, List<int>> morceaux = {};
  DateTime derniereActivite;
  _Reception(this.derniereActivite);
  int get taille => morceaux.values.fold(0, (s, m) => s + m.length);
}

class EtatFichier {
  final bool complet;
  final List<int> morceauxRecus;
  const EtatFichier(this.complet, this.morceauxRecus);

  Map<String, Object?> versJson() => {'complet': complet, 'morceaux': morceauxRecus};
  factory EtatFichier.depuisJson(Map<String, Object?> j) =>
      EtatFichier(j['complet'] == true, [for (final n in (j['morceaux'] as List?) ?? const []) (n as num).toInt()]);
}

/// Réception des fichiers sur le poste central. Les morceaux en cours sont
/// gardés en mémoire (au plus [memoireMax] octets au total) et oubliés après
/// une heure d'inactivité : le téléphone renvoie alors les morceaux manquants.
class ServiceFichiers {
  final DepotServeur depot;
  final StockageFichiersServeur stockage;
  final Horloge horloge;
  final int memoireMax;
  final Map<String, _Reception> _enCours = {};

  ServiceFichiers({
    required this.depot,
    required this.stockage,
    this.horloge = const HorlogeSysteme(),
    this.memoireMax = 200 * 1024 * 1024,
  });

  /// L'enregistrement existe, n'est pas supprimé et appartient à un
  /// établissement affecté à l'appareil. Retourne l'empreinte attendue.
  Future<String> _verifier(String appareilId, String table, String id) async {
    if (!tablesAvecFichier.contains(table)) throw const ErreurProtocole(404, 'table', 'Aucun fichier pour cette table.');
    return depot.transaction((tx) async {
      final e = await tx.lire(table, id);
      if (e == null || e.supprime) {
        throw const ErreurProtocole(404, 'inconnu', 'Photographie inconnue du poste central : synchroniser d\'abord ses données.');
      }
      final liens = await tx.chercher('appareil_etablissement', {'appareil_id': appareilId});
      if (!liens.any((l) => l.donnees['etablissement_id'] == e.etablissementId)) {
        throw const ErreurProtocole(403, 'etablissement_non_affecte', 'Établissement non affecté à cet appareil.');
      }
      return e.donnees['empreinte_sha256']! as String;
    });
  }

  void _purger() {
    final limite = horloge.maintenant().subtract(const Duration(hours: 1));
    _enCours.removeWhere((_, r) => r.derniereActivite.isBefore(limite));
  }

  Future<EtatFichier> etat(String appareilId, String table, String id) async {
    await _verifier(appareilId, table, id);
    if (await stockage.disponible(id)) return const EtatFichier(true, []);
    final r = _enCours[id];
    return EtatFichier(false, r == null ? const [] : (r.morceaux.keys.toList()..sort()));
  }

  Future<void> recevoirMorceau(String appareilId, String table, String id, int numero, List<int> octets) async {
    await _verifier(appareilId, table, id);
    if (numero < 0 || numero * tailleMorceau >= tailleMaxFichier) {
      throw const ErreurProtocole(400, 'morceau', 'Numéro de morceau invalide.');
    }
    if (octets.isEmpty || octets.length > tailleMorceau) {
      throw const ErreurProtocole(400, 'morceau', 'Taille de morceau invalide.');
    }
    _purger();
    final total = _enCours.values.fold<int>(0, (s, r) => s + r.taille);
    if (total + octets.length > memoireMax) {
      throw const ErreurProtocole(503, 'occupe', 'Poste central occupé : réessayer plus tard.');
    }
    final r = _enCours.putIfAbsent(id, () => _Reception(horloge.maintenant()));
    r.morceaux[numero] = List.of(octets);
    r.derniereActivite = horloge.maintenant();
  }

  /// Assemble les [nombreMorceaux] morceaux, vérifie l'empreinte et enregistre
  /// le fichier. Le statut de transfert de l'enregistrement passe à « confirme ».
  Future<void> terminer(String appareilId, String table, String id, int nombreMorceaux) async {
    final empreinte = await _verifier(appareilId, table, id);
    if (await stockage.disponible(id)) return; // déjà reçu (confirmation perdue)
    final r = _enCours[id];
    final manquants = [for (var i = 0; i < nombreMorceaux; i++) if (r == null || !r.morceaux.containsKey(i)) i];
    if (manquants.isNotEmpty) {
      throw ErreurProtocole(409, 'incomplet', 'Morceaux manquants : ${manquants.join(', ')}.');
    }
    final contenu = <int>[for (var i = 0; i < nombreMorceaux; i++) ...r!.morceaux[i]!];
    _enCours.remove(id);
    if (sha256Hex(contenu) != empreinte) {
      throw const ErreurProtocole(422, 'empreinte', 'Fichier altéré pendant le transfert : il sera renvoyé.');
    }
    await stockage.ecrire(id, contenu, empreinteAttendue: empreinte);
    await depot.transaction((tx) async {
      final e = (await tx.lire(table, id))!;
      // Même version : seul le statut de transfert change, sur le poste comme sur le téléphone.
      await tx.ecrire(e.copier(donnees: {...e.donnees, 'statut_transfert': 'confirme'}));
    });
  }
}
