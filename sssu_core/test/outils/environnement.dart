/// Environnement de test : un poste central en mémoire avec des données
/// fictives (rôles, comptes, établissements, classes, élèves).
library;

import 'package:sssu_core/sssu_core.dart';

class Environnement {
  final HorlogeFixe horloge;
  final DepotServeurMemoire depot;
  final ServiceAuthentification auth;
  final ServiceSynchronisation sync;
  final ServiceAppairage appairage;
  final ServiceJetons jetons;
  final ServiceConflits conflits;
  final StockageFichiersMemoire stockage = StockageFichiersMemoire();
  late final ServiceFichiers fichiers = ServiceFichiers(depot: depot, stockage: stockage, horloge: horloge);

  late final String anneeId;
  late final String etabA;
  late final String etabB;
  late final String classeA;
  late final String classeB;
  late final String eleveA;
  late final String eleveB;
  late final Utilisateur admin;
  late final Utilisateur chef;
  late final Utilisateur medecin;
  late final Utilisateur agent1;
  late final Utilisateur agent2;

  Environnement._(this.horloge, this.depot, this.auth, this.sync, this.appairage, this.jetons, this.conflits);

  static const motDePasse = 'Test-2026!';

  static Future<Environnement> creer() async {
    final horloge = HorlogeFixe(DateTime.utc(2026, 11, 10, 8));
    final depot = DepotServeurMemoire();
    await initialiserRoles(depot, horloge: horloge);
    final auth = ServiceAuthentification(
      depot: DepotUtilisateursServeur(depot, horloge: horloge),
      hacheur: HacheurMotDePasse(parametres: ParametresArgon2.tests),
      horloge: horloge,
    );
    final env = Environnement._(
      horloge,
      depot,
      auth,
      ServiceSynchronisation(depot: depot, horloge: horloge),
      ServiceAppairage(depot: depot, horloge: horloge),
      ServiceJetons(depot: depot, horloge: horloge),
      ServiceConflits(depot: depot, horloge: horloge),
    );
    await env._remplir();
    return env;
  }

  Enregistrement _nouveau(String table, Map<String, Object?> donnees, {String? etab}) {
    final m = horloge.maintenant();
    return Enregistrement(
        table: table,
        id: nouvelId(),
        version: 1,
        versionBase: 1,
        createdAt: m,
        updatedAt: m,
        etablissementId: etab,
        donnees: donnees);
  }

  Future<void> _remplir() async {
    admin = await auth.creerPremierAdministrateur(identifiant: 'admin', nom: 'ADMIN', motDePasse: motDePasse);
    final droitsAdmin = await auth.droitsDe(admin);
    Future<Utilisateur> compte(String ident, RoleCode role) async {
      final u = await auth.creerUtilisateur(droitsAdmin,
          identifiant: ident, nom: ident.toUpperCase(), role: role, motDePasseTemporaire: motDePasse);
      return u;
    }

    chef = await compte('chef', RoleCode.medecinChef);
    medecin = await compte('medecin', RoleCode.medecin);
    agent1 = await compte('agent1', RoleCode.agent);
    agent2 = await compte('agent2', RoleCode.agent);

    await depot.transaction((tx) async {
      final annee = _nouveau('annee_scolaire',
          {'libelle': '2026-2027', 'date_debut': '2026-09-14', 'date_fin': '2027-07-16', 'active': true});
      anneeId = annee.id;
      await tx.ecrire(annee);
      Future<String> etab(String code) async {
        final id = nouvelId();
        final m = horloge.maintenant();
        await tx.ecrire(Enregistrement(
            table: 'etablissement',
            id: id,
            version: 1,
            versionBase: 1,
            createdAt: m,
            updatedAt: m,
            etablissementId: id,
            donnees: {'nom': 'École $code (TEST)', 'code': code, 'type': 'primaire', 'statut': 'public'}));
        return id;
      }

      etabA = await etab('TEST-A');
      etabB = await etab('TEST-B');
      Future<String> classe(String etabId, String libelle) async {
        final c = _nouveau('classe', {'etablissement_id': etabId, 'annee_scolaire_id': anneeId, 'libelle': libelle},
            etab: etabId);
        await tx.ecrire(c);
        return c.id;
      }

      classeA = await classe(etabA, 'CM2 A');
      classeB = await classe(etabB, 'CE1 B');
      Future<String> eleve(String etabId, String classeId, String matricule, String nom) async {
        final e = _nouveau('eleve',
            {'matricule': matricule, 'nom': nom, 'prenoms': 'Aya', 'date_naissance': '2015-04-12', 'sexe': 'F'},
            etab: etabId);
        await tx.ecrire(e);
        await tx.ecrire(_nouveau('inscription',
            {'eleve_id': e.id, 'classe_id': classeId, 'annee_scolaire_id': anneeId, 'statut': 'inscrit'},
            etab: etabId));
        return e.id;
      }

      eleveA = await eleve(etabA, classeA, '12345678A', 'KOUASSI');
      eleveB = await eleve(etabB, classeB, '87654321B', 'KONAN');
    });
  }

  Future<Droits> droits(Utilisateur u) => auth.droitsDe(u);

  /// Appaire un téléphone affecté aux établissements donnés et retourne son identité.
  Future<IdentiteAppareil> appairer(String nom, List<String> etablissements, {String? titulaireId}) async {
    final qr = await appairage.preparer(
      acteur: await droits(admin),
      nomAppareil: nom,
      titulaireId: titulaireId,
      etablissementIds: etablissements,
      urlServeur: 'http://localhost',
      empreinteCertificat: null,
    );
    final identite = await IdentiteAppareil.generer(qr.appareilId);
    await appairage.finaliser(DemandeAppairage(
        appareilId: qr.appareilId, code: qr.code, clePublique: await identite.clePubliqueBase64()));
    return identite;
  }
}
