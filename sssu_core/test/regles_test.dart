import 'package:sssu_core/sssu_core.dart';
import 'package:test/test.dart';

void main() {
  group('Âge', () {
    test('années et mois révolus', () {
      expect(calculerAge(DateTime.utc(2015, 4, 12), DateTime.utc(2026, 11, 10)), const Age(11, 6));
      expect(calculerAge(DateTime.utc(2015, 11, 10), DateTime.utc(2026, 11, 10)), const Age(11, 0));
      expect(calculerAge(DateTime.utc(2015, 11, 11), DateTime.utc(2026, 11, 10)), const Age(10, 11));
    });

    test('né un 29 février', () {
      expect(calculerAge(DateTime.utc(2016, 2, 29), DateTime.utc(2027, 2, 28)), const Age(10, 11));
      expect(calculerAge(DateTime.utc(2016, 2, 29), DateTime.utc(2027, 3, 1)), const Age(11, 0));
    });

    test('âge en mois et refus d\'une naissance future', () {
      expect(calculerAge(DateTime.utc(2021, 10, 1), DateTime.utc(2026, 11, 10)).enMois, 61);
      expect(() => calculerAge(DateTime.utc(2027, 1, 1), DateTime.utc(2026, 11, 10)), throwsArgumentError);
    });
  });

  group('IMC', () {
    test('calcul et arrondi', () {
      expect(calculerImc(poidsKg: 30, tailleCm: 140), 15.3);
      expect(calculerImc(poidsKg: 70, tailleCm: 175), 22.9);
      expect(() => calculerImc(poidsKg: 0, tailleCm: 140), throwsArgumentError);
    });

    // Paramètres LMS FICTIFS, uniquement pour vérifier la formule et les seuils.
    // Ce ne sont pas les valeurs de l'OMS.
    final table = TableImcOmsCsv.depuisCsv(
      garcons: 'mois,L,M,S\n132,1,20,0.1\n',
      filles: 'mois;L;M;S\n132;0;20;0,1\n',
    );

    test('lecture CSV (virgule ou point-virgule, virgule décimale)', () {
      expect(table.nombreDeLignes, 2);
      expect(table.lms(Sexe.feminin, 132)!.s, 0.1);
      expect(table.lms(Sexe.masculin, 133), isNull);
    });

    test('score z LMS, y compris L = 0', () {
      expect(scoreZLms(20, const Lms(1, 20, 0.1)), closeTo(0, 1e-9));
      expect(scoreZLms(24, const Lms(1, 20, 0.1)), closeTo(2, 1e-9));
      expect(scoreZLms(20 * 1.1051709, const Lms(0, 20, 0.1)), closeTo(1, 1e-6));
    });

    test('classement entre 5 et 19 ans', () {
      const age = Age(11, 0);
      CategorieImc c(double imc) => interpreterImc(imc: imc, sexe: Sexe.masculin, age: age, table: table).categorie;
      expect(c(13.9), CategorieImc.maigreurSevere); // z = -3,05
      expect(c(15.9), CategorieImc.maigreur); // z = -2,05
      expect(c(20), CategorieImc.normal);
      expect(c(22.1), CategorieImc.surpoids); // z = 1,05
      expect(c(24.1), CategorieImc.obesite); // z = 2,05
    });

    test('seuils adultes à partir de 19 ans', () {
      CategorieImc c(double imc) => interpreterImc(imc: imc, sexe: Sexe.feminin, age: const Age(21, 0)).categorie;
      expect(c(15.5), CategorieImc.maigreurSevere);
      expect(c(18), CategorieImc.maigreur);
      expect(c(22), CategorieImc.normal);
      expect(c(27), CategorieImc.surpoids);
      expect(c(31), CategorieImc.obesite);
    });

    test('non interprétable avant 5 ans ou sans table', () {
      expect(interpreterImc(imc: 16, sexe: Sexe.masculin, age: const Age(4, 6), table: table).categorie,
          CategorieImc.nonInterpretable);
      expect(interpreterImc(imc: 16, sexe: Sexe.masculin, age: const Age(8, 0), table: table).categorie,
          CategorieImc.nonInterpretable);
    });
  });

  group('Vraisemblance des constantes', () {
    test('valeurs normales : aucune alerte', () {
      expect(
          verifierConstantes(
              poidsKg: 32, tailleCm: 140, taSys: 105, taDia: 65, temperatureC: 36.8, fc: 85, fr: 20),
          isEmpty);
    });

    test('erreurs de saisie signalées', () {
      final alertes = verifierConstantes(tailleCm: 14, temperatureC: 45, taSys: 80, taDia: 90);
      expect(alertes.map((a) => a.champ), containsAll(['taille_cm', 'temperature_c', 'ta_dia']));
      expect(verifierConstantes(taSys: 110).map((a) => a.champ), contains('ta_sys'));
    });
  });

  group('Conformité des inspections', () {
    test('taux et niveau', () {
      final r = calculerConformite([
        ...List.filled(6, ResultatInspection.conforme),
        ResultatInspection.partiel,
        ResultatInspection.nonConforme,
        ResultatInspection.nonApplicable,
      ]);
      expect(r.conformes, 6);
      expect(r.partiels, 1);
      expect(r.nonConformes, 1);
      expect(r.nonApplicables, 1);
      expect(r.taux, 81.3); // (6 + 0,5) / 8
      expect(r.niveau, NiveauConformite.satisfaisant);
    });

    test('seuils', () {
      expect(calculerConformite([ResultatInspection.conforme, ResultatInspection.nonConforme]).niveau,
          NiveauConformite.moyen);
      expect(calculerConformite([ResultatInspection.partiel, ResultatInspection.nonConforme]).niveau,
          NiveauConformite.insuffisant);
      expect(calculerConformite([ResultatInspection.conforme, ResultatInspection.nonConforme], seuilSatisfaisant: 50)
          .niveau, NiveauConformite.satisfaisant);
    });

    test('aucun critère évalué', () {
      final r = calculerConformite([ResultatInspection.nonApplicable]);
      expect(r.taux, isNull);
      expect(r.niveau, isNull);
    });
  });

  group('Identité et doublons', () {
    test('normalisation', () {
      expect(normaliserTexte("  N'Guessan   Aya-Marie "), 'N GUESSAN AYA MARIE');
      expect(normaliserTexte('Kouamé Chloé'), 'KOUAME CHLOE');
      expect(normaliserMatricule(' 1234-5678 a '), '12345678A');
      expect(normaliserMatricule(' - '), isNull);
    });

    test('sexe et date de naissance', () {
      expect(lireSexe('Garçon'), Sexe.masculin);
      expect(lireSexe('f'), Sexe.feminin);
      expect(lireSexe('?'), isNull);
      expect(lireDateNaissance('12/04/2015'), DateTime.utc(2015, 4, 12));
      expect(lireDateNaissance('2015-4-2'), DateTime.utc(2015, 4, 2));
      expect(lireDateNaissance('31/02/2015'), isNull);
      expect(lireDateNaissance('avril 2015'), isNull);
    });

    test('doublons par matricule puis par nom, prénoms et date', () {
      final existants = [
        IdentiteEleve(id: '1', matricule: '12345678A', nom: 'KOUASSI', prenoms: 'Aya', dateNaissance: DateTime.utc(2015, 4, 12)),
      ];
      final candidats = [
        const IdentiteEleve(matricule: '1234 5678a', nom: 'Kouassi', prenoms: 'Aya'),
        IdentiteEleve(nom: 'Kouassi', prenoms: 'Aya', dateNaissance: DateTime.utc(2015, 4, 12)),
        IdentiteEleve(nom: 'Yao', prenoms: 'Koffi', dateNaissance: DateTime.utc(2014, 1, 1)),
        IdentiteEleve(nom: 'YAO', prenoms: 'Koffi', dateNaissance: DateTime.utc(2014, 1, 1)),
      ];
      final d = detecterDoublons(candidats, existants);
      expect(d.length, 3);
      expect(d[0].motif, MotifDoublon.memeMatricule);
      expect(d[1].motif, MotifDoublon.memesNomPrenomsDateNaissance);
      expect(d[2].existant, same(candidats[2])); // doublon à l'intérieur du fichier importé
    });
  });

  group('Modèles', () {
    test('aller-retour vers les données synchronisées', () {
      final v = Visite(
        id: nouvelId(),
        eleveId: 'e',
        agentId: 'a',
        dateVisite: DateTime.utc(2026, 11, 10),
        statut: StatutVisite.enAttente,
        poidsKg: 32.5,
        conclusion: ConclusionVisite.suivi,
      );
      final copie = Visite.depuisDonnees(v.id, v.versDonnees());
      expect(copie.versDonnees(), v.versDonnees());
      expect(registreParNom['visite']!.nomsColonnes, containsAll(v.versDonnees().keys));
    });

    test('les modèles n\'utilisent que des colonnes du registre', () {
      final e = Eleve(id: 'x', nom: 'A', prenoms: 'B', sexe: Sexe.feminin, dateNaissance: DateTime.utc(2015, 1, 2));
      expect(registreParNom['eleve']!.nomsColonnes, containsAll(e.versDonnees().keys));
      const u = Utilisateur(id: 'u', identifiant: 'u', nom: 'U', roleId: 'r');
      expect(registreParNom['utilisateur']!.nomsColonnes, containsAll(u.versDonnees().keys));
      expect(Eleve.depuisDonnees('x', e.versDonnees()).dateNaissance, DateTime.utc(2015, 1, 2));
    });
  });
}
