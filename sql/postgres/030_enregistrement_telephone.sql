-- Version 1.1.0 : enregistrement d'un téléphone sans QR code.
-- L'agent enregistre lui-même son téléphone (identifiant et mot de passe) ;
-- le téléphone reste « en attente » jusqu'à sa validation par l'administrateur.
ALTER TABLE appareil ADD COLUMN IF NOT EXISTS en_attente BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS appareil_en_attente ON appareil (en_attente) WHERE en_attente AND deleted_at IS NULL;
