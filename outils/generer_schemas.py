"""Génère, à partir d'une seule spécification :
- sssu_mobile/lib/data/tables.drift (SQLite / drift)
- sql/postgres/001_schema.sql (PostgreSQL)
- sssu_core/lib/src/schema/registre.dart (registre des tables pour la synchronisation)
"""
import os, sys

ROOT = sys.argv[1]

# type -> (sqlite, postgres)
TYPES = {
    'uuid': ('TEXT', 'UUID'),
    'text': ('TEXT', 'TEXT'),
    'int': ('INTEGER', 'INTEGER'),
    'real': ('REAL', 'DOUBLE PRECISION'),
    'bool': ('BOOLEAN', 'BOOLEAN'),
    'ts': ('DATETIME', 'TIMESTAMPTZ'),
    'date': ('TEXT', 'DATE'),
    'json': ('TEXT', 'JSONB'),
    'blob': ('BLOB', 'BYTEA'),
}
DART_TYPE = {'uuid': 'uuid', 'text': 'text', 'int': 'entier', 'real': 'reel', 'bool': 'booleen',
             'ts': 'horodatage', 'date': 'date', 'json': 'json', 'blob': 'binaire'}


def c(name, typ, nn=False, default=None, check=None, fk=None, sqlite_fk=True):
    return dict(name=name, typ=typ, nn=nn, default=default, check=check, fk=fk, sqlite_fk=sqlite_fk)


def enum(name, values, nn=True, default=None):
    vals = ', '.join(f"'{v}'" for v in values)
    return c(name, 'text', nn=nn, default=default, check=f"{name} IN ({vals})")


ROLES = ['admin', 'medecin_chef', 'medecin', 'infirmier', 'agent']
APPAREILS_EXAMEN = ['general', 'dermatologique', 'orl', 'ophtalmologique', 'bucco_dentaire', 'cardiovasculaire',
                    'respiratoire', 'digestif', 'neurologique', 'osteo_articulaire', 'genito_urinaire']
RUBRIQUES = ['eau_potable', 'toilettes', 'lavage_mains', 'dechets', 'environnement', 'cantine', 'vendeuses',
             'infirmerie', 'securite']

# where: 'both' | 'pg' | 'sqlite'
# push: le téléphone peut envoyer ; pull: le téléphone reçoit ; scope: 'etab' | None ; ordre : ordre d'envoi
T = []


def table(name, row, cols, where='both', push=False, pull=False, scope=None, ordre=0, uniques=(), indexes=(),
          checks=(), natural=None):
    T.append(dict(name=name, row=row, cols=cols, where=where, push=push, pull=pull, scope=scope, ordre=ordre,
                  uniques=list(uniques), indexes=list(indexes), checks=list(checks),
                  natural=list(uniques) if natural is None else natural))


table('annee_scolaire', 'AnneeScolaireRow', [
    c('libelle', 'text', nn=True), c('date_debut', 'date', nn=True), c('date_fin', 'date', nn=True),
    c('active', 'bool', nn=True, default='FALSE')],
    pull=True, uniques=[('libelle',)], checks=['date_fin > date_debut'])

table('etablissement', 'EtablissementRow', [
    c('nom', 'text', nn=True), c('code', 'text', nn=True),
    enum('type', ['prescolaire', 'primaire', 'secondaire', 'technique', 'superieur']),
    enum('statut', ['public', 'prive']),
    c('region', 'text'), c('district_sanitaire', 'text'), c('localite', 'text'),
    c('responsable', 'text'), c('telephone', 'text')],
    pull=True, scope='etab', uniques=[('code',)])

table('classe', 'ClasseRow', [
    c('etablissement_id', 'uuid', nn=True, fk='etablissement'),
    c('annee_scolaire_id', 'uuid', nn=True, fk='annee_scolaire'),
    c('libelle', 'text', nn=True), c('niveau', 'text')],
    push=True, pull=True, scope='etab', ordre=5, uniques=[('etablissement_id', 'annee_scolaire_id', 'libelle')])

table('role', 'RoleRow', [enum('code', ROLES), c('libelle', 'text', nn=True)],
      pull=True, uniques=[('code',)])

table('role_permission', 'RolePermissionRow', [
    c('role_id', 'uuid', nn=True, fk='role'), c('permission', 'text', nn=True)],
    pull=True, uniques=[('role_id', 'permission')])

table('utilisateur', 'UtilisateurRow', [
    c('identifiant', 'text', nn=True), c('nom', 'text', nn=True), c('prenoms', 'text'),
    c('fonction', 'text'), c('structure', 'text'),
    c('role_id', 'uuid', nn=True, fk='role'),
    c('hash_mot_de_passe', 'text'), c('hash_pin', 'text'),
    c('actif', 'bool', nn=True, default='TRUE'), c('doit_changer_mdp', 'bool', nn=True, default='TRUE'),
    c('echecs_connexion', 'int', nn=True, default='0'), c('bloque_jusqua', 'ts')],
    pull=True, uniques=[('identifiant',)])

table('eleve', 'EleveRow', [
    c('matricule', 'text'), c('nom', 'text', nn=True), c('prenoms', 'text', nn=True),
    c('date_naissance', 'date'), enum('sexe', ['M', 'F']), c('telephone_contact', 'text')],
    push=True, pull=True, scope='etab', ordre=10,
    indexes=[('nom', 'prenoms'), ('matricule',)], natural=[])

table('inscription', 'InscriptionRow', [
    c('eleve_id', 'uuid', nn=True, fk='eleve'), c('classe_id', 'uuid', nn=True, fk='classe'),
    c('annee_scolaire_id', 'uuid', nn=True, fk='annee_scolaire'),
    enum('statut', ['inscrit', 'transfere', 'sorti'], default="'inscrit'")],
    push=True, pull=True, scope='etab', ordre=20, uniques=[('eleve_id', 'annee_scolaire_id')])

table('appareil', 'AppareilRow', [
    c('nom', 'text', nn=True), c('modele', 'text'), c('cle_publique', 'text'),
    c('titulaire_id', 'uuid', fk='utilisateur'), c('date_appairage', 'ts'),
    c('bloque', 'bool', nn=True, default='FALSE')], where='pg')

table('appareil_etablissement', 'AppareilEtablissementRow', [
    c('appareil_id', 'uuid', nn=True, fk='appareil'),
    c('etablissement_id', 'uuid', nn=True, fk='etablissement')],
    where='pg', uniques=[('appareil_id', 'etablissement_id')])

table('appairage_code', 'AppairageCodeRow', [
    c('appareil_id', 'uuid', nn=True, fk='appareil'), c('code_hash', 'text', nn=True),
    c('expire_le', 'ts', nn=True), c('utilise', 'bool', nn=True, default='FALSE')], where='pg')

table('import_lot', 'ImportLotRow', [
    c('classe_id', 'uuid', fk='classe'), c('utilisateur_id', 'uuid', fk='utilisateur'),
    c('fichier_nom', 'text', nn=True), enum('format', ['xlsx', 'xls', 'csv', 'pdf', 'pdf_ocr', 'image_ocr']),
    c('empreinte_sha256', 'text', nn=True),
    enum('statut', ['brouillon', 'valide', 'annule'], default="'brouillon'"),
    c('nb_lignes', 'int', nn=True, default='0')])

table('import_ligne', 'ImportLigneRow', [
    c('import_lot_id', 'uuid', nn=True, fk='import_lot'), c('numero', 'int', nn=True),
    c('donnees_extraites', 'json', nn=True), c('confiance_ocr', 'real'), c('anomalies', 'json'),
    enum('decision', ['a_verifier', 'garder', 'corriger', 'rejeter'], default="'a_verifier'"),
    c('eleve_id', 'uuid', fk='eleve')],
    uniques=[('import_lot_id', 'numero')])

table('visite', 'VisiteRow', [
    c('eleve_id', 'uuid', nn=True, fk='eleve'), c('inscription_id', 'uuid', fk='inscription'),
    c('agent_id', 'uuid', nn=True, fk='utilisateur'), c('appareil_id', 'uuid'),
    c('validateur_id', 'uuid', fk='utilisateur'),
    c('date_visite', 'date', nn=True), c('structure_origine', 'text'),
    enum('statut', ['ebauche', 'enregistre', 'en_attente', 'synchronise', 'valide'], default="'ebauche'"),
    c('poids_kg', 'real'), c('taille_cm', 'real'), c('imc', 'real'), c('imc_interpretation', 'text'),
    c('ta_sys', 'int'), c('ta_dia', 'int'), c('temperature_c', 'real'), c('fc', 'int'), c('fr', 'int'),
    enum('conclusion', ['sans_anomalie', 'anomalie', 'suivi', 'reference'], nn=False),
    c('diagnostic', 'text'), c('conduite_a_tenir', 'text'), c('traitement_conseils', 'text'),
    c('structure_reference', 'text'), c('date_controle', 'date'), c('observations', 'text'),
    c('valide_le', 'ts')],
    push=True, pull=True, scope='etab', ordre=30,
    indexes=[('eleve_id', 'date_visite'), ('agent_id',), ('inscription_id',)],
    checks=['poids_kg IS NULL OR poids_kg > 0', 'taille_cm IS NULL OR taille_cm > 0'])

table('antecedent', 'AntecedentRow', [
    c('visite_id', 'uuid', nn=True, fk='visite'), c('eleve_id', 'uuid', nn=True, fk='eleve'),
    enum('type', ['personnel', 'chirurgical', 'familial', 'allergique', 'gynecologique', 'traitement']),
    c('coche', 'bool', nn=True, default='FALSE'), c('commentaire', 'text')],
    push=True, pull=True, scope='etab', ordre=40, indexes=[('visite_id',), ('eleve_id',)])

table('examen_appareil', 'ExamenAppareilRow', [
    c('visite_id', 'uuid', nn=True, fk='visite'), enum('appareil', APPAREILS_EXAMEN),
    enum('resultat', ['normal', 'anormal', 'non_examine']), c('observation', 'text')],
    push=True, scope='etab', ordre=40, uniques=[('visite_id', 'appareil')])

table('pathologie', 'PathologieRow', [
    c('code', 'text', nn=True), c('libelle', 'text', nn=True),
    c('active', 'bool', nn=True, default='TRUE'), c('ordre', 'int', nn=True, default='0'),
    c('precision_requise', 'bool', nn=True, default='FALSE')],
    pull=True, uniques=[('code',)])

table('visite_pathologie', 'VisitePathologieRow', [
    c('visite_id', 'uuid', nn=True, fk='visite'), c('pathologie_id', 'uuid', nn=True, fk='pathologie'),
    c('precision', 'text')],
    push=True, scope='etab', ordre=40, uniques=[('visite_id', 'pathologie_id')])

table('consentement', 'ConsentementRow', [
    c('eleve_id', 'uuid', nn=True, fk='eleve'), c('visite_id', 'uuid', fk='visite'),
    enum('type', ['photo'], default="'photo'"), c('obtenu', 'bool', nn=True),
    enum('forme', ['ecrit', 'oral'], nn=False), c('nom_repondant', 'text'), c('lien_parente', 'text'),
    c('date_consentement', 'date', nn=True)],
    push=True, scope='etab', ordre=40, indexes=[('eleve_id',), ('visite_id',)],
    checks=['obtenu = FALSE OR (forme IS NOT NULL AND nom_repondant IS NOT NULL)'])

PHOTO_COLS = [c('chemin_chiffre', 'text', nn=True), c('empreinte_sha256', 'text', nn=True),
              c('taille_octets', 'int', nn=True), c('largeur', 'int'), c('hauteur', 'int'),
              c('commentaire', 'text'), c('pris_le', 'ts', nn=True),
              enum('statut_transfert', ['en_attente', 'transfere', 'confirme'], default="'en_attente'")]

table('photo', 'PhotoRow', [
    c('visite_id', 'uuid', nn=True, fk='visite'), c('eleve_id', 'uuid', nn=True, fk='eleve'),
    c('visite_pathologie_id', 'uuid', fk='visite_pathologie'),
    c('auteur_id', 'uuid', nn=True, fk='utilisateur'),
    c('consentement_id', 'uuid', nn=True, fk='consentement')] + PHOTO_COLS,
    push=True, scope='etab', ordre=50, indexes=[('visite_id',), ('eleve_id',)])

table('critere_inspection', 'CritereInspectionRow', [
    enum('rubrique', RUBRIQUES), c('code', 'text', nn=True), c('libelle', 'text', nn=True),
    c('ordre', 'int', nn=True, default='0'), c('actif', 'bool', nn=True, default='TRUE')],
    pull=True, uniques=[('code',)])

table('inspection', 'InspectionRow', [
    c('etablissement_id', 'uuid', nn=True, fk='etablissement'),
    c('annee_scolaire_id', 'uuid', nn=True, fk='annee_scolaire'),
    c('inspecteur_id', 'uuid', nn=True, fk='utilisateur'),
    c('date_inspection', 'date', nn=True), c('observations', 'text'), c('recommandations', 'text'),
    c('signature', 'blob'),
    c('nb_conformes', 'int', nn=True, default='0'), c('nb_partiels', 'int', nn=True, default='0'),
    c('nb_non_conformes', 'int', nn=True, default='0'), c('nb_non_applicables', 'int', nn=True, default='0'),
    c('taux_conformite', 'real'),
    enum('niveau', ['satisfaisant', 'moyen', 'insuffisant'], nn=False),
    enum('statut', ['ebauche', 'enregistre', 'valide'], default="'ebauche'")],
    push=True, scope='etab', ordre=30, indexes=[('etablissement_id', 'date_inspection')])

table('inspection_reponse', 'InspectionReponseRow', [
    c('inspection_id', 'uuid', nn=True, fk='inspection'),
    c('critere_id', 'uuid', nn=True, fk='critere_inspection'),
    enum('resultat', ['conforme', 'partiel', 'non_conforme', 'non_applicable']), c('observation', 'text')],
    push=True, scope='etab', ordre=40, uniques=[('inspection_id', 'critere_id')])

table('inspection_photo', 'InspectionPhotoRow', [
    c('inspection_reponse_id', 'uuid', nn=True, fk='inspection_reponse'),
    c('auteur_id', 'uuid', nn=True, fk='utilisateur')] + PHOTO_COLS,
    push=True, scope='etab', ordre=50, indexes=[('inspection_reponse_id',)])

table('journal_audit', 'JournalAuditRow', [
    c('utilisateur_id', 'uuid'), c('appareil_id', 'uuid'),
    enum('action', ['creation', 'modification', 'suppression', 'consultation', 'telechargement', 'export',
                    'connexion', 'echec_connexion', 'deconnexion', 'synchronisation', 'restauration']),
    c('table_cible', 'text'), c('enregistrement_id', 'uuid'), c('avant', 'json'), c('apres', 'json'),
    c('survenu_le', 'ts', nn=True)],
    push=True, ordre=90, indexes=[('utilisateur_id', 'survenu_le'), ('table_cible', 'enregistrement_id')])

table('journal_sync', 'JournalSyncRow', [
    c('appareil_id', 'uuid', nn=True, fk='appareil'), c('utilisateur_id', 'uuid'),
    enum('canal', ['internet', 'wifi']), c('debut', 'ts', nn=True), c('fin', 'ts'),
    c('envoyes', 'int', nn=True, default='0'), c('recus', 'int', nn=True, default='0'),
    c('photos', 'int', nn=True, default='0'), c('erreurs', 'int', nn=True, default='0'), c('detail', 'json')],
    where='pg', indexes=[('appareil_id', 'debut')])

table('conflit', 'ConflitRow', [
    c('table_cible', 'text', nn=True), c('enregistrement_id', 'uuid', nn=True),
    enum('type', ['modification_concurrente', 'suppression_modification', 'doublon_eleve', 'doublon_visite',
                  'unicite']),
    c('version_serveur', 'json'), c('version_appareil', 'json'), c('appareil_id', 'uuid'),
    enum('statut', ['ouvert', 'resolu'], default="'ouvert'"),
    c('resolu_par', 'uuid'), c('resolu_le', 'ts'), enum('choix', ['serveur', 'appareil', 'fusion'], nn=False)],
    where='pg', indexes=[('statut',), ('table_cible', 'enregistrement_id')])

table('parametre', 'ParametreRow', [c('cle', 'text', nn=True), c('valeur', 'text')],
      pull=True, uniques=[('cle',)])

NAMES = {t['name'] for t in T}


def in_sqlite(t): return t['where'] in ('both', 'sqlite')


def in_pg(t): return t['where'] in ('both', 'pg')


def default_sql(col, dialect):
    return col['default']


# ---------------------------------------------------------------- SQLite / drift
def gen_sqlite():
    out = ["-- Schéma SQLite de l'application mobile SSSU-SAJ VMS (drift).",
           "-- Fichier généré à partir de la spécification unique du modèle de données (voir README).",
           "-- Les dates (sans heure) sont stockées en texte AAAA-MM-JJ ; les horodatages en texte ISO 8601 UTC.",
           ""]
    for t in T:
        if not in_sqlite(t):
            continue
        lines = [
            "  id TEXT NOT NULL PRIMARY KEY",
            "  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1)",
            "  base_version INTEGER NOT NULL DEFAULT 0 CHECK (base_version >= 0)",
            "  created_at DATETIME NOT NULL",
            "  updated_at DATETIME NOT NULL",
            "  created_by TEXT",
            "  updated_by TEXT",
            "  device_id TEXT",
            "  deleted_at DATETIME",
            "  sync_status TEXT NOT NULL DEFAULT 'local' CHECK (sync_status IN ('local', 'en_attente', 'synchronise', 'conflit'))",
            "  portee_etablissement_id TEXT",
        ]
        for col in t['cols']:
            if col['fk'] and not in_sqlite(next(x for x in T if x['name'] == col['fk'])):
                fk = None
            else:
                fk = col['fk']
            s = f"  {col['name']} {TYPES[col['typ']][0]}"
            if col['nn']:
                s += " NOT NULL"
            if col['default'] is not None:
                s += f" DEFAULT {col['default']}"
            if col['check']:
                chk = col['check'] if col['nn'] else f"{col['name']} IS NULL OR {col['check']}"
                s += f" CHECK ({chk})"
            if fk:
                s += f" REFERENCES {fk}(id)"
            lines.append(s)
        for u in t['uniques']:
            lines.append(f"  UNIQUE ({', '.join(u)})")
        for ch in t['checks']:
            lines.append(f"  CHECK ({ch})")
        out.append(f"CREATE TABLE {t['name']} (\n" + ",\n".join(lines) + f"\n) AS {t['row']};\n")
    # index
    for t in T:
        if not in_sqlite(t):
            continue
        idx = [(col['name'],) for col in t['cols'] if col['fk']]
        idx += t['indexes']
        seen = set()
        for i in idx:
            if i in seen or any(u[:len(i)] == i for u in t['uniques']):
                continue
            seen.add(i)
            out.append(f"CREATE INDEX idx_{t['name']}_{'_'.join(i)} ON {t['name']} ({', '.join(i)});")
        if t['push']:
            out.append(f"CREATE INDEX idx_{t['name']}_sync ON {t['name']} (sync_status);")
    out.append("")
    out.append("-- Sur un même téléphone, un matricule renseigné ne peut appartenir qu'à un seul élève actif.")
    out.append("-- Sur le poste central, les doublons venant de deux téléphones sont signalés pour fusion (voir conception).")
    out.append("CREATE UNIQUE INDEX uq_eleve_matricule ON eleve (matricule) WHERE matricule IS NOT NULL AND deleted_at IS NULL;")
    out.append("")
    out.append("-- État local de la synchronisation (curseur, adresse du poste central, identifiant de l'appareil).")
    out.append("CREATE TABLE sync_etat (\n  cle TEXT NOT NULL PRIMARY KEY,\n  valeur TEXT\n) AS SyncEtatRow;")
    out.append("")
    out.append("-- Une photographie exige un consentement obtenu pour le même élève.")
    out.append("""CREATE TRIGGER trg_photo_consentement BEFORE INSERT ON photo
WHEN NOT EXISTS (
  SELECT 1 FROM consentement c
  WHERE c.id = NEW.consentement_id AND c.obtenu = TRUE AND c.eleve_id = NEW.eleve_id AND c.deleted_at IS NULL
)
BEGIN
  SELECT RAISE(ABORT, 'consentement_requis');
END;""")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------- PostgreSQL
def gen_pg():
    out = ["-- Schéma PostgreSQL du poste central SSSU-SAJ VMS.",
           "-- Fichier généré à partir de la spécification unique du modèle de données (voir README).",
           "-- À exécuter dans une base vide : psql -d sssu_saj -f 001_schema.sql",
           "",
           "BEGIN;",
           ""]
    for t in T:
        if not in_pg(t):
            continue
        lines = [
            "  id UUID PRIMARY KEY",
            "  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1)",
            "  created_at TIMESTAMPTZ NOT NULL DEFAULT now()",
            "  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()",
            "  created_by UUID",
            "  updated_by UUID",
            "  device_id UUID",
            "  deleted_at TIMESTAMPTZ",
        ]
        for col in t['cols']:
            s = f"  {col['name']} {TYPES[col['typ']][1]}"
            if col['nn']:
                s += " NOT NULL"
            if col['default'] is not None:
                s += f" DEFAULT {col['default']}"
            if col['check']:
                chk = col['check'] if col['nn'] else f"{col['name']} IS NULL OR {col['check']}"
                s += f" CHECK ({chk})"
            lines.append(s)
        for u in t['uniques']:
            lines.append(f"  UNIQUE ({', '.join(u)})")
        for ch in t['checks']:
            lines.append(f"  CHECK ({ch})")
        out.append(f"CREATE TABLE {t['name']} (\n" + ",\n".join(lines) + "\n);\n")
    # clés étrangères différables (un lot de synchronisation est validé en une transaction)
    out.append("-- Clés étrangères : différées jusqu'à la fin de la transaction de synchronisation.")
    for t in T:
        if not in_pg(t):
            continue
        for col in t['cols']:
            if col['fk']:
                out.append(f"ALTER TABLE {t['name']} ADD CONSTRAINT fk_{t['name']}_{col['name']} "
                           f"FOREIGN KEY ({col['name']}) REFERENCES {col['fk']}(id) DEFERRABLE INITIALLY DEFERRED;")
    out.append("")
    for t in T:
        if not in_pg(t):
            continue
        idx = [(col['name'],) for col in t['cols'] if col['fk']]
        idx += t['indexes']
        seen = set()
        for i in idx:
            if i in seen or any(u[:len(i)] == i for u in t['uniques']):
                continue
            seen.add(i)
            out.append(f"CREATE INDEX idx_{t['name']}_{'_'.join(i)} ON {t['name']} ({', '.join(i)});")
    out.append("")
    out.append("""-- Journal des changements diffusés aux téléphones (curseur de réception).
CREATE TABLE sync_changement (
  seq BIGSERIAL PRIMARY KEY,
  table_name TEXT NOT NULL,
  record_id UUID NOT NULL,
  scope UUID,
  version INTEGER NOT NULL,
  motif TEXT,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_sync_changement_scope ON sync_changement (scope, seq);
CREATE INDEX idx_sync_changement_record ON sync_changement (table_name, record_id);

-- Une photographie exige un consentement obtenu pour le même élève.
CREATE FUNCTION fn_photo_consentement() RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM consentement c
    WHERE c.id = NEW.consentement_id AND c.obtenu AND c.eleve_id = NEW.eleve_id AND c.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'consentement_requis';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_photo_consentement AFTER INSERT ON photo
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION fn_photo_consentement();

COMMIT;""")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------- Dart
def gen_dart():
    out = ["// Registre des tables du modèle de données SSSU-SAJ VMS.",
           "// Fichier généré à partir de la spécification unique du modèle (voir README) :",
           "// il doit rester identique aux schémas SQLite (tables.drift) et PostgreSQL (001_schema.sql).",
           "",
           "import 'colonnes.dart';",
           "",
           "/// Toutes les tables, dans l'ordre de création.",
           "const List<TableSpec> registre = ["]
    for t in T:
        cols = ",\n      ".join(f"Colonne('{col['name']}', TypeColonne.{DART_TYPE[col['typ']]}"
                                 + (", obligatoire: true" if col['nn'] else "")
                                 + (", aValeurParDefaut: true" if col['default'] is not None else "") + ")" for col in t['cols'])
        nat = ", ".join("[" + ", ".join(f"'{x}'" for x in u) + "]" for u in t['natural'])
        out.append(f"""  TableSpec(
    nom: '{t['name']}',
    surMobile: {'true' if in_sqlite(t) else 'false'},
    surServeur: {'true' if in_pg(t) else 'false'},
    envoiParTelephone: {'true' if t['push'] else 'false'},
    receptionParTelephone: {'true' if t['pull'] else 'false'},
    parEtablissement: {'true' if t['scope'] else 'false'},
    ordreEnvoi: {t['ordre']},
    clesNaturelles: [{nat}],
    colonnes: [
      {cols},
    ],
  ),""")
    out.append("];")
    out.append("")
    out.append("final Map<String, TableSpec> registreParNom = {for (final t in registre) t.nom: t};")
    return "\n".join(out) + "\n"


def write(rel, content):
    p = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8') as f:
        f.write(content)


write('sssu_mobile/lib/data/tables.drift', gen_sqlite())
write('sql/postgres/001_schema.sql', gen_pg())
write('sssu_core/lib/src/schema/registre.dart', gen_dart())
print(len(T), 'tables')
