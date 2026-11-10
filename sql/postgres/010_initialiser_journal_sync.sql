-- À exécuter UNE FOIS après un chargement direct de données en SQL (par exemple donnees_test.sql),
-- pour que ces données soient diffusées aux téléphones lors de leur première synchronisation.
-- Les enregistrements créés ensuite par l'application alimentent sync_changement automatiquement.
-- L'ordre des insertions respecte les dépendances : un téléphone reçoit toujours le parent avant l'enfant.

BEGIN;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'annee_scolaire', id, NULL, version FROM annee_scolaire ORDER BY created_at, id;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'etablissement', id, id, version FROM etablissement ORDER BY created_at, id;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'classe', id, etablissement_id, version FROM classe ORDER BY created_at, id;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'role', id, NULL, version FROM role ORDER BY created_at, id;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'role_permission', id, NULL, version FROM role_permission ORDER BY created_at, id;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'utilisateur', id, NULL, version FROM utilisateur ORDER BY created_at, id;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'pathologie', id, NULL, version FROM pathologie ORDER BY created_at, id;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'critere_inspection', id, NULL, version FROM critere_inspection ORDER BY created_at, id;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'parametre', id, NULL, version FROM parametre ORDER BY created_at, id;

-- Un élève est diffusé à l'établissement de sa dernière inscription.
INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'eleve', e.id, (
  SELECT c.etablissement_id FROM inscription i JOIN classe c ON c.id = i.classe_id
  JOIN annee_scolaire a ON a.id = i.annee_scolaire_id
  WHERE i.eleve_id = e.id ORDER BY a.date_debut DESC LIMIT 1
), e.version
FROM eleve e ORDER BY e.created_at, e.id;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'inscription', i.id, c.etablissement_id, i.version
FROM inscription i JOIN classe c ON c.id = i.classe_id ORDER BY i.created_at, i.id;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'visite', v.id, c.etablissement_id, v.version
FROM visite v JOIN inscription i ON i.id = v.inscription_id JOIN classe c ON c.id = i.classe_id
ORDER BY v.created_at, v.id;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'antecedent', a.id, c.etablissement_id, a.version
FROM antecedent a JOIN visite v ON v.id = a.visite_id
JOIN inscription i ON i.id = v.inscription_id JOIN classe c ON c.id = i.classe_id
ORDER BY a.created_at, a.id;

COMMIT;
