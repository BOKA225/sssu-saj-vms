# SSSU-SAJ VMS — Guide d'utilisation

Ce guide s'adresse au personnel du SSSU-SAJ. La partie A concerne les équipes de terrain (téléphone), la partie B le poste central du service (Windows).

Quelques règles valent partout :

- Les données sont **médicales et concernent des mineurs**. Elles sont couvertes par le secret médical et par la loi n° 2013-450 relative à la protection des données à caractère personnel. Ne prêtez pas votre compte et ne communiquez pas votre mot de passe ni votre code PIN.
- L'application se **verrouille seule** après quelques minutes sans activité. Vous la déverrouillez avec votre code PIN.
- Chaque action est enregistrée dans un journal : qui, quoi, quand.

---

## A. Application des téléphones

### A1. Première connexion

1. Enregistrez le téléphone, de l'une de ces deux façons :
   - **avec un QR code**, au bureau : l'administrateur l'affiche sur le poste central, vous le lisez avec
     l'application (même Wi-Fi que le poste) ;
   - **sans QR code**, de n'importe où : touchez **« Pas de QR code : m'enregistrer avec mon identifiant »**,
     saisissez l'adresse du poste donnée par l'administrateur (par exemple `https://sssu-saj.ddns.net:8443`
     par Internet, ou `https://192.168.1.10:8443` sur le Wi-Fi du poste), un nom pour le téléphone, votre
     identifiant et votre mot de passe. L'application affiche le **code de sécurité du poste** : il doit
     être identique à celui de la page Téléphones du poste central (en cas de doute, appelez
     l'administrateur). Si votre mot de passe est temporaire, choisissez ici votre mot de passe personnel.
     Le téléphone attend ensuite que l'administrateur l'**accepte** ; il vérifie tout seul chaque minute,
     ou touchez « Vérifier maintenant ». Une fois accepté, il reçoit les élèves de ses établissements.
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
- **Ajouter un élève** absent de la liste : ouvrez sa classe, puis **« Ajouter un élève »** (nom, prénoms, sexe, date de naissance, matricule, téléphone du parent). Si un élève semblable existe déjà (même matricule, ou mêmes nom, prénoms et date de naissance), l'application le signale et propose d'ouvrir son dossier.
- **Modifier le dossier** d'un élève : dans son dossier, touchez le crayon en haut de l'écran. Les changements partent au poste central à la prochaine synchronisation.
- Ces deux actions sont réservées au médecin-chef, au médecin et à l'infirmier (pas à l'agent de santé).
- **Importer une liste** : choisissez un fichier Excel, CSV ou PDF, ou photographiez une liste papier. L'application lit le texte, même sans réseau. **Vérifiez chaque ligne** avant de valider : rien n'est enregistré avant votre validation, et les doublons probables vous sont signalés. Un classeur Excel de **plusieurs classes** (une feuille par classe, ou une colonne « Classe ») s'importe classe par classe : choisissez la classe du fichier, validez, puis touchez **« Classe suivante du fichier »**. Le poste central, lui, importe toutes les classes en une fois.

### A4. Visite médicale

1. Ouvrez l'élève, puis touchez « Nouvelle visite ». Pour un élève de **3ème** ou de **terminale** (enseignement général ou technique), l'application demande quelle visite faire :
   - **visite médicale systématique** : le bilan de santé de tous les élèves ;
   - **visite médicale d'aptitude** : l'aptitude à la pratique de l'EPS et aux examens (BEPC, BAC).
2. Remplissez les rubriques A à F : identification, antécédents, examen clinique, examen physique (l'IMC est calculé), dépistage, conclusion. Pour une visite d'aptitude, la rubrique F commence par la **décision d'aptitude** : apte, aptitude partielle (avec restrictions), inapte temporairement ou inapte définitivement. Sauf pour « apte », précisez les restrictions ou le motif et la durée de l'inaptitude.
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

L'inspection suit la **grille d'inspection sanitaire des établissements scolaires** du SSSU-SAJ (normes MENA 2022
et OMS) : 118 critères en neuf sections (B à J), dont 7 critères critiques ★.

1. **Inspection sanitaire** : choisissez l'établissement, puis « Nouvelle inspection ». La grille est
   préremplie avec ce que l'application connaît : localité, chef d'établissement, ordre d'enseignement,
   élèves inscrits (garçons et filles), nombre de classes, date de la dernière inspection.
2. **Identification de la visite** : DRENA/IEPP, aire sanitaire, accompagnateur, heures, type de visite
   (programmée, inopinée, contre-visite), équipe.
3. **A. Structure et effectifs** (non coté) : ordre d'enseignement, statut, fréquentation, régime, milieu,
   électricité, cantine ; effectifs ; inventaire des équipements (existant et fonctionnel). Les **ratios** se
   calculent seuls ; une valeur hors norme s'affiche en rouge. Les critères qui ne s'appliquent pas sont cotés
   NA automatiquement, avec le motif : section E pour le préscolaire ou sans filles, H1 à H10 sans cantine,
   G8 sans électricité.
4. **Sections B à J** : pour chaque critère, **C** (conforme), **NC** (non conforme) ou **NA** (non
   applicable, à justifier en observation). Notez les chiffres utiles en observation et photographiez les
   insuffisances, sans personne reconnaissable. Le score de chaque section s'affiche dans son titre.
5. En haut de l'écran : **score global**, **classement** (Satisfaisant ≥ 80 %, Acceptable 60–79 %, Insuffisant
   40–59 %, Critique < 40 %) et conduite à tenir. Un seul critère ★ non conforme plafonne le classement à
   « Insuffisant ».
6. **Niveau de service** eau, assainissement et hygiène : proposé d'après les cotations, modifiable.
7. **Constats** : points forts ; **problèmes prioritaires** (le bouton « Depuis les NC » les propose à
   partir des critères non conformes, critiques d'abord), avec mesure, responsable et délai ; date de la
   contre-visite ; chef de l'équipe.
8. Signez avec le doigt, puis **ENREGISTRER ET TRANSMETTRE**. Tous les critères doivent être cotés. Une fois
   transmise, l'inspection n'est plus modifiable.

Le rapport à imprimer (grille remplie, signature et cachet du chef d'établissement) s'édite sur le poste central.

### A8. Statistiques

Les statistiques sont réservées aux médecins et au Médecin-Chef. Elles ne portent que sur les données de **ce téléphone** : couverture, conclusions, pathologies, inspections, élèves par tranche d'âge et par sexe. Choisissez en haut **Systématique** ou **Aptitude** : les deux visites ont des statistiques séparées (la visite d'aptitude porte sur les élèves de 3ème et de terminale, avec leurs décisions d'aptitude). Les statistiques complètes sont sur le poste central.

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

Les filtres portent sur le **type de visite** (systématique ou d'aptitude), l'année, l'établissement, la classe et le sexe. Les chiffres se mettent à jour d'eux-mêmes après chaque synchronisation.

### B3. Comptes et téléphones (administrateur)

- **Comptes**
  - Créer un compte : le mot de passe donné est temporaire et doit être changé à la première connexion.
    Ce changement se fait **sur le poste central** : l'agent s'y connecte une fois avec le mot de passe
    temporaire et choisit son mot de passe. Sur le téléphone, il touche ensuite **« Synchroniser avec le
    poste central »** sur l'écran de connexion (aucune connexion préalable n'est nécessaire), puis se
    connecte avec son nouveau mot de passe. Même démarche après une réinitialisation du mot de passe.
  - Supprimer un compte (menu de la ligne, **« Supprimer le compte »**, motif obligatoire) : le compte
    ne peut plus se connecter, ni sur le poste ni sur les téléphones après leur synchronisation (un agent
    connecté sur un téléphone est déconnecté). Ses visites, inspections et le journal d'audit gardent son
    nom, et son identifiant peut être réutilisé. La suppression est définitive ; pour une absence
    temporaire, utilisez **« Désactiver le compte »**. On ne peut supprimer ni son propre compte, ni le
    dernier administrateur actif.
  - Désactiver un compte, réinitialiser un mot de passe, changer un rôle.
- **Téléphones**
  - Appairer un téléphone (QR code).
  - Téléphones **en attente** (enregistrés par un agent sans QR code) : en haut de la liste, avec le nom de
    l'agent. **Accepter** demande de choisir ses établissements ; **Refuser** l'écarte définitivement. Le
    code de sécurité du poste est affiché en haut de la page : l'agent voit le même sur son téléphone.
    N'acceptez que les téléphones que vous attendiez.
  - Choisir les établissements dont il s'occupe : un établissement ajouté lui est envoyé en entier.
  - **Bloquer** un téléphone perdu ou volé.
  - **Supprimer** un téléphone (icône corbeille) : il disparaît de la liste et, à son prochain contact
    avec le poste, ses données sont effacées (les visites non encore envoyées sont perdues : synchronisez-le
    d'abord si possible). Il peut ensuite être appairé de nouveau. Utile pour un téléphone remplacé, ou
    dont l'appairage n'a pas abouti.
  - Si la première synchronisation d'un téléphone échoue juste après le QR code, il n'est plus nécessaire
    de recommencer l'appairage : le téléphone réessaie tout seul (écran « Synchronisation à terminer »).

### B4. Établissements, élèves et dossiers

- **Établissements**
  - Gérer les années scolaires, puis activer celle de l'année en cours.
  - Créer et modifier les établissements et les classes, avec leur effectif et leur couverture. En tapant le
    libellé d'une classe, les classes usuelles sont proposées : **enseignement général** (6ème…3ème, 2nde A,
    2nde C, 1ère et Tle A1, A2, C, D) et **enseignement technique** (2nde G, 2nde G1, 1ère F3, Tle G2, BT 1,
    CAP 1…). Le niveau, s'il est laissé vide, est déduit du libellé.
    « 2nd G1 » et « 2nde G1 » désignent la même classe : un doublon est refusé.
- **Élèves et dossiers**
  - Rechercher un élève. La recherche ignore les accents : « kone » trouve « KONÉ ».
- **Listes de classe** (menu) : choisissez l'année et l'établissement (tapez une partie de son nom pour le
  trouver). Les classes apparaissent dans l'ordre scolaire (CP1… CM2, 6ème… Tle, puis BT, CAP) avec leur effectif
  (garçons, filles) ; cliquez une classe pour voir sa liste : matricule, nom et prénoms, sexe, date de naissance,
  âge, téléphone du parent, dernière visite. Cliquez un élève pour ouvrir son dossier ; **« Ajouter un élève »**
  l'inscrit directement dans la classe affichée.
  - **Imprimer / exporter** : la classe affichée ou toutes les classes, en PDF (une page par classe, à
    imprimer), en Word, ou en Excel. Le fichier Excel de toutes les classes contient une feuille par classe,
    aux colonnes du modèle d'importation : il peut être complété puis réimporté.
  - Les listes exportées ne contiennent que l'identité des élèves (aucune donnée médicale) ; chaque export est
    noté dans le journal d'audit.
  - **Nouvel élève** : identité, établissement et classe de l'année. Un élève semblable déjà enregistré est
    signalé, avec la possibilité d'ouvrir son dossier plutôt que d'en créer un second.
  - Consulter son dossier. **Modifier** son identité (nom, prénoms, sexe, date de naissance, matricule,
    téléphone du parent) ; **Changer de classe** pour l'année en cours (le dossier suit l'élève dans son nouvel
    établissement) ; **Inscrire** un élève qui n'a pas encore de classe cette année. Un matricule ne peut
    appartenir qu'à un seul élève.
  - **Valider** une visite, ou la **rouvrir** avec un motif.
  - Voir la galerie photographique.
  - **Fiche individuelle** : éditer la fiche PDF. Les photos n'y sont intégrées que si vous le demandez.
- **Importer une liste** : mêmes formats et mêmes contrôles que sur le téléphone. Choisissez directement le
  fichier : l'**établissement et la classe sont proposés** d'après le titre de la liste (« EPP KOUASSIKRO 1 –
  CLASSE DE CM2 A ») et le nom du fichier. Si la classe n'existe pas encore, un bouton propose de la créer.
  Vérifiez toujours la proposition avant de valider.
- **Plusieurs classes dans un même fichier Excel**, de deux façons (le bouton **« Modèle Excel (plusieurs
  classes) »** fournit un classeur prêt à remplir) :
  - **une feuille par classe**, nommée comme la classe (« CM2 A », « 2nde G1 », « Tle F2 ») ; les feuilles
    d'explications ou vides sont ignorées. Une feuille au nom par défaut (« Feuil1 ») est rattachée à la classe
    écrite dans son titre ;
  - **une colonne « Classe »** dans une seule feuille : les élèves sont répartis selon la classe indiquée sur
    chaque ligne (une cellule vide reprend la classe de la ligne du dessus).

  Après l'analyse, un tableau montre chaque classe du fichier, son nombre d'élèves et la **classe de
  destination** proposée dans l'établissement choisi. Corrigez-la si besoin, décochez une classe à ne pas
  importer, ou créez en un clic les classes qui manquent. La validation importe toutes les classes en une seule
  fois : tout est enregistré, ou rien. Un élève présent dans deux classes du fichier est signalé comme doublon.
- **Établissements** : **Importer une liste** (Excel, CSV, PDF texte ou scanné, ou photo d'une liste papier :
  code, nom, type, statut, région, district,
  localité, responsable, téléphone ; un **modèle Excel** est proposé). Chaque ligne est comparée aux
  établissements connus (même code ou même nom) : création ou mise à jour, à vérifier avant de valider. La
  même importation est possible depuis **Paramètres**, où la liste des établissements (code, nom,
  responsable, statut) se consulte et se modifie.

### B5. Conflits

La page **Conflits** affiche, champ par champ, la version du poste et celle du téléphone. Les décisions possibles dépendent du cas :

- garder l'une des deux versions, ou composer une version champ par champ ;
- **fusionner** deux dossiers d'un même élève ;
- archiver l'une de deux visites faites le même jour ;
- clore le conflit.

La décision est transmise aux téléphones à leur synchronisation suivante.

### B6. Statistiques et rapports

- **Statistiques** : quatre onglets, pour la **visite systématique** ou la **visite d'aptitude** (bouton en haut
  à gauche) : les deux visites sont comptées séparément. La visite d'aptitude porte sur les élèves de 3ème et de
  terminale et ajoute la répartition des décisions (apte, aptitude partielle, inapte).
  - Couverture : par sexe, par établissement, par classe, et **par tranche d'âge et par sexe** (0–4, 5–9, 10–14,
    15–19, 20–24, 25–49 ans, 50 ans et plus ; âge de chaque élève au jour de la consultation, ou à la fin de
    l'année scolaire si elle est terminée).
  - Pathologies : cas, sexe, tranches d'âge, prévalence.
  - Inspections : établissements inspectés, niveaux, principales insuffisances.
  - Évolution mensuelle.

  Les filtres portent sur le type de visite, l'année, l'établissement, la classe, le sexe et la période.
- **Rapports**, en **PDF, Word ou Excel**, pour le type de visite choisi :
  - rapport annuel, par établissement, par classe (avec le tableau par tranche d'âge et par sexe, et pour la
    visite d'aptitude, les décisions d'aptitude) ;
  - pathologies ;
  - synthèse des inspections (avec, pour la grille nationale, les scores par section, le classement et les
    critères ★ non conformes de chaque établissement) ;
  - listes des élèves examinés et non examinés ;
  - élèves référés et à suivre ;
  - **décisions d'aptitude (3ème et Tle)** : liste nominative des élèves vus, avec leur décision et les
    restrictions, à transmettre pour les examens.

  Les listes nominatives portent la mention « secret médical », et leur édition est tracée.
- L'en-tête, le logo et le nom du Médecin-Chef se règlent dans **Paramètres**.

### B7. Inspections

- **Historique** : les inspections reçues des téléphones, avec score et classement. Le détail montre les scores
  par section, les critères ★ non conformes, la grille, les photos et la signature.
- **Rapport Word ou PDF** : la grille remplie au format du document officiel (identification, structure et
  effectifs, ratios, sections B à J cochées, récapitulatif des scores, niveaux de service, classement, plan
  d'action, signatures, ampliation). Le **Word** se modifie avant impression ; imprimez-le pour la signature
  et le cachet du chef d'établissement (« lu et approuvé »).
- **Grille d'inspection** : la grille nationale (B à J) ; ajouter, renommer ou retirer des critères. Les
  critères de l'ancienne grille sont désactivés depuis la version 1.2.0 (réactivables) ; les inspections
  passées gardent leurs réponses.

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
