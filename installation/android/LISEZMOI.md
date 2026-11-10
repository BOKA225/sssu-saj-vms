# Construire et diffuser l'application Android

## Construire

```
cd installation/android
./construire_apk.sh 1.0.0 1          # Linux / macOS
powershell -File construire_apk.ps1   # Windows
```

Le script :

1. génère le projet Android s'il n'existe pas (`flutter create`) ;
2. le configure avec `configurer_android.dart` : minimum Android 8.0, permissions, captures d'écran interdites, pas de sauvegarde cloud, HTTPS seul ;
3. génère le code drift (`build_runner`) ;
4. construit l'APK signé.

L'APK est produit dans `installation/android/sortie/`.

## Clé de signature (une fois, à conserver précieusement)

Toutes les mises à jour de l'application doivent être signées avec **la même clé**. Si la clé est perdue, il faut désinstaller l'application des téléphones (les données non synchronisées seraient perdues) pour installer une nouvelle version.

```
keytool -genkeypair -v -keystore sssu-saj.jks -alias sssu-saj -keyalg RSA -keysize 4096 -validity 10000
```

Ensuite, créez `sssu_mobile/android/key.properties`. Ne l'ajoutez **jamais** au dépôt Git.

```
storePassword=…
keyPassword=…
keyAlias=sssu-saj
storeFile=/chemin/vers/sssu-saj.jks
```

## Installer sur les téléphones

- **Téléphones concernés** : Android 8.0 ou plus récent, 2 Go de RAM.
- **Installation** : copiez l'APK sur le téléphone (câble USB ou partage), puis ouvrez-le. Autorisez « Installer des applications inconnues » pour le gestionnaire de fichiers quand Android le demande.
- **Mise à jour** : installez le nouvel APK par-dessus l'ancien. Les données sont conservées si la clé de signature est la même.
- **Premier lancement** : lisez le QR code d'appairage affiché par le poste central (menu Téléphones).
