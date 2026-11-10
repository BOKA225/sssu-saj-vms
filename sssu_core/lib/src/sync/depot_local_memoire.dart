/// Base locale de téléphone en mémoire (tests). Elle reproduit le
/// comportement de la base SQLite du téléphone vis-à-vis de la synchronisation.
library;

import '../commun/commun.dart';
import '../modeles/enums.dart';
import '../schema/registre.dart';
import 'client_sync.dart';
import 'enregistrement.dart';
import 'fichiers.dart';

class LigneLocale {
  final Enregistrement enregistrement;
  final EtatSync etat;
  final String? motif;
  const LigneLocale(this.enregistrement, this.etat, {this.motif});
}

class DepotLocalMemoire implements DepotLocalSync {
  final Horloge horloge;
  final String? appareilId;
  final Map<String, Map<String, LigneLocale>> _tables = {};
  int _curseur = 0;

  /// Fichiers en clair des photographies (identifiant → contenu).
  final Map<String, List<int>> fichiers = {};

  DepotLocalMemoire({this.horloge = const HorlogeSysteme(), this.appareilId});

  LigneLocale? ligne(String table, String id) => _tables[table]?[id];

  Enregistrement? lire(String table, String id) => ligne(table, id)?.enregistrement;

  List<Enregistrement> tous(String table) =>
      [for (final l in _tables[table]?.values ?? const <LigneLocale>[]) l.enregistrement];

  /// Saisie locale d'un nouvel enregistrement, à transmettre.
  Enregistrement creer(String table, Map<String, Object?> donnees,
      {required String utilisateurId, String? etablissementId, bool aTransmettre = true}) {
    final maintenant = horloge.maintenant();
    final e = Enregistrement(
      table: table,
      id: nouvelId(),
      version: 1,
      versionBase: 0,
      createdAt: maintenant,
      updatedAt: maintenant,
      createdBy: utilisateurId,
      updatedBy: utilisateurId,
      deviceId: appareilId,
      etablissementId: etablissementId,
      donnees: donnees,
    );
    (_tables[table] ??= {})[e.id] = LigneLocale(e, aTransmettre ? EtatSync.enAttente : EtatSync.local);
    return e;
  }

  /// Modification locale : la version devient « base + 1 » et l'enregistrement
  /// passe « en attente ».
  Enregistrement modifier(String table, String id, Map<String, Object?> changements, {required String utilisateurId}) {
    final l = ligne(table, id);
    if (l == null) throw StateError('$table/$id introuvable');
    final e = l.enregistrement.copier(
      version: l.enregistrement.versionBase + 1,
      updatedAt: horloge.maintenant(),
      updatedBy: utilisateurId,
      deviceId: appareilId,
      donnees: {...l.enregistrement.donnees, ...changements},
    );
    _tables[table]![id] = LigneLocale(e, EtatSync.enAttente);
    return e;
  }

  @override
  Future<List<Enregistrement>> enAttente({required int limite}) async {
    final specs = registre.where((t) => t.envoiParTelephone).toList()
      ..sort((a, b) => a.ordreEnvoi.compareTo(b.ordreEnvoi));
    final resultat = <Enregistrement>[];
    for (final s in specs) {
      for (final l in _tables[s.nom]?.values ?? const <LigneLocale>[]) {
        if (resultat.length >= limite) return resultat;
        if (l.etat == EtatSync.enAttente) resultat.add(l.enregistrement);
      }
    }
    return resultat;
  }

  @override
  Future<void> marquerSynchronise(Enregistrement envoye, int versionServeur) async {
    final l = ligne(envoye.table, envoye.id);
    if (l == null) return;
    final modifieDepuis = l.enregistrement.updatedAt != envoye.updatedAt;
    _tables[envoye.table]![envoye.id] = modifieDepuis
        ? LigneLocale(
            l.enregistrement.copier(version: versionServeur + 1, versionBase: versionServeur), EtatSync.enAttente)
        : LigneLocale(
            l.enregistrement.copier(version: versionServeur, versionBase: versionServeur), EtatSync.synchronise);
  }

  @override
  Future<void> marquerConflit(Enregistrement envoye, String motif) async {
    final l = ligne(envoye.table, envoye.id);
    if (l == null) return;
    _tables[envoye.table]![envoye.id] = LigneLocale(l.enregistrement, EtatSync.conflit, motif: motif);
  }

  @override
  Future<void> appliquerDistant(Enregistrement e, {required bool resolutionConflit}) async {
    final spec = registreParNom[e.table];
    if (spec == null || !spec.surMobile) return;
    final l = ligne(e.table, e.id);
    if (l != null) {
      final protege = l.etat == EtatSync.enAttente ||
          l.etat == EtatSync.local ||
          (l.etat == EtatSync.conflit && !resolutionConflit);
      if (protege) return;
      if (l.etat == EtatSync.synchronise && e.version < l.enregistrement.versionBase) return;
    }
    (_tables[e.table] ??= {})[e.id] = LigneLocale(e.copier(versionBase: e.version), EtatSync.synchronise);
  }

  @override
  Future<void> enTransaction(Future<void> Function() action) => action();

  @override
  Future<List<FichierLocal>> fichiersATransferer() async => [
        for (final t in tablesAvecFichier)
          for (final l in _tables[t]?.values ?? const <LigneLocale>[])
            if (l.etat == EtatSync.synchronise &&
                !l.enregistrement.supprime &&
                l.enregistrement.donnees['statut_transfert'] != 'confirme')
              FichierLocal(t, l.enregistrement.id, l.enregistrement.donnees['empreinte_sha256']! as String),
      ];

  @override
  Future<List<int>?> lireFichier(FichierLocal f) async => fichiers[f.id];

  @override
  Future<void> marquerFichierTransfere(FichierLocal f) async {
    final l = ligne(f.table, f.id)!;
    _tables[f.table]![f.id] = LigneLocale(
        l.enregistrement.copier(donnees: {...l.enregistrement.donnees, 'statut_transfert': 'confirme'}), l.etat);
    fichiers.remove(f.id);
  }

  String? _generation;

  @override
  Future<String?> generationServeur() async => _generation;

  @override
  Future<void> definirGenerationServeur(String generation) async => _generation = generation;

  @override
  Future<Set<String>> preparerReprise() async {
    final cles = <String>{};
    for (final t in _tables.entries) {
      if (registreParNom[t.key]?.envoiParTelephone != true) continue;
      for (final l in t.value.entries.toList()) {
        if (l.value.etat != EtatSync.synchronise) continue;
        t.value[l.key] = LigneLocale(l.value.enregistrement, EtatSync.enAttente);
        cles.add('${t.key}/${l.key}');
      }
    }
    return cles;
  }

  @override
  Future<int> curseur() async => _curseur;

  @override
  Future<void> definirCurseur(int curseur) async => _curseur = curseur;
}
