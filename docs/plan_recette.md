# SSSU-SAJ VMS — Plan de recette (tests sur le terrain)

Les tests automatiques couvrent la logique : synchronisation à plusieurs téléphones, coupures réseau, conflits, sécurité, sauvegarde et restauration, statistiques. Ils sont dans les dossiers `test` et sont lancés par l'intégration continue. Ce plan vérifie le reste **sur de vrais appareils**, avant la mise en service.

Chaque ligne se coche (OK / KO). Une anomalie se décrit : étape, résultat obtenu, capture.

## Matériel

- 1 poste central Windows, installé avec l'installateur.
- **3 téléphones** au moins :
  - T1 : Android 8 ou 9, 2 Go de RAM (bas de gamme) ;
  - T2 : téléphone récent ;
  - T3 : téléphone récent, affecté à un autre établissement.
- Un Wi-Fi de bureau, puis une connexion mobile (Internet), si la synchronisation par Internet est prévue.
- Le jeu de données réel d'un établissement pilote : listes Excel, CSV, PDF et papier.

## 1. Installation

| N° | Test | Attendu | OK/KO |
| --- | --- | --- | --- |
| 1.1 | Installer le poste sur un PC neuf, en compte administrateur | Fin sans erreur ; service `SSSU-SAJ-PostgreSQL` démarré ; journal d'installation sans « ERREUR » | |
| 1.2 | Premier lancement | Création du compte administrateur proposée ; tableau de bord affiché | |
| 1.3 | Redémarrer le PC, puis lancer l'application | Démarrage sans manipulation ; base disponible | |
| 1.4 | Réinstaller la même version, puis la suivante | Données, comptes et configuration conservés | |
| 1.5 | Installer l'APK sur T1, T2 et T3 | Installation possible ; icône « SSSU-SAJ VMS » | |

## 2. Comptes et appairage

| N° | Test | Attendu | OK/KO |
| --- | --- | --- | --- |
| 2.1 | Créer un compte par profil | Le mot de passe temporaire doit être changé à la première connexion | |
| 2.1 bis | Changer le mot de passe temporaire sur le poste, puis « Synchroniser » depuis l'écran de connexion du téléphone | Connexion sur le téléphone avec le nouveau mot de passe ; l'ancien est refusé | |
| 2.1 ter | Supprimer un compte d'agent (avec motif), puis synchroniser son téléphone | Connexion refusée sur le poste et le téléphone ; ses visites gardent son nom ; l'identifiant peut être recréé ; suppression de son propre compte refusée | |
| 2.2 bis | Enregistrer un téléphone sans QR code (adresse Internet, identifiant, mot de passe temporaire) | Code de sécurité identique sur le téléphone et le poste ; nouveau mot de passe demandé ; téléphone « en attente », rien reçu | |
| 2.2 ter | Accepter ce téléphone sur le poste avec un établissement, puis « Vérifier maintenant » | Le téléphone reçoit les élèves de cet établissement seulement ; connexion avec le nouveau mot de passe | |
| 2.2 quater | Refuser un autre téléphone en attente | Le téléphone affiche « Téléphone refusé » et propose de recommencer | |
| 2.2 quinquies | Supprimer un téléphone appairé, puis le synchroniser | Il disparaît de la liste du poste ; le téléphone affiche « Téléphone bloqué ou retiré », données effacées ; il s'appaire de nouveau | |
| 2.2 sexies | Couper le Wi-Fi du poste juste après la lecture du QR code | Écran « Synchronisation à terminer », puis réception des données dès le retour du réseau, sans nouveau QR code | |
| 2.2 | Appairer T1 et T2 (établissement A) et T3 (établissement B) par QR code | Première synchronisation : T1 et T2 voient uniquement les élèves de A, T3 ceux de B | |
| 2.3 | Réutiliser un QR code déjà servi, ou vieux de plus de 10 minutes | Refusé | |
| 2.4 | 5 mots de passe faux de suite | Compte bloqué 15 minutes | |
| 2.5 | Code PIN : définir, verrouiller, déverrouiller | Déverrouillage par PIN ; verrouillage seul après 5 minutes | |
| 2.6 | L'administrateur ouvre un dossier médical | Impossible (aucun accès médical) | |

## 3. Travail hors ligne (mode avion)

| N° | Test | Attendu | OK/KO |
| --- | --- | --- | --- |
| 3.1 | Connexion en mode avion (après une synchronisation) | Connexion possible | |
| 3.2 | Importer une liste Excel, une liste PDF et la photo d'une liste papier | Lignes lues, à vérifier ; doublons signalés ; rien n'est enregistré avant validation | |
| 3.3 | Saisir 10 visites complètes, avec photos et consentement | Enregistrement automatique ; indicateur « en attente » à 10 | |
| 3.4 | Pendant une saisie : appel entrant, fermeture forcée, batterie retirée | Ébauche retrouvée, saisie conservée à 30 secondes près | |
| 3.5 | Inspection complète avec photos et signature | Taux et niveau corrects (calcul à la main) | |
| 3.6 | Galerie du téléphone, gestionnaire de fichiers, capture d'écran | Aucune photo visible ; capture bloquée | |

## 4. Synchronisation

| N° | Test | Attendu | OK/KO |
| --- | --- | --- | --- |
| 4.1 | Retour au Wi-Fi du bureau | Synchronisation seule en moins d'une minute ; « en attente » à 0 | |
| 4.2 | Sur le poste : visites, photos et inspection visibles | Identiques à la saisie ; photos ouvrables ; copie effacée sur le téléphone | |
| 4.3 | T1 et T2 synchronisent en même temps 50 visites chacun | Tout arrive, sans doublon ni perte (comptage sur le poste) | |
| 4.4 | Couper le Wi-Fi pendant l'envoi d'une photo, puis le rétablir | Le transfert reprend ; la photo arrive entière | |
| 4.5 | Modifier le même élève sur T1 et sur T2 hors ligne, puis synchroniser | Un conflit sur le poste ; aucune saisie perdue ; décision du Médecin-Chef reçue par les deux téléphones | |
| 4.6 | Changer l'adresse IP du poste | Les téléphones le retrouvent sur le Wi-Fi | |
| 4.7 | Par Internet (données mobiles), si configuré | Synchronisation réussie ; journal « canal internet » | |
| 4.8 | Journal des synchronisations | Appareil, agent, date, nombres d'éléments et erreurs justes | |

## 5. Poste central

| N° | Test | Attendu | OK/KO |
| --- | --- | --- | --- |
| 5.1 | Valider une visite, puis la rouvrir avec un motif | Statuts justes ; motif dans le journal d'audit ; visite à nouveau modifiable sur le téléphone de l'agent | |
| 5.2 | Ajouter un critère à la grille d'inspection | Reçu par les téléphones ; inspections passées inchangées | |
| 5.3 | Tableau de bord et statistiques pour un établissement pilote | Égaux aux comptages à la main : effectif, examinés, couverture, cas par pathologie | |
| 5.4 | Chaque rapport, en PDF et en Excel | En-tête et logo ; chiffres égaux à l'écran ; accents corrects ; listes nominatives marquées « secret médical » | |
| 5.5 | Fiche individuelle avec photos | Photos seulement si demandées, et pour un profil autorisé | |
| 5.6 | Recherche « kone » | Trouve « KONÉ » | |
| 5.7 | 5 000 élèves (import de listes réelles ou du jeu de charge) | Écrans et statistiques en moins de 5 secondes | |

## 6. Sécurité

| N° | Test | Attendu | OK/KO |
| --- | --- | --- | --- |
| 6.1 | Bloquer T3 depuis le poste, puis synchroniser T3 | T3 affiche « Téléphone bloqué » et efface ses données ; au relancement, écran d'appairage | |
| 6.2 | Copier `C:\ProgramData\SSSU-SAJ VMS` sur un autre PC | Photos et clés inutilisables (protection DPAPI liée à l'ordinateur) | |
| 6.3 | Ouvrir la base du téléphone (fichier copié par un spécialiste) | Illisible (chiffrement SQLCipher) | |
| 6.4 | Journal d'audit | Connexions, échecs, consultations, exports, sauvegardes tracés ; aucun mot de passe visible | |

## 7. Sauvegarde et restauration (exercice obligatoire)

| N° | Test | Attendu | OK/KO |
| --- | --- | --- | --- |
| 7.1 | Définir la phrase de passe ; sauvegarde manuelle ; « Vérifier » | Sauvegarde intacte (taille, photos) | |
| 7.2 | Laisser le poste allumé après l'heure planifiée | Sauvegarde automatique faite ; tableau de bord vert | |
| 7.3 | Éteindre le poste à l'heure planifiée, le rallumer | Sauvegarde rattrapée dans la minute | |
| 7.4 | Saisir des visites après la sauvegarde, puis restaurer celle-ci | Restauration réussie ; à leur synchronisation, les téléphones renvoient les visites postérieures ; aucune perte | |
| 7.5 | Restaurer sur un **autre PC** neuf, avec la phrase de passe | Données, photos et certificat retrouvés ; les téléphones se synchronisent sans nouvel appairage | |
| 7.6 | Mauvaise phrase de passe ; fichier de sauvegarde modifié | Refus clair, rien n'est modifié | |

## Procès-verbal

| | |
| --- | --- |
| Date et lieu | |
| Version testée (poste / APK) | |
| Participants | |
| Anomalies bloquantes | |
| Anomalies mineures | |
| Décision | Mise en service / correction puis nouvelle recette |
| Signatures | Médecin-Chef — Administrateur — Prestataire |

## Version 1.6.0

| N° | Action | Résultat attendu | OK |
|----|--------|------------------|----|
| 17.1 | Téléphone : élève de CM2 → Nouvelle visite | Formulaire de visite systématique, sans question | |
| 17.2 | Élève de 3ème (puis de Tle D, Tle G2) → Nouvelle visite | Choix « visite systématique » ou « visite d'aptitude » | |
| 17.3 | Visite d'aptitude sans décision, puis « aptitude partielle » sans restrictions | Validation refusée avec le motif | |
| 17.4 | Valider une visite d'aptitude, synchroniser | Poste : dossier et détail affichent le type et la décision | |
| 17.5 | Poste : Statistiques → Visite d'aptitude | Effectif = élèves de 3ème et Tle ; décisions d'aptitude ; visites systématiques non comptées | |
| 17.6 | Statistiques → Visite systématique | Les visites d'aptitude ne sont pas comptées | |
| 17.7 | Couverture : tableau par tranche d'âge et par sexe | 0–4 … 50 ans et plus ; total = effectif | |
| 17.8 | Rapports → Décisions d'aptitude (PDF) | Liste nominative avec décision et restrictions | |
| 17.9 | Téléphone resté en 1.5 qui synchronise après une visite d'aptitude | Message « installez la dernière version », données du téléphone conservées | |

## Version 1.5.0

| N° | Action | Résultat attendu | OK |
|----|--------|------------------|----|
| 16.1 | Menu « Listes de classe », taper une partie du nom d'un établissement | L'établissement est proposé ; ses classes s'affichent dans l'ordre scolaire avec l'effectif G/F | |
| 16.2 | Cliquer une classe, puis un élève | Liste de la classe ; le dossier de l'élève s'ouvre | |
| 16.3 | « Ajouter un élève » | Élève inscrit dans la classe affichée, effectif mis à jour | |
| 16.4 | Imprimer / exporter → Toutes les classes → PDF | Une page par classe, classes vides signalées | |
| 16.5 | Imprimer / exporter → Toutes les classes → Excel, puis réimporter le fichier | Une feuille par classe ; à la réimportation, les élèves sont reconnus comme déjà enregistrés | |
| 16.6 | Compte agent de santé | Listes visibles ; pas d'« Imprimer / exporter » ni d'« Ajouter un élève » | |

## Version 1.4.0

| N° | Action | Résultat attendu | OK |
|----|--------|------------------|----|
| 15.1 | Établissements : nouvelle classe, taper « tle » | Tle A1, A2, C, D puis séries techniques proposées | |
| 15.2 | Importer un classeur avec des feuilles « 2nde C », « Tle D », « 1ère A1 » | Trois classes reconnues et rapprochées | |
| 15.3 | Poste : Élèves et dossiers → Nouvel élève (sans sexe, puis date 31/02/2014) | Messages « Indiquez le sexe », « Date de naissance illisible » | |
| 15.4 | Nouvel élève identique à un élève existant | « Cet élève semble déjà enregistré » ; « Ouvrir son dossier » ouvre le dossier existant | |
| 15.5 | Dossier : Modifier (prénoms, téléphone), puis matricule d'un autre élève | Enregistré ; puis refus « Le matricule … est déjà celui de … » | |
| 15.6 | Dossier : Changer de classe vers un autre établissement | Classe changée ; dossier reçu par les téléphones du nouvel établissement | |
| 15.7 | Téléphone (infirmier) : classe → Ajouter un élève, synchroniser | Élève visible sur le poste dans la bonne classe | |
| 15.8 | Téléphone : dossier → crayon → corriger le nom, synchroniser | Nom corrigé sur le poste | |
| 15.9 | Téléphone (agent de santé) | Ni « Ajouter un élève » ni crayon | |

## Version 1.3.0

| N° | Action | Résultat attendu | OK |
|----|--------|------------------|----|
| 14.1 | Établissements : nouvelle classe, taper « 2nd g » | 2nde G, 2nde G1, 2nde G2 proposées ; niveau vide → « 2NDE » enregistré | |
| 14.2 | Créer « 2nd G1 » alors que « 2nde G1 » existe | Refus : « Cette classe existe déjà… (« 2nde G1 ») » | |
| 14.3 | Importer : « Modèle Excel (plusieurs classes) », remplir deux feuilles renommées « 2nde G1 » et « Tle F2 » | Deux classes listées ; feuilles « Explications » et vides ignorées | |
| 14.4 | Classe de destination absente pour « Tle F2 » | Bouton « Créer la classe manquante » ; classe créée et choisie | |
| 14.5 | Décocher une classe, valider | Seules les classes cochées sont importées ; une fois validé, tout est enregistré | |
| 14.6 | Fichier d'une seule feuille avec une colonne « Classe » (2nd G1, 2nde G2, cellules fusionnées) | Élèves répartis en deux classes ; lignes d'origine affichées | |
| 14.7 | Même élève dans deux feuilles | Doublon signalé avec la classe : « Doublon de la ligne 3 de « 2nde G1 » » | |
| 14.8 | Téléphone : importer le même classeur | Choix de la classe du fichier ; après validation, « Classe suivante du fichier » | |

## Version 1.2.3

| N° | Action | Résultat attendu | OK |
|----|--------|------------------|----|
| 13.1 | Mettre à jour un poste déjà installé avec l'installateur 1.2.3 | Aucune fenêtre de Tesseract (ni installation, ni désinstallation) ; `C:\Program Files\SSSU-SAJ VMS\tesseract\tesseract.exe` présent | |
| 13.2 | Importer une liste d'élèves en PDF scanné | Lignes lues par OCR, sans « Échec de Tesseract » | |
| 13.3 | Importer une photo d'une liste d'élèves, puis une photo de la liste des établissements | Lignes proposées, à vérifier avant validation | |

## Version 1.2.0

| N° | Action | Résultat attendu | OK |
|----|--------|------------------|----|
| 12.1 | Nouvelle inspection sur le téléphone | Grille B à J (118 critères, ★ en rouge), identification et section A préremplies (effectifs, classes) | |
| 12.2 | Section A : « Pas de cantine », préscolaire, sans électricité | H1–H10, E1–E9 et G8 cotés NA avec le motif | |
| 12.3 | Coter tout C sauf un critère ★ en NC | Score > 99 %, classement « Insuffisant » (plafonné), conduite à tenir affichée | |
| 12.4 | « Depuis les NC », date de contre-visite, signature, transmettre | Problèmes prioritaires proposés ; inspection transmise | |
| 12.5 | Poste : détail de l'inspection, Rapport Word et PDF | Grille remplie au format du document ; cases ☒ ; récapitulatif 118 critères ; deux signatures | |
| 12.6 | Rapports : synthèse des inspections | Tableau par établissement : scores B à J, global, classement, ★ NC | |
| 12.7 | Importer une liste d'élèves sans choisir la classe (titre « EPP … – CLASSE DE CM2 A ») | Établissement et classe proposés ; classe absente : bouton « Créer la classe » | |
| 12.8 | Établissements : Importer une liste (modèle Excel rempli) | Créations et mises à jour proposées, doublons ignorés, codes proposés si absents | |
| 12.9 | Mettre à jour un téléphone en 1.1.x puis synchroniser | Ancienne grille désactivée, nouvelle grille reçue, inspections anciennes lisibles | |
