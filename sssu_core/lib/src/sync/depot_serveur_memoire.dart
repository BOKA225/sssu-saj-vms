/// Dépôt du poste central en mémoire, pour les tests automatiques.
/// Les transactions sont exécutées l'une après l'autre ; en cas d'erreur,
/// l'état antérieur est restauré.
library;

import 'dart:async';

import '../commun/commun.dart';
import '../schema/registre.dart';
import 'depot_serveur.dart';
import 'enregistrement.dart';

class DepotServeurMemoire implements DepotServeur {
  Map<String, Map<String, Enregistrement>> _tables = {};
  List<_Entree> _journal = [];
  int _seq = 0;
  Future<void> _file = Future.value();

  @override
  Future<T> transaction<T>(Future<T> Function(TransactionServeur tx) action) {
    final resultat = Completer<T>();
    _file = _file.then((_) async {
      final sauvegardeTables = {for (final e in _tables.entries) e.key: Map.of(e.value)};
      final sauvegardeJournal = List.of(_journal);
      final sauvegardeSeq = _seq;
      try {
        resultat.complete(await action(_Tx(this)));
      } catch (e, pile) {
        _tables = sauvegardeTables;
        _journal = sauvegardeJournal;
        _seq = sauvegardeSeq;
        resultat.completeError(e, pile);
      }
    });
    return resultat.future;
  }

  String _generation = nouvelId();

  @override
  Future<String> generation() async => _generation;

  /// Simule une restauration (tests) : les données reviennent à l'état de
  /// [instantane] et la génération change.
  void restaurer(InstantaneMemoire instantane) {
    _tables = {for (final e in instantane._tables.entries) e.key: Map.of(e.value)};
    _journal = List.of(instantane._journal);
    _seq = instantane._seq;
    _generation = nouvelId();
  }

  /// Copie de l'état actuel (sauvegarde simulée, tests).
  InstantaneMemoire instantane() => InstantaneMemoire._(
      {for (final e in _tables.entries) e.key: Map.of(e.value)}, List.of(_journal), _seq);

  /// Lecture directe pour les vérifications des tests.
  Enregistrement? lireDirect(String table, String id) => _tables[table]?[id];

  List<Enregistrement> tousDirect(String table) => List.of(_tables[table]?.values ?? const []);
}

class InstantaneMemoire {
  final Map<String, Map<String, Enregistrement>> _tables;
  final List<_Entree> _journal;
  final int _seq;
  InstantaneMemoire._(this._tables, this._journal, this._seq);
}

class _Entree {
  final int seq;
  final String table;
  final String id;
  final String? portee;
  final String? motif;
  _Entree(this.seq, this.table, this.id, this.portee, this.motif);
}

class _Tx implements TransactionServeur {
  final DepotServeurMemoire d;
  _Tx(this.d);

  @override
  Future<Enregistrement?> lire(String table, String id) async => d._tables[table]?[id];

  @override
  Future<void> ecrire(Enregistrement e, {String? motifChangement}) async {
    final spec = registreParNom[e.table];
    if (spec == null || !spec.surServeur) throw ArgumentError('Table inconnue du poste central : ${e.table}');
    final anomalies = e.anomaliesColonnes();
    if (anomalies.isNotEmpty) throw ArgumentError('${e.table}/${e.id} : ${anomalies.join(', ')}');
    // Contrainte d'unicité (comme en base).
    for (final cle in spec.clesNaturelles) {
      for (final autre in d._tables[e.table]?.values ?? const <Enregistrement>[]) {
        if (autre.id != e.id && cle.every((c) => autre.donnees[c] == e.donnees[c])) {
          throw StateError('Violation d\'unicité ${e.table}(${cle.join(', ')})');
        }
      }
    }
    (d._tables[e.table] ??= {})[e.id] = e.copier(versionBase: e.version);
    if (spec.receptionParTelephone || spec.parEtablissement) {
      d._seq++;
      d._journal.add(_Entree(d._seq, e.table, e.id, e.etablissementId, motifChangement));
    }
  }

  @override
  Future<List<Enregistrement>> chercher(String table, Map<String, Object?> egalites) async => [
        for (final e in d._tables[table]?.values ?? const <Enregistrement>[])
          if (!e.supprime && egalites.entries.every((x) => e.donnees[x.key] == x.value)) e
      ];

  @override
  Future<List<Enregistrement>> parPortee(String table, String etablissementId) async => [
        for (final e in d._tables[table]?.values ?? const <Enregistrement>[])
          if (!e.supprime && e.etablissementId == etablissementId) e
      ];

  @override
  Future<List<Changement>> changementsDepuis(
    int curseur, {
    required Set<String> tables,
    required Set<String> etablissements,
    required int limite,
  }) async {
    final resultat = <Changement>[];
    for (final entree in d._journal) {
      if (resultat.length >= limite) break;
      if (entree.seq <= curseur || !tables.contains(entree.table)) continue;
      if (entree.portee != null && !etablissements.contains(entree.portee)) continue;
      final e = d._tables[entree.table]![entree.id]!;
      resultat.add(Changement(entree.seq, e, motif: entree.motif));
    }
    return resultat;
  }
}
