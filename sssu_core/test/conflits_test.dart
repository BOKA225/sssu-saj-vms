import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

Enregistrement _e({
  String table = 'eleve',
  int version = 1,
  int base = 0,
  Map<String, Object?>? donnees,
  bool supprime = false,
}) =>
    Enregistrement(
      table: table,
      id: 'id-1',
      version: version,
      versionBase: base,
      createdAt: DateTime.utc(2026, 11, 10),
      updatedAt: DateTime.utc(2026, 11, 10),
      deletedAt: supprime ? DateTime.utc(2026, 11, 11) : null,
      donnees: donnees ?? {'nom': 'KOUASSI', 'prenoms': 'Aya', 'sexe': 'F'},
    );

void main() {
  test('création : acceptée', () {
    expect(decider(_e(), null).type, TypeDecision.accepter);
  });

  test('renvoi identique (accusé perdu) : déjà reçu', () {
    expect(decider(_e(version: 2, base: 1), _e(version: 2, base: 2)).type, TypeDecision.dejaRecu);
  });

  test('modification à partir de la version courante : acceptée', () {
    final serveur = _e(version: 3, base: 3);
    final entrant = _e(version: 4, base: 3, donnees: {'nom': 'KOUASSI', 'prenoms': 'Aya Marie', 'sexe': 'F'});
    expect(decider(entrant, serveur).type, TypeDecision.accepter);
  });

  test('modification concurrente : conflit', () {
    final serveur = _e(version: 3, base: 3, donnees: {'nom': 'KOUASSI', 'prenoms': 'Aya', 'sexe': 'F', 'telephone_contact': '07'});
    final entrant = _e(version: 3, base: 2, donnees: {'nom': 'KOUASSY', 'prenoms': 'Aya', 'sexe': 'F'});
    final d = decider(entrant, serveur);
    expect(d.type, TypeDecision.conflit);
    expect(d.typeConflit, TypesConflit.modificationConcurrente);
  });

  test('suppression contre modification : conflit', () {
    final serveur = _e(version: 2, base: 2, supprime: true);
    final entrant = _e(version: 2, base: 1, donnees: {'nom': 'X', 'prenoms': 'Y', 'sexe': 'M'});
    expect(decider(entrant, serveur).typeConflit, TypesConflit.suppressionModification);
  });

  test('version annoncée inconnue du serveur : conflit, rien n\'est écrasé', () {
    final serveur = _e(version: 2, base: 2);
    final entrant = _e(version: 6, base: 5, donnees: {'nom': 'Z', 'prenoms': 'Y', 'sexe': 'M'});
    expect(decider(entrant, serveur).type, TypeDecision.conflit);
  });

  test('visite validée : modification refusée', () {
    final d = {'eleve_id': 'e', 'agent_id': 'a', 'date_visite': '2026-11-10', 'statut': 'valide'};
    final serveur = _e(table: 'visite', version: 2, base: 2, donnees: d);
    final entrant = _e(table: 'visite', version: 3, base: 2, donnees: {...d, 'observations': 'ajout'});
    final r = decider(entrant, serveur);
    expect(r.type, TypeDecision.refuser);
    expect(r.motif, 'visite_validee');
  });
}
