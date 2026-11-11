# SSSU-SAJ VMS — Phases 1 à 6

Gestion des visites médicales scolaires et universitaires — District sanitaire de Kouassi-Kouassikro.
- **Phase 1 (conception)** : structure du dépôt, schémas SQL, modèles et règles métier, comptes et droits,
  écran de connexion, serveur de synchronisation minimal.
- **Phase 2 (version mobile)** : établissements, classes et effectifs, recherche d'élèves, importation des
  listes (Excel, CSV, PDF, PDF scannés et photos de listes avec OCR hors ligne), formulaire complet de
  visite (rubriques A à F), photographies cliniques chiffrées, ébauches et sauvegarde automatique.
  Voir la section « Phase 2 » plus bas.
- **Phase 3 (poste central Windows)** : gestion des années scolaires, établissements et classes, élèves et
  dossiers médicaux, validation et réouverture des visites, galerie photographique sécurisée, importation des
  listes sur le poste (OCR Tesseract), affectation des téléphones, comptes, journaux de synchronisation et
  d'audit. Voir la section « Phase 3 » plus bas.
- **Phase 4 (synchronisation)** : Wi-Fi local et Internet, conflits, transfert des photographies.
- **Phase 5 (statistiques et rapports)** : tableaux de bord, indicateurs, rapports PDF et Excel, inspection sanitaire.
- **Phase 6 (tests et livraison)** : sauvegarde et restauration, reprise des téléphones après restauration,
  protection DPAPI, effacement à distance, mises à jour automatiques du schéma, installateurs, intégration
  continue, documentation (`docs/`). Voir la section « Phase 6 » plus bas.

**Documentation** :

- `docs/guide_installation.md` — installation ;
- `docs/guide_utilisation.md` — utilisation ;
- `docs/documentation_technique.md` — technique ;
- `docs/plan_recette.md` — essais sur le terrain.

## État de vérification (à lire en premier)

| Élément | Vérifié ? |
| --- | --- |
| Schéma SQLite (`tables.drift`) | Chargé sans erreur dans SQLite 3.53, clés étrangères actives |
| Schéma PostgreSQL (`001_schema.sql`) | Chargé sans erreur dans PostgreSQL 16 |
| Jeu de données de test | Chargé dans les deux bases (120 élèves, 0 erreur de clé étrangère) |
| Contraintes | Testées dans les deux bases : photo sans consentement refusée, double inscription refusée, matricule unique sur le téléphone, contrôles CHECK |
| Requêtes du dépôt PostgreSQL | Formes SQL (conversions, tableaux, upsert, `FOR UPDATE`) testées dans PostgreSQL 16 |
| Code Dart / Flutter | **Écrit mais non compilé ni exécuté** : Dart et Flutter n'étaient pas disponibles dans l'environnement de rédaction. Lancer les commandes ci-dessous ; signaler toute erreur de compilation pour correction. |

## Structure du dépôt

```
sssu-saj-vms/
├── sssu_core/            Paquet Dart commun (aucune dépendance Flutter)
│   ├── lib/src/commun/       Identifiants UUID v7, horloge, dates
│   ├── lib/src/schema/       Registre des tables (généré) — référence de la synchronisation
│   ├── lib/src/modeles/      Énumérations et modèles (Élève, Visite, Utilisateur…)
│   ├── lib/src/regles/       Âge, IMC (OMS), constantes, conformité des inspections, doublons
│   ├── lib/src/auth/         Argon2id, rôles et permissions, connexion, verrouillage, PIN
│   ├── lib/src/sync/         Protocole, conflits, appairage, jetons, API REST, client, dépôts
│   └── test/                 Tests unitaires + test « deux téléphones » en HTTP réel
├── sssu_mobile/          Application Android (Flutter)
│   ├── lib/data/             Base SQLCipher (drift), dépôt local de synchronisation, comptes
│   ├── lib/securite/         Stockage sécurisé (Android Keystore)
│   ├── lib/ui/               Appairage (QR), connexion (mot de passe / PIN), accueil + synchronisation
│   ├── plateforme_android/   MainActivity (FLAG_SECURE) et extraits de manifeste
│   └── test/                 Schéma, contraintes, synchronisation de la vraie base SQLite
├── sssu_windows/         Poste central (Flutter Desktop)
│   ├── lib/donnees/          Dépôt PostgreSQL
│   ├── lib/serveur/          Certificat TLS auto-signé
│   ├── lib/ui/               Premier administrateur, connexion, tableau de bord, téléphones, comptes
│   └── test/                 Dépôt PostgreSQL (si une base de test est fournie)
├── sql/
│   ├── postgres/001_schema.sql                  Schéma du poste central
│   ├── postgres/010_initialiser_journal_sync.sql Diffusion des données chargées en SQL
│   └── seed/donnees_test.sql                    Données FICTIVES, communes aux deux bases
└── outils/               Générateurs (Python 3) des schémas, du registre et des données de test
```

Le schéma SQLite, le schéma PostgreSQL et le registre Dart sont **générés à partir d'une seule
spécification** (`outils/generer_schemas.py`) : ils ne peuvent pas diverger. Après toute modification du
modèle : `python3 outils/generer_schemas.py .` depuis la racine.

## Dépendances

| Partie | Dépendances principales |
| --- | --- |
| `sssu_core` | `uuid` (v7), `cryptography` (Argon2id, Ed25519, SHA-256), `shelf`, `shelf_router` (API), `http`, `collection` |
| `sssu_mobile` | `sssu_core`, `drift` + `drift_dev`, `sqlcipher_flutter_libs`, `sqlite3`, `flutter_secure_storage`, `mobile_scanner`, `flutter_riverpod`, `path_provider` |
| `sssu_windows` | `sssu_core`, `postgres` (v3), `basic_utils` (certificat), `qr_flutter`, `shelf`, `flutter_riverpod`, `path_provider` |

## Commandes

Prérequis : Flutter 3.24 ou plus récent (Dart 3.5+), PostgreSQL 16, Android SDK (mobile),
Visual Studio 2022 avec « Développement Desktop en C++ » (Windows).

### 1. Paquet commun — tests unitaires

```
cd sssu_core
dart pub get
dart test
```

Tests : règles métier (`regles_test`), comptes et droits (`auth_test`), règles de conflit
(`conflits_test`), traitement serveur (`service_sync_test`), appairage et jetons (`appairage_test`),
**deux téléphones de bout en bout en HTTP** (`deux_telephones_test`).

### 2. Base PostgreSQL du poste central

En production, l'installateur s'en charge. L'application crée et met à jour le schéma au démarrage
(fichiers `sql/postgres/NNN_*.sql`, voir `docs/documentation_technique.md` § 2.5).

Pour une **base de test** :

```
createdb -U postgres sssu_saj_test
psql -U postgres -d sssu_saj_test -f sql/postgres/001_schema.sql
psql -U postgres -d sssu_saj_test -f sql/seed/donnees_test.sql
psql -U postgres -d sssu_saj_test -f sql/postgres/010_initialiser_journal_sync.sql
```

Les tests appliquent ensuite les autres mises à jour (`002`, `020`…). Le test de restauration exige un
compte avec le droit `CREATEDB` et les outils `pg_dump` et `pg_restore` (`SSSU_PG_BIN`). Lancez les tests
du poste un fichier à la fois : `flutter test --concurrency=1`.

### 3. Application mobile

```
cd sssu_mobile
flutter create --org ci.sssusaj --platforms=android --project-name sssu_mobile .
dart run ../installation/android/configurer_android.dart   # manifeste, MainActivity, minSdk, signature
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter build apk --release
```

`flutter test` utilise la bibliothèque SQLite de l'ordinateur (Linux : `libsqlite3-dev` ; Windows :
`sqlite3.dll` dans le PATH ; macOS : déjà présente).

### 4. Poste central Windows

```
cd sssu_windows
flutter create --org ci.sssusaj --platforms=windows .
flutter pub get
flutter test
# Tests du dépôt PostgreSQL, sur la base de TEST préparée au point 2 :
set SSSU_PG_TEST_URL=postgres://postgres:motdepasse@localhost:5432/sssu_saj_test
set SSSU_PG_BIN=C:\Program Files\PostgreSQL\16\bin
flutter test --concurrency=1
flutter run -d windows
```

En développement, le poste crée `sssu_config.json` dans son dossier de données (`%APPDATA%`, chemin affiché
en cas d'erreur de démarrage) : y renseigner le mot de passe PostgreSQL, puis relancer. Une installation
par l'installateur utilise `C:\ProgramData\SSSU-SAJ VMS\sssu_config.json`, déjà rempli.
L'écran propose alors de créer le compte administrateur.

### 5. Essai de bout en bout

1. Poste central : créer l'administrateur, puis un compte « agent » (onglet Comptes).
2. Se connecter une fois avec le compte agent sur le poste central pour remplacer le mot de passe temporaire.
3. Onglet Téléphones : « Appairer un téléphone », choisir l'établissement, afficher le QR code.
4. Téléphone (même Wi-Fi) : scanner le QR code. Les comptes et les élèves de l'établissement sont reçus.
5. Téléphone : connexion hors ligne avec le compte agent, définir un code PIN, « SYNCHRONISER MES DONNÉES ».

## Synchronisation : ce qui est implémenté

- Appairage par QR code (code à usage unique, valable 10 minutes), clé Ed25519 générée sur le téléphone,
  épinglage du certificat TLS du poste central.
- Jeton de session (1 heure) obtenu par signature ; protection contre le rejeu et les horloges décalées.
- Envoi par lots de 200, parents avant enfants ; accusé par enregistrement : `accepte`, `deja_recu`,
  `conflit`, `refuse`. Un lot est traité dans une transaction ; les lignes modifiées sont verrouillées
  (`FOR UPDATE`).
- Réception par curseur, limitée aux référentiels et aux établissements affectés au téléphone.
- Conflits : la version du poste central est gardée, celle du téléphone est conservée dans `conflit`,
  le téléphone garde sa saisie (état « conflit ») jusqu'à la décision du Médecin-Chef
  (`ServiceConflits.resoudre` : garder serveur, garder téléphone, ou fusionner). Doublons d'élèves
  (même matricule) et de visites (même élève, même jour) acceptés mais signalés.
- Aucune donnée locale n'est supprimée avant accusé ; une modification faite pendant l'envoi reste à transmettre.

**Reporté à la phase 4** (conformément au plan) : transfert des photographies par morceaux,
découverte automatique du poste par mDNS (en phase 1 l'adresse vient du QR code), écran de résolution
des conflits.

## Décisions prises en phase 1 — à valider

1. **Administrateur sans accès aux données médicales** (contrairement à « accès complet » du prompt
   général) : séparation entre administration technique et secret médical. Réglable en base (`role_permission`).
2. **Changement du mot de passe temporaire sur le poste central uniquement.** Le téléphone ne modifie que
   le code PIN et les compteurs de tentatives ; un mot de passe changé sur le téléphone serait écrasé à la
   synchronisation suivante.
3. **Comptes présents sur les téléphones avec leur empreinte Argon2id**, pour permettre la connexion hors
   ligne. La base du téléphone est chiffrée (SQLCipher) et un téléphone perdu peut être bloqué.
4. **Matricule** : unique sur un même téléphone ; sur le poste central, deux téléphones peuvent créer le
   même matricule, ce qui est signalé comme doublon à fusionner (et non refusé, pour ne rien perdre).
5. **Conformité des inspections** : « partiellement conforme » compte pour moitié, « non applicable » est
   exclu ; niveaux satisfaisant ≥ 80 %, moyen ≥ 50 % (paramètres modifiables).
6. **Année scolaire** portée par les classes et les inscriptions, pas par l'établissement : un
   établissement est créé une fois, ses classes chaque année.
7. **Interprétation de l'IMC** : tables OMS 5-19 ans à fournir (voir ci-dessous) ; seuils adultes à partir
   de 19 ans ; avant 5 ans, « non interprétable » (normes 0-5 ans non intégrées).
8. **Sécurité du poste central en phase 1** : PostgreSQL installé séparément, clé privée TLS dans le dossier
   de l'application. Installation automatique de PostgreSQL et protection de la clé par Windows DPAPI : phase 6.
9. **Argon2id** : 19 Mio, 2 passes (minimum recommandé par l'OWASP). En pur Dart, la vérification peut
   prendre une à deux secondes sur un téléphone d'entrée de gamme ; c'est pourquoi le code PIN est proposé.

## Tables OMS de l'IMC pour l'âge

Le code n'invente aucune valeur de référence. Pour activer l'interprétation entre 5 et 19 ans, créer à
partir des fichiers officiels OMS « BMI-for-age 5–19 years » (garçons et filles, colonnes L, M, S par
mois) deux fichiers CSV :

```
mois,L,M,S
61,<L>,<M>,<S>
...
228,<L>,<M>,<S>
```

Ils seront intégrés comme ressources de l'application en phase 2 (`TableImcOmsCsv.depuisCsv`).
Les tests utilisent des valeurs fictives, signalées comme telles, pour vérifier la formule.

## Données de test

`sql/seed/donnees_test.sql` (généré par `outils/generer_donnees_test.py`) : année 2026-2027,
2 établissements **fictifs**, 4 classes, 120 élèves **fictifs** (dont 2 sans matricule), 5 rôles et
la matrice des droits, 17 pathologies, 21 critères d'inspection, en-tête institutionnel. Aucun compte
utilisateur : les comptes sont créés par l'application (mots de passe hachés).

---

# Phase 2 — Version mobile

## Ce qui est livré

| Module | Contenu |
| --- | --- |
| Établissements | Liste avec classes, effectif, élèves examinés et taux de couverture de l'année ; classes (effectif garçons/filles, examinés) ; élèves d'une classe avec filtre « non examinés » ; recherche rapide par nom, prénoms ou matricule ; fiche élève avec historique des visites. Le Médecin-Chef peut créer une classe. |
| Importation | Excel (.xlsx), CSV (UTF-8 ou Windows-1252, `;` `,` ou tabulation), PDF texte, PDF scannés et photos de listes papier (OCR Google ML Kit sur le téléphone). Aperçu du PDF, colonnes reconnues automatiquement (intitulés variés, plusieurs mots, colonnes décalées, en-têtes répétés, nom et prénoms séparés ou regroupés, textes sur deux lignes), affectation manuelle des colonnes, tableau de contrôle : doublons (dans le fichier et avec les élèves déjà connus), matricules manquants, sexe, dates, âge, corrections, ajout et rejet de lignes. **Rien n'est enregistré avant la validation.** Rattachement automatique à l'établissement, la classe et l'année ; changement de classe détecté ; fichier source conservé chiffré. |
| Visite | Formulaire en 7 onglets : identification, antécédents (repris de la visite précédente, rubrique gynécologique pour les filles de 9 ans et plus), examen clinique (IMC automatique et interprété, alertes de vraisemblance), examen par appareil (normal / anormal / non examiné + observations), dépistage multi-sélection, conclusion, photos. Contrôles avant transmission. |
| Photos | Consentement du parent ou tuteur obligatoire ; appareil photo ou galerie ; réduction à 1600 px, JPEG, **suppression des métadonnées EXIF (position GPS)** ; chiffrement AES-256-GCM dans l'espace privé de l'application ; commentaire et pathologie associée ; agrandissement, remplacement, suppression. |
| Ébauches | Ébauche → Enregistré localement → Valider et synchroniser (tous les éléments de la visite passent en attente, synchronisation lancée aussitôt si le poste est joignable). Sauvegarde automatique toutes les 30 secondes, à chaque changement d'onglet, à la mise en arrière-plan et à la sortie. Liste des ébauches. Validation médicale possible sur le téléphone (médecin, Médecin-Chef). |

## Vérifications faites ici

- Schémas régénérés (classe envoyable par le téléphone, format « image_ocr ») rechargés sans erreur dans SQLite et PostgreSQL.
- **Toutes les requêtes SQL des écrans exécutées sur la base de test** : effectifs (60 par établissement), classes (30 élèves, 15 garçons, 15 filles), élèves d'une classe, recherche, ébauches, pathologies.
- Noms de tables et de colonnes du code vérifiés automatiquement contre le registre.
- Code Dart/Flutter : **toujours non compilé ici** (même limite qu'en phase 1).

## Tests ajoutés

- `sssu_core/test/import_test.dart` : intitulés, CSV (encodages, guillemets), **page OCR simulée** (colonnes décalées, « O » lu au lieu de « 0 », en-tête répété sur la page 2, prénoms sur deux lignes), dates Excel et OCR, doublons, contrôles.
- `sssu_core/test/visite_test.dart` : formulaire, IMC, contrôles avant transmission, statuts affichés, chiffrement AES-GCM.
- `sssu_mobile/test/phase2_test.dart` : sur la vraie base SQLite avec le jeu de test — effectifs, import CSV complet (création, rattachement, ligne rejetée, fichier chiffré), lecture d'un classeur Excel, dossier de visite (ébauche locale, rechargement, transmission de tous les éléments, couverture), suppression d'une ébauche.
- `sssu_core/test/service_sync_test.dart` : création de classe depuis le téléphone (Médecin-Chef seulement).

Commandes : identiques à la phase 1 (`dart test` dans `sssu_core`, `flutter test` dans `sssu_mobile`).

## Points à valider (phase 2)

1. **.xls** : non lisible sur le téléphone ; l'application demande de réenregistrer le fichier en .xlsx.
2. **Création des établissements** sur le poste central uniquement ; création des classes sur le téléphone par le Médecin-Chef.
3. **OCR hors ligne** : modèle latin de Google ML Kit intégré à l'application. **À vérifier sur un téléphone en mode avion dès la première utilisation.** L'OCR ne fournit pas ici de score de confiance exploitable : les valeurs douteuses sont signalées par les contrôles (date illisible, sexe illisible, matricule corrigé automatiquement…).
4. **Format du matricule** : aucun format n'est imposé faute de référence officielle. Si les matricules suivent un format fixe (par exemple 8 chiffres et une lettre), l'indiquer dans le paramètre `format_matricule` (expression régulière, table `parametre`) : la correction OCR devient plus fiable et les matricules non conformes sont signalés.
5. **Contrôles bloquants** avant « Valider et synchroniser » : conclusion ; diagnostic si anomalie, suivi ou référence ; structure si référence ; précision pour « Autres pathologies » et « Handicap ». Les autres contrôles sont des avertissements.
6. **Photos** : le transfert des fichiers vers le poste central est en phase 4 ; jusque-là les métadonnées des photos sont synchronisées et les fichiers restent chiffrés sur le téléphone.
7. **Tables OMS de l'IMC** : toujours à fournir (`sssu_mobile/assets/oms/LISEZMOI.txt`). Sans elles, l'IMC est calculé mais « non interprétable » entre 5 et 19 ans.
8. **Dépendances ajoutées** (`excel`, `pdfrx`, `google_mlkit_text_recognition`, `image`, `image_picker`, `file_picker`, `cryptography_flutter`) : versions à confirmer par `flutter pub get` ; l'API de `pdfrx` a évolué entre ses versions 1 et 2 (le code cible la version 1).

---

# Phase 3 — Poste central Windows

## Ce qui est livré

| Écran (menu latéral) | Contenu | Accès |
| --- | --- | --- |
| Tableau de bord | État du serveur de synchronisation, compteurs | Tous |
| Établissements | Années scolaires (création, année active) ; établissements (création, modification, archivage refusé si des dossiers médicaux y sont rattachés) ; classes de l'année (effectif G/F, examinés, couverture) | Lecture : tous ; gestion : Administrateur, Médecin-Chef |
| Élèves et dossiers | Recherche par établissement, classe, nom ou matricule, filtre « non examinés » ; dossier de l'élève : identité (modifiable), scolarité et changement de classe ; visites médicales (rubriques A à F, validation, réouverture motivée) ; **galerie photographique** de toutes les visites (agrandissement, commentaires, téléchargement réservé) | Visites et photos : profils médicaux uniquement (l'administrateur ne voit que l'identité) |
| Importer une liste | Excel, CSV, PDF, PDF scannés et images (Tesseract) ; mêmes contrôles que sur le téléphone ; validation explicite | Droit `import.executer` |
| Téléphones | Appairage, **établissements affectés** (un établissement ajouté est envoyé en entier au téléphone), blocage | Administrateur |
| Comptes | Création, désactivation, réinitialisation du mot de passe (temporaire), changement de rôle | Administrateur |
| Synchronisations | Journal des envois des téléphones (agent, canal, refus et conflits) | Administrateur, Médecin-Chef |
| Journal d'audit | Connexions, consultations de dossiers et de photos, téléchargements, créations, modifications, archivages | Droit `audit.consulter` |

Toutes les actions de gestion passent par `ServiceGestion` (paquet commun) : contrôle des droits,
nouvelle version de l'enregistrement, diffusion aux téléphones concernés et ligne du journal d'audit
(les empreintes de mots de passe n'y figurent jamais).

## Correction de la synchronisation apportée en phase 3

Quand un élève change d'établissement (changement de classe, importation, inscription envoyée par un
téléphone), son dossier (identité, visites, antécédents) est maintenant **rattaché au nouvel
établissement avant l'inscription**. Les téléphones de cet établissement reçoivent donc l'élève avant son
inscription. Le téléphone applique en outre chaque page reçue dans une transaction aux contrôles de clés
étrangères différés. Sans cette correction, la synchronisation d'un téléphone pouvait se bloquer.

## Vérifications faites ici

- **Toutes les requêtes SQL des écrans Windows exécutées sur PostgreSQL 16** avec le jeu de test enrichi
  (une visite, une photo, un téléphone, des journaux) : années, établissements, classes (30 élèves,
  15 G / 15 F, 1 examiné), élèves par classe, par établissement et par recherche, scolarité, visites,
  photos, journaux de synchronisation et d'audit, téléphones avec leurs établissements, rediffusion par
  établissement.
- Noms de colonnes du code de gestion vérifiés contre le registre ; parenthèses équilibrées dans les 95 fichiers Dart.
- Code Dart/Flutter : **toujours non compilé ici**.

## Tests ajoutés

- `sssu_core/test/gestion_test.dart` : droits, unicité des codes et des classes, archivages refusés,
  année active unique, validation et réouverture motivée, **rediffusion à un téléphone nouvellement
  affecté (parents d'abord)**, dossier qui suit l'élève changeant d'établissement, importation sur le poste,
  comptes (désactivation, mot de passe temporaire, rôle, aucune empreinte dans le journal), lecture du TSV de Tesseract.
- `sssu_windows/test/phase3_test.dart` : stockage chiffré des photos ; requêtes et gestion sur PostgreSQL
  (si `SSSU_PG_TEST_URL` est défini, base de test chargée avec le schéma, le jeu de test et `010_…`).

## Points à valider (phase 3)

1. **Photos** : la galerie et le stockage chiffré sont en place ; les fichiers arriveront avec le transfert
   de la phase 4. D'ici là, les photos s'affichent « en attente de transfert depuis le téléphone ».
2. **Clé de chiffrement des photos** du poste conservée dans le dossier de l'application ; protection par
   Windows DPAPI en phase 6, avec celle de la clé du certificat.
3. **OCR sur le poste** : Tesseract (langue française) doit être installé ; chemin facultatif `"tesseract"`
   dans `sssu_config.json`. Son installation automatique est prévue en phase 6.
4. **Réouverture d'une visite validée** : elle repasse « enregistrée » ; l'agent la corrige sur son
   téléphone puis la valide de nouveau. Le motif est obligatoire et tracé.
5. **Recherche d'élèves** : insensible à la casse mais pas aux accents (« KONE » ne trouve pas « KONÉ »).
   L'extension PostgreSQL `unaccent` peut être ajoutée en phase 6 si besoin.
6. **Changement de mot de passe** : un mot de passe réinitialisé est temporaire et doit être changé sur le
   poste central (décision de la phase 1).

# Phase 4 — Synchronisation Wi-Fi et Internet, conflits, photos

## Ce qui est livré

**Trouver le poste central** (téléphone, `ServicesMobile.trouverPosteCentral`). Le téléphone essaie dans l'ordre :

1. la dernière adresse locale qui a répondu ;
2. le poste trouvé sur le Wi-Fi par diffusion UDP (port 8444), **seulement si l'empreinte de son certificat
   est celle de l'appairage** ; si l'adresse du poste a changé, la nouvelle est retenue ;
3. l'adresse Internet du poste, si elle figure dans le QR code d'appairage.

Le journal de synchronisation indique le canal utilisé (Wi-Fi local ou Internet).

**Synchronisation automatique** pendant que l'application est ouverte : au retour du réseau, au passage sur
le Wi-Fi et toutes les 15 minutes. Un seul passage à la fois. Le bouton SYNCHRONISER MES DONNÉES reste disponible.

**Photographies** :

- leurs données partent d'abord ; le fichier suit, par morceaux de 512 Ko (15 Mo au plus) ;
- après une coupure, seuls les morceaux manquants sont renvoyés ;
- le poste vérifie l'empreinte SHA-256, chiffre le fichier dans son stockage et passe la photo à « confirme » ;
- le téléphone efface alors sa copie et affiche « Transférée au poste central » ;
- le fichier local d'une photo supprimée est effacé dès que le poste a enregistré la suppression.

**Conflits — poste Windows, menu « Conflits »** (droit `conflit.resoudre`, Médecin-Chef). Chaque conflit montre
les deux versions champ par champ, avec les différences surlignées. Décisions possibles selon le type :

| Type | Décisions |
| --- | --- |
| Modifications concurrentes | Garder la version du poste, retenir celle du téléphone, ou composer une version champ par champ |
| Suppression et modification | Garder la version du poste, ou accepter la suppression |
| Doublon probable d'élève | Fusionner (dans le dossier existant ou dans le nouveau), ou garder les deux |
| Deux visites le même jour | Archiver l'une ou l'autre (avec ses éléments), ou garder les deux |
| Enregistrement déjà existant | Clore : la version du poste est conservée |

La décision est transmise aux téléphones à leur synchronisation suivante et remplace leur version en conflit.

**Téléphone — « Éléments à vérifier »** : l'écran liste ce que le poste a refusé ou mis en conflit, avec le motif.
Un élément jamais accepté par le poste peut être abandonné, avec les éléments saisis qui en dépendent.

**Configuration du poste** (`sssu_config.json`) : `adresse_internet` (facultative, par exemple
`https://sssu-saj.ddns.net:8443`) et `nom_poste`.

## Vérifications faites ici

- Contraintes PostgreSQL du transfert de photo (utilisateur, appareil, visite, consentement, photo,
  statut « confirme ») et du cycle d'un conflit : rejoués sur PostgreSQL 16 avec le jeu de test.
- Requêtes SQLite du téléphone (fichiers à transférer, éléments en conflit, clés étrangères pour l'abandon) :
  exécutées sur le schéma mobile.
- Parenthèses, crochets et accolades équilibrés dans les 104 fichiers Dart (vérificateur qui tient compte des
  chaînes et des interpolations) ; noms de colonnes contrôlés contre le registre.
- Code Dart/Flutter : **toujours non compilé ici**.

## Tests ajoutés

- `sssu_core/test/phase4_test.dart` couvre :
  - les morceaux reçus dans le désordre, la reprise et la confirmation renvoyée ;
  - le fichier altéré (refusé) ;
  - les contrôles d'accès : photo inconnue, autre établissement, table sans fichier, morceau trop gros ;
  - la fusion de deux dossiers d'élève, l'archivage d'une visite en double et la clôture d'un doublon d'inscription ;
  - l'adresse Internet dans le QR code.
- `sssu_core/test/deux_telephones_test.dart`, par HTTP réel : photo de 1,2 Mo en trois morceaux, puis découverte du poste sur la boucle locale.
- `sssu_mobile/test/phase4_test.dart`, sur la vraie base SQLite :
  - le transfert de la photo et l'effacement de la copie locale ;
  - le statut « confirme » gardé après une modification ;
  - le fichier local manquant ;
  - les éléments refusés et leur abandon en cascade.
- `sssu_windows/test/phase4_test.dart` : réception dans le stockage chiffré du poste, en mémoire et sur
  PostgreSQL ; conflit lu et clos sur PostgreSQL.
- Le transport de test du téléphone est déplacé dans `sssu_mobile/test/outils/transport_direct.dart`.

```
cd sssu_core && dart test
cd sssu_mobile && flutter pub get && flutter test
cd sssu_windows && SSSU_PG_TEST_URL=postgres://… flutter test
```

## Points à valider (phase 4)

1. **Synchronisation par Internet** : il faut une adresse fixe ou un nom DynDNS, et une redirection du port
   8443 du routeur vers le poste. Le certificat reste vérifié par son empreinte, quel que soit le nom
   utilisé. Les téléphones déjà appairés n'ont pas cette adresse : ré-appairez-les une fois `adresse_internet` renseignée.
2. **Découverte Wi-Fi** : elle utilise une diffusion UDP sur le port 8444 plutôt que mDNS. Le pare-feu
   Windows doit autoriser ce port en entrée ; sinon les téléphones utilisent la dernière adresse connue.
3. **Copie du téléphone effacée** après confirmation du poste : la photo ne se consulte plus que sur le poste central.
4. **Synchronisation automatique** uniquement application ouverte. Une synchronisation en arrière-plan, application
   fermée (WorkManager), nécessite le déverrouillage de la base chiffrée sans l'utilisateur : je propose de
   l'étudier en phase 6.
5. **Fusion de dossiers** : refusée si les deux dossiers sont dans des établissements différents ; il faut
   d'abord changer la classe de l'un des élèves.
6. **Morceaux en cours** gardés en mémoire par le poste, une heure au plus : un redémarrage du poste
   fait seulement renvoyer la photo en entier.

# Phase 5 — Statistiques, rapports et inspection sanitaire

## Ce qui est livré

**Inspection sanitaire (section 11).**

- **Téléphone, menu « Inspection sanitaire »** (droit `inspection.realiser`) :
  - choix de l'établissement, puis historique des inspections faites sur l'appareil ;
  - grille par rubrique (eau potable, toilettes, lavage des mains, déchets, environnement, cantines,
    vendeuses, infirmerie, sécurité). Chaque critère se note Conforme, Partiellement conforme, Non conforme
    ou Non applicable, avec une observation ;
  - photos des insuffisances, observations, recommandations, date, inspecteur ;
  - signature tracée au doigt dans une fenêtre dédiée, pour ne pas faire défiler l'écran en signant.
- **Calcul en direct** : nombre de critères dans chaque catégorie, taux de conformité (les « non
  applicable » sont exclus, les « partiellement conforme » comptent pour moitié) et niveau global.
  Les seuils sont réglés dans les paramètres, 80 et 50 % par défaut.
- **Cycle de vie** : une inspection reste une ébauche, sauvegardée toutes les 30 secondes, jusqu'à
  « Enregistrer et transmettre ». Il faut alors une réponse pour chaque critère et la signature. Elle part
  ensuite avec ses réponses et ses photos, envoyées par morceaux comme en phase 4.
- **Poste, page « Inspections »** :
  - historique de tous les établissements ;
  - détail d'une inspection : grille, photos, signature ;
  - rapport d'inspection en PDF ou Excel ;
  - onglet « Grille d'inspection » (droit `parametres.modifier`) : ajouter, renommer, réordonner,
    retirer ou rétablir un critère. Les inspections passées gardent leurs réponses ;
    les téléphones reçoivent la grille à jour.

**Statistiques (sections 4 et 12).** Tous les indicateurs sont calculés par un seul moteur, dans le
paquet commun (`calculerStatistiques`). Le téléphone et le poste affichent donc les mêmes définitions :

- effectif, garçons et filles, élèves examinés et non examinés, nombre de visites, taux de couverture ;
- par sexe, par établissement, par classe ;
- conclusion de la dernière visite ;
- pathologies : cas, garçons et filles, tranches d'âge, établissements, classes et prévalence ;
- inspections : établissements inspectés, conformes et non conformes, taux moyen, principales insuffisances ;
- évolution mensuelle : visites et couverture cumulée.

Sur le **poste** :

- le tableau de bord présente les indicateurs de la section 4 et trois graphiques ;
- la page « Statistiques » a quatre onglets (couverture, pathologies, inspections, évolution), avec
  histogrammes, diagrammes circulaires, courbes et tableaux ;
- les filtres portent sur l'année scolaire, l'établissement, la classe, le sexe et la période ;
- les écrans se mettent à jour automatiquement dans les 20 secondes qui suivent une synchronisation.

Sur le **téléphone**, l'écran « Statistiques » (droit `statistiques.consulter`) donne une version
simplifiée, limitée aux données de l'appareil, sans aucune donnée nominative.

**Rapports (section 13)**, page « Rapports » du poste, en **PDF ou Excel** :

- rapport annuel du district ;
- rapport par établissement et par classe ;
- rapport statistique des pathologies ;
- synthèse des inspections sanitaires ;
- listes des élèves examinés et non examinés ;
- élèves référés et élèves à suivre.

D'autres documents s'éditent ailleurs :

- la **fiche individuelle de visite**, depuis le dossier de l'élève (bouton « Fiche individuelle ») ;
- le **rapport d'inspection**, depuis la page Inspections.

Tous les rapports portent :

- l'en-tête institutionnel et le logo, réglés dans la page **« Paramètres »** ;
- le bloc de signature et de cachet du Médecin-Chef ;
- la pagination.

Les documents nominatifs portent la mention « secret médical ». Chaque édition est tracée dans le journal
d'audit (action « export »).

**Paramètres** (droit `parametres.modifier`) : six lignes d'en-tête (pour un autre district), nom du
Médecin-Chef, logo (réduit automatiquement), seuils de conformité, délais de verrouillage. Le délai du poste
s'applique désormais à l'ouverture de session.

## Nouveaux fichiers

- `sssu_core/lib/src/inspection/formulaire_inspection.dart` : grille, réponses, calcul, contrôles avant transmission.
- `sssu_core/lib/src/statistiques/statistiques.dart` : jeu de données, filtres, indicateurs, listes nominatives.
- `sssu_core/lib/src/rapports/` : modèle de document, composition des rapports, rendu PDF (paquet `pdf`) et Excel (paquet `excel`).
- `sssu_core/lib/src/gestion/service_gestion.dart` : grille d'inspection, paramètres, trace des exports.
- `sssu_mobile/lib/inspection/` : dépôt, écrans, zone de signature ; `sssu_mobile/lib/statistiques/ecran_statistiques.dart`.
- `sssu_windows/lib/donnees/source_statistiques.dart`, `sssu_windows/lib/rapports/service_rapports.dart`.
- `sssu_windows/lib/ui/` : `page_statistiques.dart`, `page_inspections.dart`, `page_rapports.dart`,
  `page_parametres.dart`, `statistiques_commun.dart` (filtres, graphiques `fl_chart`).
- `sssu_windows/assets/polices/` : DejaVu Sans, licence libre jointe. Les polices standard du PDF ne
  couvrent pas tous les caractères français.

Nouvelles dépendances : `pdf` et `excel` (paquet commun) ; `fl_chart` (poste).

## Vérifications faites ici

- Requêtes PostgreSQL des statistiques, de l'historique des inspections, de la grille, des paramètres et
  du tableau de bord : 36 requêtes exécutées sur PostgreSQL 16, avec le jeu de test et une inspection
  ajoutée (120 élèves inscrits retrouvés).
- Requêtes SQLite du téléphone (statistiques, inspections) : exécutées sur le schéma mobile.
- Parenthèses, crochets et accolades équilibrés dans les 124 fichiers Dart ; noms de colonnes contrôlés contre le registre.
- Code Dart/Flutter : **toujours non compilé ici**.

## Tests ajoutés

- `sssu_core/test/phase5_test.dart` couvre :
  - le formulaire d'inspection : ordre de la grille, contrôles, calcul, rechargement, seuils ;
  - les indicateurs, sur un jeu de 8 élèves où chaque valeur attendue est justifiée : élève sorti,
    inscription supprimée, ébauche, visite de l'année précédente ; filtres de sexe, de classe et de
    période ; évolution ; inspections ;
  - les droits sur les rapports ;
  - le rendu PDF et Excel, avec des nombres restés numériques dans Excel ;
  - la grille et les paramètres ;
  - la fiche de visite et le rapport d'inspection lus dans le dépôt.
- `sssu_mobile/test/phase5_test.dart`, sur la base SQLite :
  - l'ébauche non transmise, puis la transmission refusée tant qu'il manque une réponse et la signature ;
  - l'envoi de l'inspection, de ses 3 réponses et de sa photo (fichier compris) ;
  - le rechargement, la suppression d'une ébauche et les statistiques de l'appareil.
- `sssu_windows/test/phase5_test.dart`, sur PostgreSQL :
  - indicateurs égaux aux comptages SQL ;
  - rapport enregistré en PDF et en Excel, export tracé ;
  - grille et paramètres.

## Points à valider (phase 5)

1. **Élève examiné** : élève inscrit qui a au moins une visite autre qu'une ébauche pendant l'année, ou
   pendant la période filtrée. La conclusion et la tranche d'âge retenues sont celles de sa dernière visite.
2. **Tranches d'âge** : < 6, 6–9, 10–14, 15–19, 20–24, 25 ans et plus. Elles se changent dans `TrancheAge`.
3. **Inspections dans les statistiques** : seule la dernière inspection de chaque établissement compte.
   Un établissement est « conforme » s'il est au niveau satisfaisant, « non conforme » s'il est au niveau
   moyen ou insuffisant.
4. **Statistiques pour l'administrateur** : il voit les indicateurs agrégés, pathologies comprises, mais
   aucune liste nominative ni fiche. C'est la matrice des droits de la phase 1 ; dites-moi s'il faut lui
   retirer le profil des pathologies.
5. **Word** non livré : PDF et Excel seulement. Les graphiques sont à l'écran ; les rapports PDF présentent
   les résultats en tableaux.
6. **Signature de l'inspecteur** : image tracée à l'écran, sans valeur de signature électronique qualifiée.
   Le cachet et la signature du Médecin-Chef restent un emplacement à compléter sur le document imprimé.
7. **Téléphone** : il ne garde que ses propres inspections, et une inspection transmise n'y est plus modifiable.
   L'écran Statistiques du téléphone suit la matrice des droits (Administrateur, Médecin-Chef, Médecin).
8. **Logo** : il est aussi transmis aux téléphones avec les autres paramètres (200 Ko au plus).


# Phase 6 — Tests et livraison

## Ce qui est livré

### Sauvegarde et restauration (poste, page « Sauvegardes », administrateur)

- **Contenu d'une sauvegarde** :
  - la base PostgreSQL (`pg_dump`) ;
  - les photographies ;
  - la clé des photos ;
  - le certificat du poste et sa clé privée.
- **Chiffrement** : toute l'archive est chiffrée (`.sssubak`, AES-256-GCM par blocs, en flux). La clé est
  dérivée de la **phrase de passe** choisie par l'administrateur (Argon2id).
- **Planification** :
  - une sauvegarde automatique par jour, à l'heure choisie ;
  - rattrapage au démarrage si le poste était éteint ;
  - nouvel essai une heure après un échec ;
  - conservation des 14 dernières ;
  - dossier réglable (disque externe conseillé).
- **Vérification complète** d'une sauvegarde : phrase, intégrité et contenu.
- **Restauration**, en six étapes :
  1. sauvegarde de sécurité de l'état actuel ;
  2. chargement dans une base neuve ;
  3. échange par renommage, l'ancienne base étant gardée ;
  4. remise en place des photos et des clés ;
  5. trace dans le journal d'audit ;
  6. fermeture de l'application, à relancer.

  Elle fonctionne aussi sur un **autre PC**. Les téléphones gardent le certificat épinglé et retrouvent le
  poste sur le Wi-Fi.
- Le **tableau de bord** signale en rouge une dernière sauvegarde de plus de 36 heures.

### Reprise des téléphones après une restauration

- La restauration change la « génération » des données du poste.
- À sa synchronisation suivante, chaque téléphone le voit :
  1. il renvoie ce qu'il détient, et le poste garde la version la plus récente ;
  2. il recharge tout.
- Rien de ce qui avait été saisi depuis la sauvegarde ne se perd, si un téléphone l'a encore.
- Un téléphone appairé après la sauvegarde propose un nouvel appairage et garde ses données.

### Sécurité

- **Clés du poste** (photos, certificat, sauvegardes) : protégées par **Windows DPAPI**, portée ordinateur.
  Un ancien fichier de clé en clair est converti au premier lancement.
- **Base PostgreSQL** : réservée à la machine (`localhost`, scram-sha-256). Ses fichiers ne sont accessibles
  qu'au service.
- **Téléphone bloqué** sur le poste : à sa connexion suivante, il **efface** sa base, ses photos et ses clés,
  puis affiche « Téléphone bloqué ». Au lancement suivant, il repart de l'appairage.
- **Délais de verrouillage** : ceux réglés dans les paramètres s'appliquent désormais (téléphone et poste).

### Mises à jour du schéma

- Les fichiers `sql/postgres/NNN_*.sql` sont appliqués au démarrage du poste, une fois chacun
  (table `schema_migration`).
- `002_referentiels.sql` contient les référentiels de production : rôles et droits, 17 pathologies,
  grille de 21 critères, paramètres. Il ne contient aucune donnée de personne.
- `020_phase6.sql` crée la génération de synchronisation et la recherche **sans accents** (`unaccent`) :
  « kouame » trouve « KOUAMÉ ».

### Installables

- **`installation/windows/`** :
  - installateur **Inno Setup**, qui installe en une procédure l'application, PostgreSQL 16 (service
    Windows), Tesseract (français), le runtime Visual C++, la base, le compte, la configuration et le
    pare-feu ;
  - scripts `preparer_dependances.ps1`, `configurer_poste.ps1`, `desinstaller_poste.ps1` et
    `construire_poste.ps1`.
- **`installation/android/`** :
  - `configurer_android.dart`, qui règle le projet généré par Flutter : manifeste, `FLAG_SECURE`,
    Android 8.0 minimum, signature ;
  - scripts `construire_apk.ps1` et `.sh` ;
  - `LISEZMOI.md` (clé de signature).
- **`.github/workflows/livraison.yml`** :
  - tous les tests à chaque envoi, avec PostgreSQL 16 ;
  - sur une étiquette `v1.0.0`, construction de l'APK signé et de l'installateur Windows, joints à une
    « release ».

### Documentation (`docs/`)

| Fichier | Contenu |
| --- | --- |
| `guide_installation.md` | Installation, premier lancement, appairage, Internet, mises à jour, production des installables |
| `guide_utilisation.md` | Téléphone et poste central, par profil |
| `documentation_technique.md` | Architecture, modèle de données, protocole de synchronisation, sécurité et loi n° 2013-450, sauvegardes, statistiques, tests, dépannage |
| `plan_recette.md` | Essais sur le terrain : installation, appairage, hors ligne, synchronisation, poste central, sécurité, exercice de restauration, procès-verbal |

## Vérifications faites ici

- **Restauration sur PostgreSQL 16**, avec les commandes exactes du service :
  - compte non super-utilisateur, avec `CREATEDB` ;
  - `pg_dump -Fc`, base neuve, `pg_restore --single-transaction`, échange par renommage, nouvelle
    génération ;
  - le paramètre modifié après la sauvegarde est revenu, et l'extension `unaccent` est restaurée.
- **Fichiers SQL** :
  - `002_referentiels.sql` et `020_phase6.sql` appliqués deux fois sur une base de production vierge :
    5 rôles, 41 droits, 17 pathologies, 21 critères, 9 paramètres ;
  - appliqués aussi sur une base de test déjà chargée, sans doublon.
- **Requêtes** : recherche sans accents et requêtes nouvelles ou modifiées exécutées sur PostgreSQL.
- **Code** : parenthèses et accolades équilibrées dans les 133 fichiers Dart ; flux d'intégration continue
  valide (YAML).
- Code Dart/Flutter, scripts PowerShell et Inno Setup : **non exécutés ici** (ni Flutter, ni Windows).
  L'intégration continue les exécute.

## Tests ajoutés

- `sssu_core/test/phase6_test.dart` :
  - **5 téléphones** sur 2 établissements, synchronisés dans le désordre ;
  - hors ligne puis retour du réseau ;
  - accusé de réception perdu (aucun doublon) ;
  - réception interrompue (état final identique à celui d'un téléphone non coupé) ;
  - modification concurrente (conflit, aucune perte, décision diffusée) ;
  - **reprise après restauration** : 3 téléphones, dont l'un avec une copie ancienne ; modification hors
    ligne au moment de la restauration ;
  - **sécurité** : établissement non affecté, tables réservées au poste (comptes, droits, paramètres),
    auteur inconnu ou désactivé, visite d'un autre agent, visite validée, lot trop grand, rien de
    confidentiel diffusé, jetons, téléphone bloqué.
- `sssu_mobile/test/phase6_test.dart`, sur SQLite réel :
  - reprise ;
  - préparation de la reprise (ébauches et comptes exclus) ;
  - téléphone bloqué.
- `sssu_windows/test/phase6_test.dart` :
  - archive chiffrée : aller-retour sur plusieurs blocs, clé fausse, octet modifié, troncature, nom
    dangereux ;
  - phrase de passe ;
  - planification des sauvegardes ;
  - clé protégée ;
  - migrations idempotentes, génération, recherche sans accents ;
  - **sauvegarde puis restauration réelles** sur PostgreSQL.

## Points à valider (phase 6)

1. **Installables** : à produire par l'intégration continue GitHub, ou sur un PC Windows. Les versions de
   PostgreSQL (16.10) et de Tesseract (5.5.0) sont des paramètres du script : vérifiez les dernières
   versions publiées. La première construction révélera d'éventuelles erreurs de compilation, que je
   corrigerai.
2. **Accès au poste** : les clés sont protégées par DPAPI au niveau de l'**ordinateur**, pas d'un compte
   Windows. Tous les comptes Windows du poste peuvent donc ouvrir l'application ; l'accès aux données reste
   contrôlé par les comptes SSSU-SAJ. Le poste doit être réservé au personnel autorisé ; BitLocker est
   recommandé.
3. **Phrase de passe des sauvegardes** : si elle est perdue, les sauvegardes sont irrécupérables sur un
   autre PC. Le poste lui-même continue de sauvegarder.
4. **Téléphone bloqué** : les données non transmises sont effacées avec le reste.
5. **Loi n° 2013-450** : les mesures techniques sont décrites dans `documentation_technique.md` § 4.2. Les
   formalités auprès de l'ARTCI et la durée de conservation sont à fixer par le service.
6. **Synchronisation application fermée** : non prévue. Elle reste automatique tant que l'application
   est ouverte.
7. **Plan de recette** : les essais sur de vrais téléphones et sur le poste installé restent à faire, avec
   `docs/plan_recette.md`. Je corrigerai les anomalies relevées.

## Version 1.0.1

- Téléphone : bouton **« Synchroniser avec le poste central »** sur l'écran de connexion. La
  synchronisation n'exige plus qu'un utilisateur soit connecté : un agent dont le mot de passe
  temporaire a été changé sur le poste central (ou un compte créé après l'appairage) peut le
  recevoir puis se connecter. Test : `sssu_mobile/test/comptes_test.dart`.

## Version 1.0.2

- Poste central : **« Supprimer le compte »** dans le menu de chaque compte (motif obligatoire,
  confirmation). Suppression logique : le compte ne se connecte plus nulle part, disparaît des listes,
  son identifiant est libéré ; visites, inspections et journal d'audit gardent leur auteur. Refusée pour
  son propre compte et pour le dernier administrateur actif. `ServiceGestion.supprimerCompte`.
- Téléphone : une session ouverte est fermée si son compte a été supprimé ou désactivé sur le poste.
- Tests : `sssu_core/test/gestion_test.dart`, `sssu_mobile/test/comptes_test.dart`.
