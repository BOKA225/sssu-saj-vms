-- Schéma PostgreSQL du poste central SSSU-SAJ VMS.
-- Fichier généré à partir de la spécification unique du modèle de données (voir README).
-- À exécuter dans une base vide : psql -d sssu_saj -f 001_schema.sql

BEGIN;

CREATE TABLE annee_scolaire (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  libelle TEXT NOT NULL,
  date_debut DATE NOT NULL,
  date_fin DATE NOT NULL,
  active BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE (libelle),
  CHECK (date_fin > date_debut)
);

CREATE TABLE etablissement (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  nom TEXT NOT NULL,
  code TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('prescolaire', 'primaire', 'secondaire', 'technique', 'superieur')),
  statut TEXT NOT NULL CHECK (statut IN ('public', 'prive')),
  region TEXT,
  district_sanitaire TEXT,
  localite TEXT,
  responsable TEXT,
  telephone TEXT,
  UNIQUE (code)
);

CREATE TABLE classe (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  etablissement_id UUID NOT NULL,
  annee_scolaire_id UUID NOT NULL,
  libelle TEXT NOT NULL,
  niveau TEXT,
  UNIQUE (etablissement_id, annee_scolaire_id, libelle)
);

CREATE TABLE role (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  code TEXT NOT NULL CHECK (code IN ('admin', 'medecin_chef', 'medecin', 'infirmier', 'agent')),
  libelle TEXT NOT NULL,
  UNIQUE (code)
);

CREATE TABLE role_permission (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  role_id UUID NOT NULL,
  permission TEXT NOT NULL,
  UNIQUE (role_id, permission)
);

CREATE TABLE utilisateur (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  identifiant TEXT NOT NULL,
  nom TEXT NOT NULL,
  prenoms TEXT,
  fonction TEXT,
  structure TEXT,
  role_id UUID NOT NULL,
  hash_mot_de_passe TEXT,
  hash_pin TEXT,
  actif BOOLEAN NOT NULL DEFAULT TRUE,
  doit_changer_mdp BOOLEAN NOT NULL DEFAULT TRUE,
  echecs_connexion INTEGER NOT NULL DEFAULT 0,
  bloque_jusqua TIMESTAMPTZ,
  UNIQUE (identifiant)
);

CREATE TABLE eleve (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  matricule TEXT,
  nom TEXT NOT NULL,
  prenoms TEXT NOT NULL,
  date_naissance DATE,
  sexe TEXT NOT NULL CHECK (sexe IN ('M', 'F')),
  telephone_contact TEXT
);

CREATE TABLE inscription (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  eleve_id UUID NOT NULL,
  classe_id UUID NOT NULL,
  annee_scolaire_id UUID NOT NULL,
  statut TEXT NOT NULL DEFAULT 'inscrit' CHECK (statut IN ('inscrit', 'transfere', 'sorti')),
  UNIQUE (eleve_id, annee_scolaire_id)
);

CREATE TABLE appareil (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  nom TEXT NOT NULL,
  modele TEXT,
  cle_publique TEXT,
  titulaire_id UUID,
  date_appairage TIMESTAMPTZ,
  bloque BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE appareil_etablissement (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  appareil_id UUID NOT NULL,
  etablissement_id UUID NOT NULL,
  UNIQUE (appareil_id, etablissement_id)
);

CREATE TABLE appairage_code (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  appareil_id UUID NOT NULL,
  code_hash TEXT NOT NULL,
  expire_le TIMESTAMPTZ NOT NULL,
  utilise BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE import_lot (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  classe_id UUID,
  utilisateur_id UUID,
  fichier_nom TEXT NOT NULL,
  format TEXT NOT NULL CHECK (format IN ('xlsx', 'xls', 'csv', 'pdf', 'pdf_ocr', 'image_ocr')),
  empreinte_sha256 TEXT NOT NULL,
  statut TEXT NOT NULL DEFAULT 'brouillon' CHECK (statut IN ('brouillon', 'valide', 'annule')),
  nb_lignes INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE import_ligne (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  import_lot_id UUID NOT NULL,
  numero INTEGER NOT NULL,
  donnees_extraites JSONB NOT NULL,
  confiance_ocr DOUBLE PRECISION,
  anomalies JSONB,
  decision TEXT NOT NULL DEFAULT 'a_verifier' CHECK (decision IN ('a_verifier', 'garder', 'corriger', 'rejeter')),
  eleve_id UUID,
  UNIQUE (import_lot_id, numero)
);

CREATE TABLE visite (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  eleve_id UUID NOT NULL,
  inscription_id UUID,
  agent_id UUID NOT NULL,
  appareil_id UUID,
  validateur_id UUID,
  date_visite DATE NOT NULL,
  structure_origine TEXT,
  statut TEXT NOT NULL DEFAULT 'ebauche' CHECK (statut IN ('ebauche', 'enregistre', 'en_attente', 'synchronise', 'valide')),
  poids_kg DOUBLE PRECISION,
  taille_cm DOUBLE PRECISION,
  imc DOUBLE PRECISION,
  imc_interpretation TEXT,
  ta_sys INTEGER,
  ta_dia INTEGER,
  temperature_c DOUBLE PRECISION,
  fc INTEGER,
  fr INTEGER,
  conclusion TEXT CHECK (conclusion IS NULL OR conclusion IN ('sans_anomalie', 'anomalie', 'suivi', 'reference')),
  diagnostic TEXT,
  conduite_a_tenir TEXT,
  traitement_conseils TEXT,
  structure_reference TEXT,
  date_controle DATE,
  observations TEXT,
  valide_le TIMESTAMPTZ,
  CHECK (poids_kg IS NULL OR poids_kg > 0),
  CHECK (taille_cm IS NULL OR taille_cm > 0)
);

CREATE TABLE antecedent (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  visite_id UUID NOT NULL,
  eleve_id UUID NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('personnel', 'chirurgical', 'familial', 'allergique', 'gynecologique', 'traitement')),
  coche BOOLEAN NOT NULL DEFAULT FALSE,
  commentaire TEXT
);

CREATE TABLE examen_appareil (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  visite_id UUID NOT NULL,
  appareil TEXT NOT NULL CHECK (appareil IN ('general', 'dermatologique', 'orl', 'ophtalmologique', 'bucco_dentaire', 'cardiovasculaire', 'respiratoire', 'digestif', 'neurologique', 'osteo_articulaire', 'genito_urinaire')),
  resultat TEXT NOT NULL CHECK (resultat IN ('normal', 'anormal', 'non_examine')),
  observation TEXT,
  UNIQUE (visite_id, appareil)
);

CREATE TABLE pathologie (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  code TEXT NOT NULL,
  libelle TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  ordre INTEGER NOT NULL DEFAULT 0,
  precision_requise BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE (code)
);

CREATE TABLE visite_pathologie (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  visite_id UUID NOT NULL,
  pathologie_id UUID NOT NULL,
  precision TEXT,
  UNIQUE (visite_id, pathologie_id)
);

CREATE TABLE consentement (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  eleve_id UUID NOT NULL,
  visite_id UUID,
  type TEXT NOT NULL DEFAULT 'photo' CHECK (type IN ('photo')),
  obtenu BOOLEAN NOT NULL,
  forme TEXT CHECK (forme IS NULL OR forme IN ('ecrit', 'oral')),
  nom_repondant TEXT,
  lien_parente TEXT,
  date_consentement DATE NOT NULL,
  CHECK (obtenu = FALSE OR (forme IS NOT NULL AND nom_repondant IS NOT NULL))
);

CREATE TABLE photo (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  visite_id UUID NOT NULL,
  eleve_id UUID NOT NULL,
  visite_pathologie_id UUID,
  auteur_id UUID NOT NULL,
  consentement_id UUID NOT NULL,
  chemin_chiffre TEXT NOT NULL,
  empreinte_sha256 TEXT NOT NULL,
  taille_octets INTEGER NOT NULL,
  largeur INTEGER,
  hauteur INTEGER,
  commentaire TEXT,
  pris_le TIMESTAMPTZ NOT NULL,
  statut_transfert TEXT NOT NULL DEFAULT 'en_attente' CHECK (statut_transfert IN ('en_attente', 'transfere', 'confirme'))
);

CREATE TABLE critere_inspection (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  rubrique TEXT NOT NULL CHECK (rubrique IN ('eau_potable', 'toilettes', 'lavage_mains', 'dechets', 'environnement', 'cantine', 'vendeuses', 'infirmerie', 'securite')),
  code TEXT NOT NULL,
  libelle TEXT NOT NULL,
  ordre INTEGER NOT NULL DEFAULT 0,
  actif BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (code)
);

CREATE TABLE inspection (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  etablissement_id UUID NOT NULL,
  annee_scolaire_id UUID NOT NULL,
  inspecteur_id UUID NOT NULL,
  date_inspection DATE NOT NULL,
  observations TEXT,
  recommandations TEXT,
  signature BYTEA,
  nb_conformes INTEGER NOT NULL DEFAULT 0,
  nb_partiels INTEGER NOT NULL DEFAULT 0,
  nb_non_conformes INTEGER NOT NULL DEFAULT 0,
  nb_non_applicables INTEGER NOT NULL DEFAULT 0,
  taux_conformite DOUBLE PRECISION,
  niveau TEXT CHECK (niveau IS NULL OR niveau IN ('satisfaisant', 'moyen', 'insuffisant')),
  statut TEXT NOT NULL DEFAULT 'ebauche' CHECK (statut IN ('ebauche', 'enregistre', 'valide'))
);

CREATE TABLE inspection_reponse (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  inspection_id UUID NOT NULL,
  critere_id UUID NOT NULL,
  resultat TEXT NOT NULL CHECK (resultat IN ('conforme', 'partiel', 'non_conforme', 'non_applicable')),
  observation TEXT,
  UNIQUE (inspection_id, critere_id)
);

CREATE TABLE inspection_photo (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  inspection_reponse_id UUID NOT NULL,
  auteur_id UUID NOT NULL,
  chemin_chiffre TEXT NOT NULL,
  empreinte_sha256 TEXT NOT NULL,
  taille_octets INTEGER NOT NULL,
  largeur INTEGER,
  hauteur INTEGER,
  commentaire TEXT,
  pris_le TIMESTAMPTZ NOT NULL,
  statut_transfert TEXT NOT NULL DEFAULT 'en_attente' CHECK (statut_transfert IN ('en_attente', 'transfere', 'confirme'))
);

CREATE TABLE journal_audit (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  utilisateur_id UUID,
  appareil_id UUID,
  action TEXT NOT NULL CHECK (action IN ('creation', 'modification', 'suppression', 'consultation', 'telechargement', 'export', 'connexion', 'echec_connexion', 'deconnexion', 'synchronisation', 'restauration')),
  table_cible TEXT,
  enregistrement_id UUID,
  avant JSONB,
  apres JSONB,
  survenu_le TIMESTAMPTZ NOT NULL
);

CREATE TABLE journal_sync (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  appareil_id UUID NOT NULL,
  utilisateur_id UUID,
  canal TEXT NOT NULL CHECK (canal IN ('internet', 'wifi')),
  debut TIMESTAMPTZ NOT NULL,
  fin TIMESTAMPTZ,
  envoyes INTEGER NOT NULL DEFAULT 0,
  recus INTEGER NOT NULL DEFAULT 0,
  photos INTEGER NOT NULL DEFAULT 0,
  erreurs INTEGER NOT NULL DEFAULT 0,
  detail JSONB
);

CREATE TABLE conflit (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  table_cible TEXT NOT NULL,
  enregistrement_id UUID NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('modification_concurrente', 'suppression_modification', 'doublon_eleve', 'doublon_visite', 'unicite')),
  version_serveur JSONB,
  version_appareil JSONB,
  appareil_id UUID,
  statut TEXT NOT NULL DEFAULT 'ouvert' CHECK (statut IN ('ouvert', 'resolu')),
  resolu_par UUID,
  resolu_le TIMESTAMPTZ,
  choix TEXT CHECK (choix IS NULL OR choix IN ('serveur', 'appareil', 'fusion'))
);

CREATE TABLE parametre (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  cle TEXT NOT NULL,
  valeur TEXT,
  UNIQUE (cle)
);

-- Clés étrangères : différées jusqu'à la fin de la transaction de synchronisation.
ALTER TABLE classe ADD CONSTRAINT fk_classe_etablissement_id FOREIGN KEY (etablissement_id) REFERENCES etablissement(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE classe ADD CONSTRAINT fk_classe_annee_scolaire_id FOREIGN KEY (annee_scolaire_id) REFERENCES annee_scolaire(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE role_permission ADD CONSTRAINT fk_role_permission_role_id FOREIGN KEY (role_id) REFERENCES role(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE utilisateur ADD CONSTRAINT fk_utilisateur_role_id FOREIGN KEY (role_id) REFERENCES role(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE inscription ADD CONSTRAINT fk_inscription_eleve_id FOREIGN KEY (eleve_id) REFERENCES eleve(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE inscription ADD CONSTRAINT fk_inscription_classe_id FOREIGN KEY (classe_id) REFERENCES classe(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE inscription ADD CONSTRAINT fk_inscription_annee_scolaire_id FOREIGN KEY (annee_scolaire_id) REFERENCES annee_scolaire(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE appareil ADD CONSTRAINT fk_appareil_titulaire_id FOREIGN KEY (titulaire_id) REFERENCES utilisateur(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE appareil_etablissement ADD CONSTRAINT fk_appareil_etablissement_appareil_id FOREIGN KEY (appareil_id) REFERENCES appareil(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE appareil_etablissement ADD CONSTRAINT fk_appareil_etablissement_etablissement_id FOREIGN KEY (etablissement_id) REFERENCES etablissement(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE appairage_code ADD CONSTRAINT fk_appairage_code_appareil_id FOREIGN KEY (appareil_id) REFERENCES appareil(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE import_lot ADD CONSTRAINT fk_import_lot_classe_id FOREIGN KEY (classe_id) REFERENCES classe(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE import_lot ADD CONSTRAINT fk_import_lot_utilisateur_id FOREIGN KEY (utilisateur_id) REFERENCES utilisateur(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE import_ligne ADD CONSTRAINT fk_import_ligne_import_lot_id FOREIGN KEY (import_lot_id) REFERENCES import_lot(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE import_ligne ADD CONSTRAINT fk_import_ligne_eleve_id FOREIGN KEY (eleve_id) REFERENCES eleve(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE visite ADD CONSTRAINT fk_visite_eleve_id FOREIGN KEY (eleve_id) REFERENCES eleve(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE visite ADD CONSTRAINT fk_visite_inscription_id FOREIGN KEY (inscription_id) REFERENCES inscription(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE visite ADD CONSTRAINT fk_visite_agent_id FOREIGN KEY (agent_id) REFERENCES utilisateur(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE visite ADD CONSTRAINT fk_visite_validateur_id FOREIGN KEY (validateur_id) REFERENCES utilisateur(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE antecedent ADD CONSTRAINT fk_antecedent_visite_id FOREIGN KEY (visite_id) REFERENCES visite(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE antecedent ADD CONSTRAINT fk_antecedent_eleve_id FOREIGN KEY (eleve_id) REFERENCES eleve(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE examen_appareil ADD CONSTRAINT fk_examen_appareil_visite_id FOREIGN KEY (visite_id) REFERENCES visite(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE visite_pathologie ADD CONSTRAINT fk_visite_pathologie_visite_id FOREIGN KEY (visite_id) REFERENCES visite(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE visite_pathologie ADD CONSTRAINT fk_visite_pathologie_pathologie_id FOREIGN KEY (pathologie_id) REFERENCES pathologie(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE consentement ADD CONSTRAINT fk_consentement_eleve_id FOREIGN KEY (eleve_id) REFERENCES eleve(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE consentement ADD CONSTRAINT fk_consentement_visite_id FOREIGN KEY (visite_id) REFERENCES visite(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE photo ADD CONSTRAINT fk_photo_visite_id FOREIGN KEY (visite_id) REFERENCES visite(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE photo ADD CONSTRAINT fk_photo_eleve_id FOREIGN KEY (eleve_id) REFERENCES eleve(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE photo ADD CONSTRAINT fk_photo_visite_pathologie_id FOREIGN KEY (visite_pathologie_id) REFERENCES visite_pathologie(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE photo ADD CONSTRAINT fk_photo_auteur_id FOREIGN KEY (auteur_id) REFERENCES utilisateur(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE photo ADD CONSTRAINT fk_photo_consentement_id FOREIGN KEY (consentement_id) REFERENCES consentement(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE inspection ADD CONSTRAINT fk_inspection_etablissement_id FOREIGN KEY (etablissement_id) REFERENCES etablissement(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE inspection ADD CONSTRAINT fk_inspection_annee_scolaire_id FOREIGN KEY (annee_scolaire_id) REFERENCES annee_scolaire(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE inspection ADD CONSTRAINT fk_inspection_inspecteur_id FOREIGN KEY (inspecteur_id) REFERENCES utilisateur(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE inspection_reponse ADD CONSTRAINT fk_inspection_reponse_inspection_id FOREIGN KEY (inspection_id) REFERENCES inspection(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE inspection_reponse ADD CONSTRAINT fk_inspection_reponse_critere_id FOREIGN KEY (critere_id) REFERENCES critere_inspection(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE inspection_photo ADD CONSTRAINT fk_inspection_photo_inspection_reponse_id FOREIGN KEY (inspection_reponse_id) REFERENCES inspection_reponse(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE inspection_photo ADD CONSTRAINT fk_inspection_photo_auteur_id FOREIGN KEY (auteur_id) REFERENCES utilisateur(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE journal_sync ADD CONSTRAINT fk_journal_sync_appareil_id FOREIGN KEY (appareil_id) REFERENCES appareil(id) DEFERRABLE INITIALLY DEFERRED;

CREATE INDEX idx_classe_annee_scolaire_id ON classe (annee_scolaire_id);
CREATE INDEX idx_utilisateur_role_id ON utilisateur (role_id);
CREATE INDEX idx_eleve_nom_prenoms ON eleve (nom, prenoms);
CREATE INDEX idx_eleve_matricule ON eleve (matricule);
CREATE INDEX idx_inscription_classe_id ON inscription (classe_id);
CREATE INDEX idx_inscription_annee_scolaire_id ON inscription (annee_scolaire_id);
CREATE INDEX idx_appareil_titulaire_id ON appareil (titulaire_id);
CREATE INDEX idx_appareil_etablissement_etablissement_id ON appareil_etablissement (etablissement_id);
CREATE INDEX idx_appairage_code_appareil_id ON appairage_code (appareil_id);
CREATE INDEX idx_import_lot_classe_id ON import_lot (classe_id);
CREATE INDEX idx_import_lot_utilisateur_id ON import_lot (utilisateur_id);
CREATE INDEX idx_import_ligne_eleve_id ON import_ligne (eleve_id);
CREATE INDEX idx_visite_eleve_id ON visite (eleve_id);
CREATE INDEX idx_visite_inscription_id ON visite (inscription_id);
CREATE INDEX idx_visite_agent_id ON visite (agent_id);
CREATE INDEX idx_visite_validateur_id ON visite (validateur_id);
CREATE INDEX idx_visite_eleve_id_date_visite ON visite (eleve_id, date_visite);
CREATE INDEX idx_antecedent_visite_id ON antecedent (visite_id);
CREATE INDEX idx_antecedent_eleve_id ON antecedent (eleve_id);
CREATE INDEX idx_visite_pathologie_pathologie_id ON visite_pathologie (pathologie_id);
CREATE INDEX idx_consentement_eleve_id ON consentement (eleve_id);
CREATE INDEX idx_consentement_visite_id ON consentement (visite_id);
CREATE INDEX idx_photo_visite_id ON photo (visite_id);
CREATE INDEX idx_photo_eleve_id ON photo (eleve_id);
CREATE INDEX idx_photo_visite_pathologie_id ON photo (visite_pathologie_id);
CREATE INDEX idx_photo_auteur_id ON photo (auteur_id);
CREATE INDEX idx_photo_consentement_id ON photo (consentement_id);
CREATE INDEX idx_inspection_etablissement_id ON inspection (etablissement_id);
CREATE INDEX idx_inspection_annee_scolaire_id ON inspection (annee_scolaire_id);
CREATE INDEX idx_inspection_inspecteur_id ON inspection (inspecteur_id);
CREATE INDEX idx_inspection_etablissement_id_date_inspection ON inspection (etablissement_id, date_inspection);
CREATE INDEX idx_inspection_reponse_critere_id ON inspection_reponse (critere_id);
CREATE INDEX idx_inspection_photo_inspection_reponse_id ON inspection_photo (inspection_reponse_id);
CREATE INDEX idx_inspection_photo_auteur_id ON inspection_photo (auteur_id);
CREATE INDEX idx_journal_audit_utilisateur_id_survenu_le ON journal_audit (utilisateur_id, survenu_le);
CREATE INDEX idx_journal_audit_table_cible_enregistrement_id ON journal_audit (table_cible, enregistrement_id);
CREATE INDEX idx_journal_sync_appareil_id ON journal_sync (appareil_id);
CREATE INDEX idx_journal_sync_appareil_id_debut ON journal_sync (appareil_id, debut);
CREATE INDEX idx_conflit_statut ON conflit (statut);
CREATE INDEX idx_conflit_table_cible_enregistrement_id ON conflit (table_cible, enregistrement_id);

-- Journal des changements diffusés aux téléphones (curseur de réception).
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

COMMIT;
