-- Version 1.8.0 : vaccination.
-- - Liste des vaccins (PEV et hors PEV, obligatoires ou recommandés),
--   modifiable sur le poste central et envoyée aux téléphones. La liste
--   initiale reprend le calendrier du PEV de Côte d'Ivoire et des vaccins
--   recommandés hors PEV ; le vaccin HPV (code « HPV ») ne figure pas dans la
--   liste du préscolaire.
-- - Suivi vaccinal des enfants : une fiche par enfant (identifiant calculé à
--   partir de celui de l'élève), parent ou tuteur, carnet présenté,
--   observations, et pour chaque vaccin vérifié : fait (true) ou non fait
--   (false), en JSON (identifiant du vaccin → booléen).
-- - Visite systématique des filles de 9 à 14 ans : vaccin HPV (déjà fait, à
--   proposer, fait lors de la visite, proposé et non fait) et motif.

CREATE TABLE IF NOT EXISTS vaccin (
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
  programme TEXT NOT NULL CHECK (programme IN ('pev', 'hors_pev')),
  statut TEXT NOT NULL CHECK (statut IN ('obligatoire', 'recommande')),
  cible TEXT,
  prescolaire BOOLEAN NOT NULL DEFAULT TRUE,
  actif BOOLEAN NOT NULL DEFAULT TRUE,
  ordre INTEGER NOT NULL DEFAULT 0,
  UNIQUE (code)
);

CREATE TABLE IF NOT EXISTS suivi_vaccinal (
  id UUID PRIMARY KEY,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version >= 1),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  updated_by UUID,
  device_id UUID,
  deleted_at TIMESTAMPTZ,
  eleve_id UUID NOT NULL,
  parent_tuteur TEXT,
  parent_telephone TEXT,
  carnet_presente BOOLEAN,
  vaccins TEXT,
  observations TEXT,
  date_verification DATE,
  UNIQUE (eleve_id)
);

ALTER TABLE visite ADD COLUMN IF NOT EXISTS hpv TEXT;
ALTER TABLE visite DROP CONSTRAINT IF EXISTS visite_hpv_check;
ALTER TABLE visite ADD CONSTRAINT visite_hpv_check CHECK (
  hpv IS NULL OR hpv IN ('deja_fait', 'a_proposer', 'fait', 'non_fait'));

ALTER TABLE visite ADD COLUMN IF NOT EXISTS hpv_motif TEXT;
ALTER TABLE visite DROP CONSTRAINT IF EXISTS visite_hpv_motif_check;
ALTER TABLE visite ADD CONSTRAINT visite_hpv_motif_check CHECK (
  hpv_motif IS NULL OR hpv_motif IN ('refus_parents', 'refus_eleve', 'vaccin_indisponible', 'contre_indication', 'autre'));

INSERT INTO vaccin (id, version, created_at, updated_at, code, libelle, programme, statut, cible, prescolaire, actif, ordre) VALUES
  ('ae1508a2-f0ce-51e5-9856-23d50e28f7ff', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'BCG', 'BCG (tuberculose)', 'pev', 'obligatoire', 'À la naissance', TRUE, TRUE, 1),
  ('687fae48-a0b1-5567-b0de-7652124c35aa', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'HEPB0', 'Hépatite B, dose de naissance (HépB 0)', 'pev', 'obligatoire', 'À la naissance', TRUE, TRUE, 2),
  ('1f5aec27-da44-597c-8116-c1af5c4b832c', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'VPO', 'Poliomyélite orale (VPO 0 à 3)', 'pev', 'obligatoire', 'Naissance, 6, 10 et 14 semaines', TRUE, TRUE, 3),
  ('c3850bf4-a6da-5bb8-b4d6-28d875618e7e', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'PENTA', 'DTC-HépB-Hib (pentavalent 1 à 3)', 'pev', 'obligatoire', '6, 10 et 14 semaines', TRUE, TRUE, 4),
  ('5ead4662-51cd-590f-a848-32f243e3f300', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'PCV13', 'Pneumocoque (PCV13, 1 à 3)', 'pev', 'obligatoire', '6, 10 et 14 semaines', TRUE, TRUE, 5),
  ('db867865-e0c4-53e0-ab0a-c4360c92b0a8', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'ROTA', 'Rotavirus', 'pev', 'obligatoire', 'À partir de 6 semaines', TRUE, TRUE, 6),
  ('d5001293-0e72-5820-bb36-56094255bee1', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'VPI', 'Poliomyélite injectable (VPI)', 'pev', 'obligatoire', 'VPI 1 et VPI 2', TRUE, TRUE, 7),
  ('ee1a1194-8f05-547e-9636-8733b34a259f', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'PALU', 'Paludisme (R21/Matrix-M)', 'pev', 'obligatoire', '4 doses, de 6 à 15 mois', TRUE, TRUE, 8),
  ('9942fbb8-3a5f-5112-9a5f-fefec420e06c', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'RR', 'Rougeole-rubéole (RR 1 et 2)', 'pev', 'obligatoire', 'RR 1 à 9 mois, RR 2 à 15–18 mois', TRUE, TRUE, 9),
  ('0c81a4d9-a4c0-55f7-b50d-8efa8a63dcbf', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'VAA', 'Fièvre jaune (VAA)', 'pev', 'obligatoire', '9 mois', TRUE, TRUE, 10),
  ('360ee79b-6386-5e75-bc29-194117d7cafb', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'MENA', 'Méningite A (MenAfriVac)', 'pev', 'obligatoire', 'Dose unique, entre 9 et 18 mois', TRUE, TRUE, 11),
  ('e09479bd-dda7-5ab5-bd60-661054bf5d37', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'HPV', 'Papillomavirus humain (HPV)', 'pev', 'obligatoire', 'Filles de 9 à 14 ans', FALSE, TRUE, 12),
  ('4f17cfd8-f756-5e37-9bea-dbba41c39587', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'ROR', 'Rougeole-oreillons-rubéole (ROR)', 'hors_pev', 'recommande', 'À partir de 12 mois', TRUE, TRUE, 1),
  ('3b86aead-9eb5-556b-aa5e-a0ce79423214', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'VARICELLE', 'Varicelle', 'hors_pev', 'recommande', 'À partir de 12 mois', TRUE, TRUE, 2),
  ('e9b9b914-36df-5bab-8782-57d52d9cd2a9', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'HEPA', 'Hépatite A', 'hors_pev', 'recommande', 'À partir de 12 mois', TRUE, TRUE, 3),
  ('55804cd0-d356-5ce5-894b-514efb585a46', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'TYPHOIDE', 'Fièvre typhoïde', 'hors_pev', 'recommande', 'À partir de 2 ans', TRUE, TRUE, 4),
  ('85780ea6-806f-5032-9296-d5286a3224b7', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'MENACWY', 'Méningocoques A, C, W, Y (conjugué)', 'hors_pev', 'recommande', 'Selon l''âge', TRUE, TRUE, 5),
  ('d7ad210f-1710-523f-8e3c-5c9251dda802', 1, '2026-11-18T08:00:00Z', '2026-11-18T08:00:00Z', 'GRIPPE', 'Grippe saisonnière', 'hors_pev', 'recommande', 'À partir de 6 mois, chaque année', TRUE, TRUE, 6)
ON CONFLICT (code) DO NOTHING;

-- Liste diffusée aux téléphones.
INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'vaccin', x.id, NULL, x.version FROM vaccin x
WHERE NOT EXISTS (SELECT 1 FROM sync_changement s WHERE s.table_name = 'vaccin' AND s.record_id = x.id)
ORDER BY x.programme DESC, x.ordre;
