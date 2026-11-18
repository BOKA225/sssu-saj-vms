-- Version 1.9.0 : effectifs d'une classe saisis à la main sur le poste central
-- (classes sans liste d'élèves) : élèves inscrits et élèves visités, par sexe,
-- pour la visite systématique et la visite d'aptitude (3ème, Tle). Les
-- statistiques les utilisent tant que la classe n'a pas de liste d'élèves.
-- Table du poste central seulement (non envoyée aux téléphones).

CREATE TABLE IF NOT EXISTS effectif_classe (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  classe_id UUID NOT NULL,
  garcons INTEGER CHECK (garcons IS NULL OR garcons >= 0),
  filles INTEGER CHECK (filles IS NULL OR filles >= 0),
  visites_garcons INTEGER CHECK (visites_garcons IS NULL OR visites_garcons >= 0),
  visites_filles INTEGER CHECK (visites_filles IS NULL OR visites_filles >= 0),
  aptitude_garcons INTEGER CHECK (aptitude_garcons IS NULL OR aptitude_garcons >= 0),
  aptitude_filles INTEGER CHECK (aptitude_filles IS NULL OR aptitude_filles >= 0),
  UNIQUE (classe_id)
);
