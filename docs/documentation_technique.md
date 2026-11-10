# SSSU-SAJ VMS — Documentation technique

Ce document s'adresse aux informaticiens chargés de la maintenance ou de l'évolution de l'application. Pour l'installation, voir `guide_installation.md` ; pour l'usage, `guide_utilisation.md` ; pour les essais avant mise en service, `plan_recette.md`.

## 1. Architecture

```
 Téléphones Android (Flutter)                      Poste central Windows (Flutter Desktop)
 ┌──────────────────────────────┐   HTTPS 8443    ┌──────────────────────────────────────┐
 │ sssu_mobile                  │ ◄─────────────► │ sssu_windows                         │
 │  SQLite chiffrée (SQLCipher) │  Wi-Fi local    │  API REST (shelf) + découverte UDP   │
 │  photos chiffrées AES-GCM    │  ou Internet    │  PostgreSQL 16 (service Windows)     │
 │  ML Kit (OCR hors ligne)     │                 │  photos chiffrées, sauvegardes       │
 └──────────────┬───────────────┘                 └──────────────────┬───────────────────┘
                └──────────── sssu_core (Dart pur, partagé) ─────────┘
          modèles, règles métier, droits, protocole et logique de synchronisation,
          import, formulaires, statistiques, rapports PDF/Excel
```

| Paquet | Rôle |
| --- | --- |
| `sssu_core` | Toute la logique indépendante de l'interface : modèles (`modeles/`), règles (âge, IMC OMS, constantes, conformité), droits (`auth/`), synchronisation client et serveur (`sync/`), import de listes (`import/`), formulaires de visite et d'inspection, gestion centralisée (`gestion/`), statistiques et rapports. Testé avec `dart test`. |
| `sssu_mobile` | Application Android : base drift/SQLCipher (`data/`), coffre Keystore (`securite/`), écrans, OCR ML Kit, photos, inspection, synchronisation automatique. |
| `sssu_windows` | Poste central : dépôt PostgreSQL (`donnees/`), serveur HTTPS (`serveur/`), écrans de gestion, statistiques (`fl_chart`), rapports, sauvegardes (`sauvegarde/`), protection DPAPI (`securite/`). |
| `sql/` | Schéma PostgreSQL et fichiers de mise à jour (`postgres/NNN_*.sql`), jeu de données de test (`seed/`). |
| `outils/` | Générateur du schéma (`generer_schemas.py`) et du jeu de test. |
| `installation/` | Installateur Windows (Inno Setup, PowerShell) et construction Android. |

## 2. Modèle de données

### 2.1 Spécification unique

Les tables sont décrites une seule fois, dans `outils/generer_schemas.py`. Ce script génère trois fichiers, à ne **jamais modifier à la main** :

- `sssu_mobile/lib/data/tables.drift` : schéma SQLite du téléphone ;
- `sql/postgres/001_schema.sql` : schéma PostgreSQL ;
- `sssu_core/lib/src/schema/registre.dart` : registre des tables utilisé par la synchronisation.

Pour ajouter une colonne :

1. modifiez la spécification et relancez le script ;
2. écrivez un fichier de mise à jour PostgreSQL `0NN_….sql` (`ALTER TABLE …`) ;
3. augmentez `schemaVersion` dans `sssu_mobile/lib/data/base_locale.dart` et ajoutez l'étape de migration drift.

### 2.2 Colonnes communes

Chaque table synchronisée porte :

- `id` (UUID v7, créé par l'appareil) ;
- `version`, `created_at`, `updated_at`, `created_by`, `updated_by` ;
- `device_id` ;
- `deleted_at` (suppression logique).

Sur le téléphone s'ajoutent `sync_status` (`local`, `en_attente`, `synchronise` ou `conflit`), `base_version` et `portee_etablissement_id`.

### 2.3 Tables

| Domaine | Tables |
| --- | --- |
| Référentiels | `annee_scolaire`, `etablissement`, `classe`, `pathologie`, `critere_inspection`, `parametre` |
| Comptes | `role`, `role_permission`, `utilisateur` |
| Élèves | `eleve`, `inscription`, `import_lot`, `import_ligne` |
| Visites | `visite`, `antecedent`, `examen_appareil`, `visite_pathologie`, `consentement`, `photo` |
| Inspections | `inspection`, `inspection_reponse`, `inspection_photo` |
| Poste seulement | `appareil`, `appareil_etablissement`, `appairage_code`, `conflit`, `journal_sync`, `sync_changement`, `sync_generation`, `schema_migration` |
| Traçabilité | `journal_audit` (écrit sur le téléphone et sur le poste) |

### 2.4 Diffusion des tables

Chaque table du registre indique si le téléphone peut l'**envoyer** et s'il la **reçoit** :

- les référentiels et les comptes sont reçus par tous les téléphones ;
- les tables rattachées à un établissement ne sont reçues que par les téléphones affectés à cet établissement ;
- les examens, les pathologies dépistées, les consentements et les photos ne sont jamais renvoyés aux autres téléphones. Ils se consultent sur le poste central.

### 2.5 Mises à jour du schéma (poste)

`MigrationsPoste` (`sssu_windows/lib/donnees/migrations.dart`) applique au démarrage, dans l'ordre et une seule fois chacun, les fichiers `sql/postgres/NNN_*.sql`. Ils sont installés dans `{app}\sql`. La table `schema_migration` garde leur nom et leur empreinte.

| Fichier | Rôle |
| --- | --- |
| `001_schema.sql` | Schéma complet |
| `002_referentiels.sql` | Rôles et droits, pathologies, grille d'inspection, paramètres par défaut. Idempotent. |
| `020_phase6.sql` | Génération de synchronisation et recherche sans accents (extension `unaccent`, fonction `sssu_sans_accents`) |
| `010_initialiser_journal_sync.sql` | Outil manuel, après un chargement SQL direct de données (jeu de test). Jamais appliqué automatiquement. |

Un nouveau fichier doit être **idempotent** si possible (`IF NOT EXISTS`, `ON CONFLICT DO NOTHING`).

## 3. Synchronisation

### 3.1 Appairage et authentification

1. Sur le poste, l'administrateur prépare un appairage. Le QR code contient :
   - l'URL locale du poste, et son URL Internet si elle est configurée ;
   - l'**empreinte SHA-256 du certificat** du poste ;
   - l'identifiant de l'appareil ;
   - un code à usage unique, valable 10 minutes.
2. Le téléphone génère une paire de clés **Ed25519**. Il garde la graine dans le Keystore Android et envoie la clé publique.
3. À chaque synchronisation, le téléphone demande un **jeton** :
   - la demande est signée, avec un horodatage (écart toléré : ±5 minutes) et un nonce unique (pas de rejeu) ;
   - le jeton vaut 1 heure ;
   - il porte la **génération** des données du poste (voir 3.6).
4. Toute connexion est en HTTPS, avec le certificat auto-signé du poste. Le téléphone le reconnaît par son empreinte (épinglage) : un autre certificat est refusé.

### 3.2 Envoi

- Le téléphone envoie ses enregistrements `en_attente` par lots de 200, parents avant enfants (ordre du registre).
- Le poste contrôle chaque enregistrement :
  - table autorisée à l'envoi ;
  - données valides ;
  - établissement affecté au téléphone ;
  - auteur actif, avec les droits nécessaires (`permissionsEnvoi`) ;
  - règles propres aux visites.
- Le poste applique ensuite les règles de `decider()` (`resolution_conflits.dart`) :

| Situation | Décision |
| --- | --- |
| Inconnu du poste | Accepté (création) |
| Contenu identique à celui du poste | « Déjà reçu » (accusé perdu puis renvoi) |
| Visite validée | Refusée |
| `base_version` égale à la version du poste | Accepté (modification normale) |
| Supprimé d'un côté, modifié de l'autre | Conflit `suppression_modification` |
| Autre | Conflit `modification_concurrente` |

- Le poste détecte aussi :
  - les **doublons probables** (même matricule ; deux visites le même jour pour un élève) : enregistrement accepté, mais conflit signalé ;
  - les **unicités** (inscription unique par année…) : conflit `unicite`.
- Un conflit ne perd aucune donnée :
  - la version du téléphone est gardée dans `conflit.version_appareil`, et le téléphone garde la sienne en état `conflit` ;
  - la décision du Médecin-Chef est diffusée avec le motif `resolution_conflit`, et elle seule remplace la version locale.

### 3.3 Réception

- `sync_changement` est un journal ordonné (`seq`) : table, enregistrement, établissement (portée), version.
- Le téléphone demande les changements postérieurs à son **curseur**, par pages. Il les applique dans une transaction, avec les clés étrangères différées, puis avance le curseur.
- Une modification locale non transmise n'est jamais écrasée.
- Quand un téléphone reçoit un nouvel établissement, ou quand un élève change d'établissement, ses données sont rediffusées (parents d'abord).

### 3.4 Fichiers

Les photos (`photo`, `inspection_photo`) partent après leurs données :

- en morceaux de 512 Kio, au plus 15 Mio par fichier ;
- avec reprise après coupure : seuls les morceaux manquants sont renvoyés ;
- avec contrôle SHA-256.

Le poste chiffre le fichier (AES-256-GCM) et passe la photo à `confirme`. Le téléphone efface alors sa copie.

### 3.5 Trouver le poste

Le téléphone essaie, dans l'ordre :

1. la dernière adresse locale qui a répondu ;
2. une **diffusion UDP** sur le port 8444. La question est `SSSU-SAJ-VMS?v1` ; la réponse donne le port et l'empreinte, et le téléphone la vérifie ;
3. l'adresse Internet.

La synchronisation automatique se déclenche au retour du réseau et toutes les 15 minutes, tant que l'application est ouverte.

### 3.6 Reprise après restauration

Une restauration ramène la base du poste à la date de la sauvegarde. Elle donne aussi une **nouvelle génération** (`sync_generation`). Quand un téléphone voit la génération changer :

1. il remet « en attente » tout ce qu'il a de synchronisé dans les tables qu'il peut envoyer ;
2. il le renvoie avec l'indicateur `reprise`. Le poste garde la version la plus récente ; un enregistrement repris garde son numéro de version, pour qu'une copie plus ancienne détenue par un autre téléphone soit reconnue comme telle ;
3. il recharge tout depuis le curseur 0.

Les copies que le poste ne reprend pas sont simplement remises à jour par la réception complète. C'est le cas, par exemple, d'un enregistrement créé sur le poste sans auteur.

Les téléphones appairés après la date de la sauvegarde ne sont plus connus du poste. Ils proposent un nouvel appairage et gardent leurs données.

## 4. Sécurité et protection des données

### 4.1 Mesures

| Risque | Mesure |
| --- | --- |
| Accès non autorisé | Comptes nominatifs, mots de passe hachés en **Argon2id** (19 Mio, 2 passes), 8 caractères au moins avec lettres et chiffres, blocage 15 minutes après 5 échecs, mot de passe temporaire à changer. PIN à 6 chiffres sur le téléphone (Argon2id). Verrouillage automatique (paramètres). |
| Droits | Matrice rôles × permissions en base (`role_permission`), contrôlée sur le poste **et** à la réception des envois. L'administrateur n'a aucun accès médical. Listes et fiches nominatives réservées au droit `rapport.exporter_nominatif` ; photos au droit `photo.voir_toutes`. |
| Perte ou vol d'un téléphone | Base SQLCipher (clé de 256 bits dans le Keystore) ; photos chiffrées AES-256-GCM, hors galerie ; captures d'écran interdites (`FLAG_SECURE`) ; pas de sauvegarde cloud Android ; **blocage à distance avec effacement** à la connexion suivante. |
| Interception | HTTPS seul (`usesCleartextTraffic=false`) ; certificat épinglé ; jetons signés Ed25519 ; anti-rejeu. |
| Vol du disque du poste | Clé des photos, clé privée du certificat et clé des sauvegardes protégées par **DPAPI** (portée ordinateur) ; base PostgreSQL accessible seulement depuis la machine (`localhost`, scram-sha-256) ; dossier de la base réservé au service. BitLocker recommandé. |
| Perte de données | Sauvegarde quotidienne chiffrée (§ 5) ; synchronisation idempotente ; reprise après restauration ; aucune donnée en conflit n'est écrasée. |
| Traçabilité | `journal_audit` : connexions et échecs, consultations de dossiers et de photos, créations, modifications, suppressions, exports, sauvegardes, restaurations. Les empreintes de mots de passe n'y figurent jamais. `journal_sync` : chaque échange des téléphones. |

### 4.2 Loi n° 2013-450 relative à la protection des données à caractère personnel

L'application facilite le respect de la loi. Elle ne dispense pas le service de ses obligations. À vérifier avec le responsable du traitement :

1. **Formalités préalables** auprès de l'autorité de protection, l'ARTCI. Les données de santé sont des données sensibles : vérifier le régime applicable (autorisation ou déclaration) avant la mise en service.
2. **Finalité** : visites médicales systématiques et suivi sanitaire scolaire. Aucune autre utilisation.
3. **Minimisation** : seules les données utiles à la visite sont collectées. Les photographies n'existent qu'avec un consentement enregistré.
4. **Information et droits** : information des parents ; droit d'accès et de rectification exercé auprès du Médecin-Chef (consultation et correction du dossier sur le poste, fiche individuelle).
5. **Durée de conservation** : à fixer par le service. L'archivage des années scolaires et des établissements est prévu ; la purge définitive n'est pas automatisée.
6. **Sécurité et confidentialité** : mesures du § 4.1. Le personnel est tenu au secret ; les comptes sont personnels.
7. **Sous-traitance** : aucune donnée ne quitte les équipements du service. Pas de serveur externe : le poste est le serveur.

## 5. Sauvegarde et restauration

- **Contenu** :
  - export PostgreSQL (`pg_dump -Fc`) ;
  - photos (déjà chiffrées) ;
  - clé des photos, certificat et sa clé privée, pour une restauration sur un autre PC ;
  - manifeste : date, poste, migrations, empreinte de la base, nombre de photos.
- **Format `.sssubak`** (`archive_chiffree.dart`) :
  - en-tête en clair : sel et paramètres Argon2id (64 Mio, 3 passes), contrôle de la phrase ;
  - corps : blocs AES-256-GCM de 1 Mio ;
  - le numéro de chaque bloc et l'indicateur « dernier » sont authentifiés : modification, réordonnancement ou troncature sont détectés ;
  - écriture et lecture en flux : la mémoire utilisée ne dépend pas de la taille.
- **Clé** :
  - elle est dérivée de la phrase de passe choisie par l'administrateur ;
  - elle est gardée sur le poste, protégée par DPAPI, pour les sauvegardes automatiques ;
  - une restauration exige de ressaisir la phrase.
- **Planification** :
  - une vérification par minute, une sauvegarde par jour à l'heure choisie ;
  - rattrapage au démarrage, nouvel essai une heure après un échec ;
  - conservation des N dernières (14 par défaut) ; les sauvegardes « avant restauration » ne sont pas comptées.
- **Restauration** :
  1. déchiffrement et contrôle complet ;
  2. sauvegarde de sécurité de l'état actuel ;
  3. chargement dans une **base neuve** (`pg_restore --single-transaction`), puis échange par renommage. L'ancienne base est gardée sous le nom `sssu_saj_avant_<horodatage>` : seule la dernière est conservée ;
  4. remise en place des photos et des clés ;
  5. nouvelle génération et trace dans l'audit ;
  6. redémarrage de l'application.

  Le compte `sssu` a le droit `CREATEDB` à cet effet.

## 6. Statistiques et rapports

- **Calcul** : `calculerStatistiques` (`sssu_core/lib/src/statistiques/`) calcule en mémoire à partir d'un `JeuStatistiques`. Ce jeu est lu en une requête par table, par `SourceStatistiquesPoste` (PostgreSQL) ou par `Requetes.jeuStatistiques` (SQLite, données de l'appareil). Les définitions sont en tête du fichier :
  - un élève est examiné s'il a au moins une visite autre qu'une ébauche dans l'année ou dans la période ;
  - la prévalence vaut cas / examinés ;
  - la conclusion et la tranche d'âge sont celles de la dernière visite ;
  - pour chaque établissement, c'est la dernière inspection qui compte.
- **Rapports** : `rapports/rapports.dart` compose des `DocumentRapport` (en-tête, blocs). `rendu_pdf.dart` (paquet `pdf`, police DejaVu Sans livrée) et `rendu_excel.dart` (nombres restés numériques) les rendent. Les droits sont contrôlés à la composition.

## 7. Configuration du poste

Le fichier `C:\ProgramData\SSSU-SAJ VMS\sssu_config.json` est créé par l'installateur :

```json
{
  "postgres": { "hote": "localhost", "port": 5433, "base": "sssu_saj", "utilisateur": "sssu",
                "mot_de_passe": "…", "bin": "C:\\Program Files\\SSSU-SAJ VMS\\pgsql\\bin" },
  "port_api": 8443,
  "dossier_sql": "C:\\Program Files\\SSSU-SAJ VMS\\sql",
  "tesseract": "C:\\Program Files\\SSSU-SAJ VMS\\tesseract\\tesseract.exe",
  "adresse_internet": null,
  "nom_poste": "SSSU-SAJ Kouassi-Kouassikro"
}
```

Le même dossier contient aussi :

- `photos/` ;
- `cle_photos.bin`, `certificat.pem` et `cle_privee.pem` (protégés par DPAPI) ;
- `sauvegarde.json`, `cle_sauvegarde.bin` et `sauvegardes/` ;
- `pgdata/`, la base, réservée au service PostgreSQL ;
- `admin/`, avec le mot de passe du super-utilisateur PostgreSQL.

## 8. Tests

```
cd sssu_core && dart test --concurrency=1
cd sssu_mobile && flutter pub get && dart run build_runner build && flutter test
cd sssu_windows && SSSU_PG_TEST_URL=postgres://sssu:…@localhost:5432/sssu_saj_test SSSU_PG_BIN=/usr/lib/postgresql/16/bin \
  flutter test --concurrency=1
```

La base de test se prépare ainsi :

1. créez la base ; le compte doit avoir `CREATEDB` pour le test de restauration ;
2. chargez `001_schema.sql`, `sql/seed/donnees_test.sql` et `010_initialiser_journal_sync.sql` ;
3. les tests appliquent eux-mêmes les autres mises à jour.

L'intégration continue (`.github/workflows/livraison.yml`) fait tout cela. Elle construit aussi les installables sur une étiquette `v*`.

| Fichier de tests | Contenu |
| --- | --- |
| `sssu_core/test/phase6_test.dart` | 5 téléphones sur 2 établissements, travail hors ligne, accusé perdu, réception interrompue, modification concurrente, reprise après restauration (3 téléphones dont une copie ancienne), sécurité des envois et de la diffusion |
| `deux_telephones_test.dart` | Échanges HTTP réels : lots, conflit, photos par morceaux, découverte UDP |
| `appairage_test.dart`, `auth_test.dart` | Code d'appairage, jetons (signature, rejeu, horloge, expiration, blocage), mots de passe, PIN, verrouillage |
| `sssu_windows/test/phase6_test.dart` | Archive chiffrée (aller-retour, clé fausse, altération, troncature, nom dangereux), planification, migrations, recherche sans accents, **sauvegarde puis restauration réelles** sur PostgreSQL |
| Autres | Règles métier, import, visites, gestion, statistiques, rapports, inspection, photos, SQLite réel |

## 9. Exploitation et dépannage

| Symptôme | Vérification |
| --- | --- |
| « Poste central introuvable » sur les téléphones | Même Wi-Fi ? Réseau Windows « Privé » ? Règles de pare-feu 8443/8444 présentes (`wf.msc`) ? Application du poste ouverte ? |
| L'application du poste ne démarre pas | Service `SSSU-SAJ-PostgreSQL` démarré (`services.msc`) ; journaux dans `pgdata\log` ; message affiché au démarrage (chemin de la configuration). |
| « Mise à jour de la base impossible » | Fichier SQL en cause indiqué dans le message ; la base n'est pas modifiée par ce fichier (transaction). |
| Sauvegarde en échec | Message sur la page Sauvegardes : dossier inaccessible (disque débranché ?), `pg_dump` introuvable (champ `bin` de la configuration). |
| Téléphone « non reconnu » | Restauration d'une sauvegarde antérieure à son appairage : nouvel appairage, données gardées. |
| Changement de PC | Installer le nouveau PC, puis restaurer la dernière sauvegarde (phrase de passe). Les téléphones gardent le même certificat épinglé et retrouvent le poste sur le Wi-Fi. |
