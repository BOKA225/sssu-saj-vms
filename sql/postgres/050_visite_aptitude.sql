-- Version 1.6.0 : visite médicale d'aptitude (classes de 3ème et de terminale),
-- distincte de la visite médicale systématique. Les visites existantes sont
-- des visites systématiques. Décision d'aptitude : apte, aptitude partielle
-- (avec restrictions), inapte temporairement, inapte définitivement ; les
-- restrictions ou le motif sont précisés sauf pour « apte ».

ALTER TABLE visite ADD COLUMN IF NOT EXISTS type_visite TEXT NOT NULL DEFAULT 'systematique';
ALTER TABLE visite DROP CONSTRAINT IF EXISTS visite_type_visite_check;
ALTER TABLE visite ADD CONSTRAINT visite_type_visite_check CHECK (type_visite IN ('systematique', 'aptitude'));

ALTER TABLE visite ADD COLUMN IF NOT EXISTS aptitude TEXT;
ALTER TABLE visite DROP CONSTRAINT IF EXISTS visite_aptitude_check;
ALTER TABLE visite ADD CONSTRAINT visite_aptitude_check CHECK (
  aptitude IS NULL OR aptitude IN ('apte', 'apte_partiel', 'inapte_temporaire', 'inapte_definitif'));

ALTER TABLE visite ADD COLUMN IF NOT EXISTS aptitude_restrictions TEXT;

CREATE INDEX IF NOT EXISTS visite_type_idx ON visite (type_visite, date_visite);
