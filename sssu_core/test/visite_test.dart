import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

void main() {
  FormulaireVisite nouveau() =>
      FormulaireVisite(eleveId: 'e1', agentId: 'a1', dateVisite: DateTime.utc(2026, 11, 10));

  group('Formulaire de visite', () {
    test('valeurs initiales : toutes les rubriques présentes, rien d\'examiné', () {
      final f = nouveau();
      expect(f.antecedents.keys, TypeAntecedent.values);
      expect(f.examens.values.every((e) => e.resultat == ResultatExamen.nonExamine), isTrue);
      expect(f.statut, StatutVisite.ebauche);
      expect(f.modifiable, isTrue);
      expect(f.imc, isNull);
    });

    test('IMC calculé automatiquement et interprété selon l\'âge', () {
      final f = nouveau()
        ..poidsKg = 70
        ..tailleCm = 175;
      expect(f.imc, 22.9);
      final i = f.interpretationImc(sexe: Sexe.masculin, dateNaissance: DateTime.utc(2005, 1, 1));
      expect(i!.categorie, CategorieImc.normal);
      expect(i.methode, MethodeImc.adulte);
      expect(f.donneesVisite(interpretation: i)['imc_interpretation'], 'normal');
      expect(f.interpretationImc(sexe: Sexe.masculin, dateNaissance: null), isNull);
    });

    test('aller-retour avec les données de la table visite', () {
      final f = nouveau()
        ..poidsKg = 30.5
        ..taSys = 100
        ..taDia = 60
        ..conclusion = ConclusionVisite.suivi
        ..diagnostic = 'Caries multiples'
        ..dateControle = DateTime.utc(2026, 12, 10)
        ..statut = StatutVisite.enregistre;
      final d = f.donneesVisite();
      expect(registreParNom['visite']!.nomsColonnes, containsAll(d.keys));
      final g = nouveau()..chargerVisite(d);
      expect(g.donneesVisite(), d);
      expect(d['observations'], isNull, reason: 'texte vide enregistré comme absent');
    });

    test('rubrique gynécologique', () {
      final visite = DateTime.utc(2026, 11, 10);
      expect(rubriqueGynecologiqueVisible(Sexe.masculin, DateTime.utc(2010, 1, 1), visite), isFalse);
      expect(rubriqueGynecologiqueVisible(Sexe.feminin, DateTime.utc(2020, 1, 1), visite), isFalse);
      expect(rubriqueGynecologiqueVisible(Sexe.feminin, DateTime.utc(2015, 1, 1), visite), isTrue);
      expect(rubriqueGynecologiqueVisible(Sexe.feminin, null, visite), isTrue);
    });
  });

  group('Contrôles avant transmission', () {
    test('conclusion obligatoire', () {
      final c = controlerVisite(nouveau(), aujourdhui: DateTime.utc(2026, 11, 10));
      expect(c.transmissible, isFalse);
      expect(c.erreurs, contains('Choisir la conclusion de la visite.'));
      expect(c.avertissements, contains('Aucun examen par appareil n\'a été renseigné.'));
    });

    test('référence : structure et diagnostic exigés ; précision des pathologies', () {
      final f = nouveau()
        ..conclusion = ConclusionVisite.reference
        ..pathologies['autre'] = '';
      final c = controlerVisite(f, pathologiesAPreciser: {'autre'}, aujourdhui: DateTime.utc(2026, 11, 10));
      expect(c.erreurs, hasLength(3));
      f
        ..structureReference = 'CSU de Kouassi-Kouassikro'
        ..diagnostic = 'Otite'
        ..pathologies['autre'] = 'Otite chronique';
      expect(controlerVisite(f, pathologiesAPreciser: {'autre'}, aujourdhui: DateTime.utc(2026, 11, 10)).transmissible,
          isTrue);
    });

    test('avertissements : examen anormal sans observation, constantes, suivi sans rendez-vous', () {
      final f = nouveau()
        ..conclusion = ConclusionVisite.suivi
        ..diagnostic = 'Asthme'
        ..temperatureC = 45
        ..poidsKg = 30
        ..tailleCm = 135;
      f.examens[AppareilExamen.respiratoire]!.resultat = ResultatExamen.anormal;
      final c = controlerVisite(f, aujourdhui: DateTime.utc(2026, 11, 10));
      expect(c.transmissible, isTrue);
      expect(c.avertissements.join('\n'), allOf(contains('Examen respiratoire anormal'), contains('temperature_c'),
          contains('rendez-vous de contrôle')));
    });

    test('date de visite dans le futur refusée', () {
      final f = FormulaireVisite(eleveId: 'e', agentId: 'a', dateVisite: DateTime.utc(2026, 12, 25))
        ..conclusion = ConclusionVisite.sansAnomalie;
      expect(controlerVisite(f, aujourdhui: DateTime.utc(2026, 11, 10)).erreurs.first, contains('futur'));
    });
  });

  test('statut affiché', () {
    expect(statutAffiche(StatutVisite.ebauche, EtatSync.local), 'Ébauche');
    expect(statutAffiche(StatutVisite.enregistre, EtatSync.local), 'Enregistré localement');
    expect(statutAffiche(StatutVisite.enAttente, EtatSync.enAttente), 'En attente de synchronisation');
    expect(statutAffiche(StatutVisite.enAttente, EtatSync.synchronise), 'Synchronisé');
    expect(statutAffiche(StatutVisite.valide, EtatSync.synchronise), 'Validé');
    expect(statutAffiche(StatutVisite.enAttente, EtatSync.conflit), 'À vérifier (conflit)');
  });

  group('Chiffrement des fichiers', () {
    final cle = List<int>.generate(32, (i) => i);

    test('aller-retour, nonce différent à chaque chiffrement', () async {
      final c = ChiffreurFichiers(cle);
      final clair = List<int>.generate(5000, (i) => i % 251);
      final a = await c.chiffrer(clair);
      final b = await c.chiffrer(clair);
      expect(a, isNot(b));
      expect(String.fromCharCodes(a.take(4)), 'SSV1');
      expect(await c.dechiffrer(a), clair);
    });

    test('altération ou mauvaise clé détectée', () async {
      final c = ChiffreurFichiers(cle);
      final a = await c.chiffrer([1, 2, 3]);
      a[a.length - 1] ^= 1;
      await expectLater(c.dechiffrer(a), throwsA(isA<ErreurDechiffrement>()));
      final autre = ChiffreurFichiers(List<int>.filled(32, 7));
      await expectLater(autre.dechiffrer(await c.chiffrer([1, 2, 3])), throwsA(isA<ErreurDechiffrement>()));
      expect(() => ChiffreurFichiers([1, 2]), throwsArgumentError);
    });

    test('empreinte SHA-256', () {
      expect(sha256HexTexte('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
  });
}
