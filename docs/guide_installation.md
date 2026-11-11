# SSSU-SAJ VMS — Guide d'installation

Ce guide s'adresse à la personne qui installe le système au service SSSU-SAJ. Aucune connaissance informatique particulière n'est nécessaire.

## 1. Ce qu'il faut

| Élément | Exigence |
| --- | --- |
| Poste central | PC Windows 10 ou 11, 64 bits, 8 Go de RAM conseillés, 20 Go libres. Il doit être **réservé au personnel autorisé** et protégé par un mot de passe Windows. BitLocker est recommandé. |
| Réseau du bureau | Un routeur ou un point d'accès Wi-Fi. Le poste et les téléphones doivent être sur **le même Wi-Fi**. Internet n'est pas nécessaire. |
| Téléphones | Android 8.0 ou plus récent, 2 Go de RAM, appareil photo. |
| Sauvegardes | Un disque externe USB, ou un dossier réseau. |
| Fichiers | `SSSU-SAJ-VMS-Poste-<version>.exe` (poste) et `SSSU-SAJ-VMS-<version>.apk` (téléphones). Pour les produire, voir le chapitre 7. |

## 2. Installer le poste central

1. Connectez-vous à Windows avec un compte **administrateur**.
2. Lancez `SSSU-SAJ-VMS-Poste-<version>.exe`, puis suivez l'assistant (Suivant, Installer). L'installation dure quelques minutes. Elle installe et configure **automatiquement** :
   - l'application ;
   - la base de données PostgreSQL 16. C'est un service Windows qui démarre avec l'ordinateur, et seul le poste peut y accéder ;
   - Tesseract avec la langue française, pour lire les listes scannées ;
   - le runtime Visual C++ ;
   - le pare-feu : port 8443 (synchronisation) et port 8444 (recherche du poste sur le Wi-Fi), sur les réseaux privés seulement ;
   - le dossier de données `C:\ProgramData\SSSU-SAJ VMS`. Il contient la base, les photos, les clés, la configuration et les sauvegardes.
3. À la fin, laissez cochée la case « Lancer SSSU-SAJ VMS ».

En cas de problème, le journal de l'installation se trouve dans `C:\ProgramData\SSSU-SAJ VMS\installation.log`.

Dans Windows, le réseau Wi-Fi du bureau doit être de type **« Privé »** (Paramètres > Réseau > Propriétés). Sur un réseau « Public », les téléphones ne trouveront pas le poste.

## 3. Premier lancement du poste

1. L'application prépare la base. Elle crée les tables, la liste des pathologies, la grille d'inspection et les paramètres.
2. Elle demande de **créer le compte administrateur** : identifiant, nom, mot de passe d'au moins 8 caractères, avec lettres et chiffres.
3. Dans **Paramètres** :
   - complétez l'en-tête des rapports et le nom du Médecin-Chef ;
   - ajoutez le logo du SSSU-SAJ.
4. Dans **Sauvegardes** (ces réglages sont indispensables) :
   - **définissez la phrase de passe** des sauvegardes. Écrivez-la sur papier et rangez-la sous clé, hors du bureau : sans elle, une sauvegarde ne peut pas être restaurée sur un autre PC ;
   - choisissez le **dossier**, de préférence le disque externe, puis l'heure de la sauvegarde quotidienne ;
   - cliquez « Sauvegarder maintenant », puis « Vérifier » sur la sauvegarde obtenue.
5. Dans **Comptes**, créez les comptes : Médecin-Chef, médecins, infirmiers, agents.
6. Dans **Établissements**, créez l'année scolaire et les établissements, ou importez les listes.

## 4. Installer et appairer les téléphones

1. Copiez l'APK sur le téléphone, ouvrez-le et autorisez l'installation quand Android le demande.
2. Sur le poste, ouvrez **Téléphones**, puis « Appairer un téléphone ». Indiquez le nom de l'appareil et les établissements dont il s'occupe : un **QR code** s'affiche, valable 10 minutes.
3. Sur le téléphone, ouvrez l'application et lisez le QR code. La première synchronisation charge les comptes, les établissements et les élèves.
4. L'agent se connecte avec son identifiant et son mot de passe. Il choisit ensuite un **code PIN** de 6 chiffres pour déverrouiller l'application rapidement.

## 5. Synchronisation par Internet (facultatif)

Elle permet aux équipes de synchroniser sans revenir au bureau. Il faut :

1. une **adresse fixe** sur Internet pour le bureau, ou un nom DynDNS (par exemple `sssu-saj.ddns.net`) ;
2. dans le routeur, une **redirection** du port TCP 8443 vers le poste central. Donnez au poste une adresse IP fixe sur le réseau local ;
3. dans `C:\ProgramData\SSSU-SAJ VMS\sssu_config.json`, la ligne `"adresse_internet": "https://sssu-saj.ddns.net:8443"`, puis un redémarrage de l'application ;
4. pour les téléphones appairés par QR code avant ce réglage, un nouvel appairage, pour qu'ils reçoivent cette adresse.

Avec cette adresse, les agents peuvent aussi **enregistrer un téléphone sans QR code**, depuis le terrain,
avec leur identifiant et leur mot de passe ; l'administrateur l'accepte ensuite sur le poste (page
Téléphones). Donnez l'adresse aux agents, pas par écrit public.

La connexion reste chiffrée. Les téléphones n'acceptent que le certificat du poste, reconnu par son
empreinte : lue dans le QR code, ou, sans QR code, retenue au premier contact après vérification du code de
sécurité par l'agent. Le poste exposé sur Internet reçoit des tentatives de connexion : les comptes se
bloquent 15 minutes après 5 mots de passe faux, et un téléphone enregistré ne reçoit rien tant qu'il n'est
pas accepté. Imposez des mots de passe solides.

## 6. Mises à jour et désinstallation

- **Poste**
  - Lancez le nouvel installateur par-dessus l'ancien. Données, configuration et clés sont conservées.
  - Au lancement, l'application met la base à jour d'elle-même (fichiers `sql\NNN_*.sql`).
  - Faites une sauvegarde juste avant.
- **Téléphones** : installez le nouvel APK par-dessus l'ancien. Il doit avoir la même clé de signature.
- **Désinstallation** (Paramètres Windows > Applications) : elle retire l'application et arrête la base. Les données restent dans `C:\ProgramData\SSSU-SAJ VMS`. Ne supprimez ce dossier que si vous êtes certain de ne plus en avoir besoin.

## 7. Produire les fichiers installables (informaticien)

**Méthode recommandée : GitHub Actions** (`.github/workflows/livraison.yml`).

1. Déposez le code dans un dépôt GitHub privé.
2. Ajoutez les secrets de signature Android (voir `installation/android/LISEZMOI.md`).
3. Créez une étiquette de version :
   ```
   git tag v1.0.0
   git push --tags
   ```
4. Le flux exécute tous les tests, puis construit l'APK signé et l'installateur Windows. Il les joint à une « release » GitHub.

**Méthode locale sur un PC Windows.** Il faut installer Flutter 3.24, Visual Studio 2022 (« Développement Desktop en C++ »), Inno Setup 6, Android Studio et le JDK 17. Ensuite :

```
powershell -ExecutionPolicy Bypass -File installation\windows\construire_poste.ps1 -Version 1.0.0
powershell -ExecutionPolicy Bypass -File installation\android\construire_apk.ps1 -Version 1.0.0
```

`preparer_dependances.ps1` télécharge PostgreSQL 16 (binaires EDB), Tesseract et le runtime Visual C++. Leurs versions sont des paramètres du script : vérifiez les dernières versions publiées avant une livraison.

## 8. Informations techniques utiles

| Élément | Valeur |
| --- | --- |
| Base de données | PostgreSQL 16, service `SSSU-SAJ-PostgreSQL`, port 5433, base `sssu_saj`, compte `sssu` |
| Mot de passe du super-utilisateur PostgreSQL | `C:\ProgramData\SSSU-SAJ VMS\admin\postgres_superutilisateur.txt` (lisible par les administrateurs seulement) |
| Configuration | `C:\ProgramData\SSSU-SAJ VMS\sssu_config.json` |
| Synchronisation | HTTPS, port 8443 ; découverte Wi-Fi UDP, port 8444 |
| Journal d'installation | `C:\ProgramData\SSSU-SAJ VMS\installation.log` |
