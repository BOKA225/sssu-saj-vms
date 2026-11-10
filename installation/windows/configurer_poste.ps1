<#
  SSSU-SAJ VMS - configuration du poste central (lancée par l'installateur,
  avec les droits d'administrateur). Idempotente : une réinstallation ou une
  mise à jour garde la base, les photos, les clés et la configuration.

  1. Dossier de données : %ProgramData%\SSSU-SAJ VMS
  2. PostgreSQL 16 (binaires fournis) : initialisation de la base, service
     Windows « SSSU-SAJ-PostgreSQL » (démarrage automatique), écoute
     uniquement sur la machine (localhost), authentification scram-sha-256.
  3. Compte « sssu » (mots de passe aléatoires) et base « sssu_saj ».
     Le schéma est créé par l'application à son premier lancement.
  4. Configuration sssu_config.json.
  5. Pare-feu : HTTPS 8443 (TCP) et découverte 8444 (UDP), réseaux privés.
#>
param(
  [Parameter(Mandatory = $true)][string]$DossierApplication,
  [int]$PortPostgres = 5433,
  [int]$PortApi = 8443,
  [int]$PortDecouverte = 8444
)

$ErrorActionPreference = 'Stop'
$journal = Join-Path $env:ProgramData 'SSSU-SAJ VMS\installation.log'
New-Item -ItemType Directory -Force -Path (Split-Path $journal) | Out-Null
function Noter([string]$m) { $l = "$(Get-Date -Format s)  $m"; Write-Host $l; Add-Content -Path $journal -Value $l -Encoding UTF8 }

function MotDePasseAleatoire([int]$n = 32) {
  $o = New-Object byte[] $n
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($o)
  return ([Convert]::ToBase64String($o) -replace '[+/=]', 'x').Substring(0, $n)
}

try {
  $donnees = Join-Path $env:ProgramData 'SSSU-SAJ VMS'
  $pgBin = Join-Path $DossierApplication 'pgsql\bin'
  $pgData = Join-Path $donnees 'pgdata'
  $config = Join-Path $donnees 'sssu_config.json'
  $secret = Join-Path $donnees 'admin'
  $service = 'SSSU-SAJ-PostgreSQL'
  Noter "Configuration du poste central (application : $DossierApplication)"

  # 1. Dossiers et droits : administrateurs et système en contrôle total,
  #    utilisateurs de l'ordinateur en modification (le poste doit être
  #    réservé au personnel autorisé). Aucun accès pour le reste.
  foreach ($d in @($donnees, (Join-Path $donnees 'sauvegardes'), $secret)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
  & icacls $donnees /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)M' | Out-Null
  & icacls $secret /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' | Out-Null

  # 2. PostgreSQL.
  if (-not (Test-Path (Join-Path $pgBin 'pg_ctl.exe'))) { throw "Binaires PostgreSQL absents : $pgBin" }
  $fichierSuper = Join-Path $secret 'postgres_superutilisateur.txt'
  if (-not (Test-Path (Join-Path $pgData 'PG_VERSION'))) {
    Noter 'Initialisation de la base PostgreSQL'
    $super = MotDePasseAleatoire
    Set-Content -Path $fichierSuper -Value $super -NoNewline -Encoding ASCII
    $pw = Join-Path $env:TEMP "sssu_pw_$([guid]::NewGuid()).txt"
    Set-Content -Path $pw -Value $super -NoNewline -Encoding ASCII
    try {
      & (Join-Path $pgBin 'initdb.exe') -D $pgData -U postgres --pwfile=$pw -A scram-sha-256 -E UTF8 --locale=C | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "initdb a échoué (code $LASTEXITCODE)" }
    } finally { Remove-Item $pw -Force -ErrorAction SilentlyContinue }
    Add-Content -Path (Join-Path $pgData 'postgresql.conf') -Encoding ASCII -Value @"

# --- SSSU-SAJ VMS ---
listen_addresses = 'localhost'
port = $PortPostgres
max_connections = 50
shared_buffers = 256MB
timezone = 'UTC'
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_rotation_age = 7d
"@
    # Fichiers de la base : service PostgreSQL (« Service réseau »), système et
    # administrateurs uniquement ; les utilisateurs n'y ont pas accès.
    & icacls $pgData /inheritance:r /grant:r '*S-1-5-20:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
  } else {
    Noter 'Base PostgreSQL déjà initialisée : conservée'
    $super = Get-Content $fichierSuper -Raw
  }

  if (-not (Get-Service -Name $service -ErrorAction SilentlyContinue)) {
    Noter "Enregistrement du service $service"
    & (Join-Path $pgBin 'pg_ctl.exe') register -N $service -D $pgData -S auto -U 'NT AUTHORITY\NetworkService' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Enregistrement du service impossible (code $LASTEXITCODE)" }
  }
  Start-Service -Name $service
  $ok = $false
  for ($i = 0; $i -lt 30 -and -not $ok; $i++) {
    & (Join-Path $pgBin 'pg_isready.exe') -h localhost -p $PortPostgres | Out-Null
    $ok = ($LASTEXITCODE -eq 0); if (-not $ok) { Start-Sleep -Seconds 1 }
  }
  if (-not $ok) { throw 'PostgreSQL ne répond pas après 30 secondes.' }

  # 3. Compte et base de l'application.
  $env:PGPASSWORD = $super
  $psql = Join-Path $pgBin 'psql.exe'
  $existe = & $psql -h localhost -p $PortPostgres -U postgres -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'sssu'"
  if (Test-Path $config) {
    $mdp = (Get-Content $config -Raw | ConvertFrom-Json).postgres.mot_de_passe
  } else {
    $mdp = MotDePasseAleatoire
  }
  if ($existe -ne '1') {
    Noter 'Création du compte « sssu »'
    & $psql -h localhost -p $PortPostgres -U postgres -d postgres -v ON_ERROR_STOP=1 -c "CREATE ROLE sssu LOGIN CREATEDB PASSWORD '$mdp'" | Out-Null
  } elseif (-not (Test-Path $config)) {
    & $psql -h localhost -p $PortPostgres -U postgres -d postgres -v ON_ERROR_STOP=1 -c "ALTER ROLE sssu WITH LOGIN CREATEDB PASSWORD '$mdp'" | Out-Null
  }
  $base = & $psql -h localhost -p $PortPostgres -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = 'sssu_saj'"
  if ($base -ne '1') {
    Noter 'Création de la base « sssu_saj »'
    & $psql -h localhost -p $PortPostgres -U postgres -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE sssu_saj OWNER sssu TEMPLATE template0 ENCODING 'UTF8'" | Out-Null
  }
  Remove-Item Env:\PGPASSWORD

  # 4. Configuration (gardée lors d'une mise à jour, chemins actualisés).
  if (Test-Path $config) {
    $c = Get-Content $config -Raw | ConvertFrom-Json
    $c.postgres.bin = $pgBin
    $c.dossier_sql = (Join-Path $DossierApplication 'sql')
    $c.tesseract = (Join-Path $DossierApplication 'tesseract\tesseract.exe')
    Noter 'Configuration existante mise à jour (chemins)'
  } else {
    $c = [ordered]@{
      postgres          = [ordered]@{ hote = 'localhost'; port = $PortPostgres; base = 'sssu_saj'; utilisateur = 'sssu'; mot_de_passe = $mdp; bin = $pgBin }
      port_api          = $PortApi
      dossier_sql       = (Join-Path $DossierApplication 'sql')
      tesseract         = (Join-Path $DossierApplication 'tesseract\tesseract.exe')
      adresse_internet  = $null
      nom_poste         = 'SSSU-SAJ Kouassi-Kouassikro'
    }
    Noter 'Configuration créée'
  }
  $json = $c | ConvertTo-Json -Depth 5
  [System.IO.File]::WriteAllText($config, $json, (New-Object System.Text.UTF8Encoding $false))

  # 5. Pare-feu (réseaux privés : Wi-Fi du bureau).
  foreach ($r in @(
      @{ Nom = 'SSSU-SAJ VMS - synchronisation (HTTPS)'; Proto = 'TCP'; Port = $PortApi },
      @{ Nom = 'SSSU-SAJ VMS - découverte Wi-Fi'; Proto = 'UDP'; Port = $PortDecouverte })) {
    if (-not (Get-NetFirewallRule -DisplayName $r.Nom -ErrorAction SilentlyContinue)) {
      New-NetFirewallRule -DisplayName $r.Nom -Direction Inbound -Action Allow -Protocol $r.Proto -LocalPort $r.Port -Profile Private, Domain | Out-Null
      Noter "Pare-feu : $($r.Nom) ouvert"
    }
  }
  Noter 'Configuration terminée.'
  exit 0
} catch {
  Noter "ERREUR : $($_.Exception.Message)"
  exit 1
}
