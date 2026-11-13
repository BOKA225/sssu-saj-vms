import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

import 'outils/environnement.dart';

/// Téléphone resté en version 1.1.x (protocole 1) face à un poste en 1.2 :
/// il reçoit ce que sa base sait enregistrer, puis un refus clair au lieu
/// d'une erreur de base de données.
void main() {
  test('critères de la nouvelle grille retenus pour un téléphone en protocole 1', () async {
    final env = await Environnement.creer();
    final id = await env.appairer('Ancien', [env.etabA]);
    final m = env.horloge.maintenant();
    Enregistrement critere(String rubrique, String code) => Enregistrement(
        table: 'critere_inspection',
        id: nouvelId(),
        version: 1,
        versionBase: 1,
        createdAt: m,
        updatedAt: m,
        donnees: {'rubrique': rubrique, 'code': code, 'libelle': code, 'ordre': 1, 'actif': true});
    final ancien = critere('eau_potable', 'ancien');
    final nouveau = critere('latrines', 'C1');
    await env.depot.transaction((tx) async {
      await tx.ecrire(ancien);
      await tx.ecrire(nouveau);
    });

    // Protocole 2 (téléphone à jour) : tout est reçu.
    var tout = <String>{};
    var curseur = 0;
    while (true) {
      final r = await env.sync.preparerReception(id.appareilId, curseur);
      tout.addAll(r.changements.map((c) => c.enregistrement.id));
      curseur = r.curseur;
      if (!r.suite) break;
    }
    expect(tout, containsAll([ancien.id, nouveau.id]));

    // Protocole 1 : tout ce qui précède le premier critère nouveau, puis refus.
    final recus = <String>{};
    curseur = 0;
    ErreurProtocole? refus;
    for (var i = 0; i < 50; i++) {
      try {
        final r = await env.sync.preparerReception(id.appareilId, curseur, protocole: 1);
        recus.addAll(r.changements.map((c) => c.enregistrement.id));
        expect(r.changements.every((c) => SyncCompat.compatible(c.enregistrement)), isTrue);
        curseur = r.curseur;
        if (!r.suite) break;
      } on ErreurProtocole catch (e) {
        refus = e;
        break;
      }
    }
    expect(recus, contains(ancien.id));
    expect(recus, isNot(contains(nouveau.id)));
    expect(refus?.code, 'mise_a_jour_requise');
    expect(refus?.codeHttp, 426);
    expect(refus?.message, contains('installez la dernière version'));
  });
}

/// Raccourci de lecture.
abstract final class SyncCompat {
  static bool compatible(Enregistrement e) => ServiceSynchronisation.compatibleProtocole1(e);
}
