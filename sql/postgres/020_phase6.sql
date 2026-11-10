-- Phase 6 : génération des données (reprise des téléphones après une
-- restauration de sauvegarde) et recherche des élèves sans tenir compte des
-- accents. Appliqué automatiquement par le poste central (migrations).

BEGIN;

-- Une seule ligne. La restauration d'une sauvegarde renouvelle la génération :
-- les téléphones renvoient alors leurs données plus récentes et rechargent tout.
CREATE TABLE IF NOT EXISTS sync_generation (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  generation UUID NOT NULL,
  depuis TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO sync_generation (id, generation) VALUES (1, gen_random_uuid()) ON CONFLICT (id) DO NOTHING;

-- « KONE » trouve « KONÉ ». L'extension unaccent est livrée avec PostgreSQL
-- (contrib) et autorisée au propriétaire de la base (extension « trusted »).
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Enveloppe IMMUTABLE (indexable) autour de unaccent().
CREATE OR REPLACE FUNCTION sssu_sans_accents(t TEXT) RETURNS TEXT
  LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
  AS $$ SELECT public.unaccent('public.unaccent'::regdictionary, t) $$;

CREATE INDEX IF NOT EXISTS idx_eleve_nom_sans_accents ON eleve (sssu_sans_accents(lower(nom || ' ' || prenoms)));

COMMIT;
