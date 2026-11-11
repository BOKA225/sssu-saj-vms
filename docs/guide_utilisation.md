# SSSU-SAJ VMS — Guide d'utilisation

Ce guide s'adresse au personnel du SSSU-SAJ. La partie A concerne les équipes de terrain (téléphone), la partie B le poste central du service (Windows).

Quelques règles valent partout :

- Les données sont **médicales et concernent des mineurs**. Elles sont couvertes par le secret médical et par la loi n° 2013-450 relative à la protection des données à caractère personnel. Ne prêtez pas votre compte et ne communiquez pas votre mot de passe ni votre code PIN.
- L'application se **verrouille seule** après quelques minutes sans activité. Vous la déverrouillez avec votre code PIN.
- Chaque action est enregistrée dans un journal : qui, quoi, quand.

---

## A. Application des téléphones

### A1. Première connexion

1. L'administrateur appaire le téléphone : vous lisez avec l'application le QR code affiché sur le poste central.
2. Connectez-vous avec l'identifiant et le mot de passe que l'administrateur vous a remis. Choisissez un **code PIN** de 6 chiffres, ni identiques, ni à la suite.
3. La connexion fonctionne **sans réseau**, dès que le téléphone a été synchronisé une fois.

### A2. Écran d'accueil

L'écran d'accueil montre :

- le nombre d'éléments **en attente** de synchronisation, **synchronisés** et **en ébauche** ;
- l'état de la connexion au poste central ;
- les menus : Établissements et élèves, Rechercher un élève, Ébauches, Inspection sanitaire, Statistiques, Importer une liste, et « Éléments à vérifier » s'il y en a.

Le bouton **SYNCHRONISER MES DONNÉES** envoie vos saisies au poste central et reçoit les nouveautés. La synchronisation se fait aussi **toute seule** quand le réseau revient, et toutes les 15 minutes tant que l'application est ouverte.

- **Au bureau** : le téléphone trouve le poste sur le Wi-Fi.
- **Sur le terrain** : il passe par Internet, si le service l'a configuré.

### A3. Élèves et listes

- **Établissements et élèves** : classes, effectifs, élèves examinés ou non.
- **Rechercher** : par nom, prénoms ou matricule.
- **Importer une liste** : choisissez un fichier Excel, CSV ou PDF, ou photographiez une liste papier. L'application lit le texte, même sans réseau. **Vérifiez chaque ligne** avant de valider : rien n'est enregistré avant votre validation, et les doublons probables vous sont signalés.

### A4. Visite médicale

1. Ouvrez l'élève, puis touchez « Nouvelle visite ».
2. Remplissez les rubriques A à F : identification, antécédents, examen clinique, examen physique (l'IMC est calculé), dépistage, conclusion.
3. Le dossier est **enregistré automatiquement** toutes les 30 secondes et à chaque changement de rubrique. Rien n'est perdu en cas d'appel, de batterie vide ou de fermeture.
4. **Valider et synchroniser** met la visite en attente d'envoi. Les contrôles signalent ce qui manque : conclusion, diagnostic, structure de référence…
5. Une visite commencée et non terminée reste dans **Ébauches**.

### A5. Photographies cliniques

- Une photographie exige le **consentement** du parent ou du tuteur : nom, lien de parenté, forme écrite ou orale. Il est noté dans la visite.
- Les photos sont chiffrées et n'apparaissent **jamais** dans la galerie du téléphone. Les captures d'écran de l'application sont bloquées.
- Une fois la photo transférée et vérifiée par le poste central, le téléphone efface sa copie et affiche « Transférée au poste central ».

### A6. Éléments à vérifier

Le poste central peut refuser une saisie, ou en mettre une en conflit avec une autre. Par exemple, le même dossier a été modifié par deux téléphones. L'écran **Éléments à vérifier** indique le motif.

- Le Médecin-Chef décide sur le poste ; sa décision arrive à la synchronisation suivante.
- Un élément **jamais accepté** par le poste peut être abandonné (« Abandonner ma version »).

### A7. Inspection sanitaire

1. **Inspection sanitaire** : choisissez l'établissement, puis « Nouvelle inspection ».
2. Pour chaque critère, choisissez **Conforme**, **Partiellement conforme**, **Non conforme** ou **Non applicable**.
   - Ajoutez une observation.
   - Pour une insuffisance, ajoutez une photo, sans aucune personne reconnaissable.
3. Le taux de conformité et le niveau (satisfaisant, moyen, insuffisant) s'affichent en direct.
4. Saisissez les observations et les recommandations, puis signez avec le doigt (« Signer »).
5. **ENREGISTRER ET TRANSMETTRE** n'est possible que si tous les critères ont une réponse et que l'inspection est signée. Une fois transmise, l'inspection n'est plus modifiable.

### A8. Statistiques

Les statistiques sont réservées aux médecins et au Médecin-Chef. Elles ne portent que sur les données de **ce téléphone** : couverture, conclusions, pathologies, inspections. Les statistiques complètes sont sur le poste central.

### A9. Téléphone perdu ou volé

Prévenez immédiatement l'administrateur : il **bloque** le téléphone depuis le poste. À sa prochaine connexion, le téléphone **efface toutes les données SSSU-SAJ** qu'il contient : dossiers, photos, clés.

---

## B. Poste central (Windows)

### B1. Connexion et menu

Connectez-vous avec votre identifiant et votre mot de passe. Le menu de gauche dépend de votre profil :

| Profil | Accès principaux |
| --- | --- |
| Administrateur | Comptes, téléphones, établissements, importation, paramètres, sauvegardes, journaux, statistiques sans données nominatives. **Aucun accès aux dossiers médicaux.** |
| Médecin-Chef | Dossiers, validation, réouverture, conflits, statistiques, rapports, inspections, paramètres |
| Médecin | Dossiers, validation, statistiques, rapports |
| Infirmier, agent de santé | Saisie (surtout sur téléphone), inspections |

### B2. Tableau de bord

Le tableau de bord présente :

- l'état du serveur de synchronisation, de la recherche Wi-Fi et de la dernière sauvegarde (en rouge si elle a plus de 36 heures) ;
- les téléphones et les conflits ;
- les indicateurs de l'année : établissements, classes, effectifs, garçons et filles, élèves examinés et non examinés, visites, établissements inspectés, taux de couverture ;
- trois graphiques.

Les filtres portent sur l'année, l'établissement, la classe et le sexe. Les chiffres se mettent à jour d'eux-mêmes après chaque synchronisation.

### B3. Comptes et téléphones (administrateur)

- **Comptes**
  - Créer un compte : le mot de passe donné est temporaire et doit être changé à la première connexion.
    Ce changement se fait **sur le poste central** : l'agent s'y connecte une fois avec le mot de passe
    temporaire et choisit son mot de passe. Sur le téléphone, il touche ensuite **« Synchroniser avec le
    poste central »** sur l'écran de connexion (aucune connexion préalable n'est nécessaire), puis se
    connecte avec son nouveau mot de passe. Même démarche après une réinitialisation du mot de passe.
  - Désactiver un compte, réinitialiser un mot de passe, changer un rôle.
- **Téléphones**
  - Appairer un téléphone (QR code).
  - Choisir les établissements dont il s'occupe : un établissement ajouté lui est envoyé en entier.
  - **Bloquer** un téléphone perdu ou volé.

### B4. Établissements, élèves et dossiers

- **Établissements**
  - Gérer les années scolaires, puis activer celle de l'année en cours.
  - Créer et modifier les établissements et les classes, avec leur effectif et leur couverture.
- **Élèves et dossiers**
  - Rechercher un élève. La recherche ignore les accents : « kone » trouve « KONÉ ».
  - Consulter son dossier.
  - **Valider** une visite, ou la **rouvrir** avec un motif.
  - Voir la galerie photographique.
  - **Fiche individuelle** : éditer la fiche PDF. Les photos n'y sont intégrées que si vous le demandez.
- **Importer une liste** : mêmes formats et mêmes contrôles que sur le téléphone.

### B5. Conflits

La page **Conflits** affiche, champ par champ, la version du poste et celle du téléphone. Les décisions possibles dépendent du cas :

- garder l'une des deux versions, ou composer une version champ par champ ;
- **fusionner** deux dossiers d'un même élève ;
- archiver l'une de deux visites faites le même jour ;
- clore le conflit.

La décision est transmise aux téléphones à leur synchronisation suivante.

### B6. Statistiques et rapports

- **Statistiques** : quatre onglets.
  - Couverture : par sexe, par établissement, par classe.
  - Pathologies : cas, sexe, tranches d'âge, prévalence.
  - Inspections : établissements inspectés, niveaux, principales insuffisances.
  - Évolution mensuelle.

  Les filtres portent sur l'année, l'établissement, la classe, le sexe et la période.
- **Rapports**, en **PDF ou Excel** :
  - rapport annuel, par établissement, par classe ;
  - pathologies ;
  - synthèse des inspections ;
  - listes des élèves examinés et non examinés ;
  - élèves référés et à suivre.

  Les listes nominatives portent la mention « secret médical », et leur édition est tracée.
- L'en-tête, le logo et le nom du Médecin-Chef se règlent dans **Paramètres**.

### B7. Inspections

- **Historique** : les inspections reçues des téléphones. Le détail montre la grille, les photos et la signature. Vous pouvez éditer le rapport en PDF ou en Excel.
- **Grille d'inspection** : ajouter, renommer ou retirer des critères. Les inspections passées gardent leurs réponses.

### B8. Sauvegardes et restauration (administrateur)

- **Sauvegarde**
  - Elle se fait automatiquement chaque jour à l'heure choisie, et elle est rattrapée au démarrage si le poste était éteint.
  - Les 14 dernières sont gardées.
  - Le bouton « Sauvegarder maintenant » en fait une à tout moment.
- **Vérifier** : contrôle une sauvegarde de bout en bout. Faites-le chaque mois.
- **Emportez régulièrement une copie** du dossier des sauvegardes hors du bureau.
- **Restaurer** : en cas de panne, de PC remplacé ou d'erreur grave.
  1. Installez l'application sur le nouveau PC.
  2. Ouvrez Sauvegardes > « Restaurer depuis un autre fichier… », puis saisissez la phrase de passe.
  3. Une sauvegarde de sécurité de l'état actuel est faite d'abord, puis la base est remplacée. L'application se ferme : relancez-la.
  4. Les téléphones **renvoient d'eux-mêmes** leurs données plus récentes que la sauvegarde. Ceux qui ont été appairés après la date de la sauvegarde doivent être appairés de nouveau ; ils gardent leurs données.

### B9. Journaux

- **Synchronisations** : chaque envoi des téléphones, avec l'appareil, l'agent, la date, le nombre d'éléments et les erreurs.
- **Journal d'audit** : connexions, consultations de dossiers et de photos, modifications, exports, sauvegardes, restaurations.
