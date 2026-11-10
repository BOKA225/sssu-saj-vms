-- Référentiels de production du poste central : rôles et matrice des droits,
-- liste officielle des pathologies dépistées, grille d'inspection sanitaire,
-- paramètres par défaut (en-tête institutionnel, seuils, verrouillage).
-- Appliqué automatiquement par le poste central (migrations) après 001_schema.sql.
-- Idempotent : les lignes déjà présentes (même identifiant) sont laissées telles quelles,
-- ce qui permet aussi de l'appliquer sur une base chargée avec donnees_test.sql.
-- Ne contient aucune donnée de personne ni d'établissement.

BEGIN;

INSERT INTO role (id, version, created_at, updated_at, code, libelle) VALUES
  ('01a1c478-9808-73f6-8882-8b65670e7a1a', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'admin', 'Administrateur'),
  ('01a1c478-9809-7a17-b369-517ff26bf95a', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin_chef', 'Médecin-Chef'),
  ('01a1c478-980a-72a2-97e9-6e7db3329a4a', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin', 'Médecin'),
  ('01a1c478-980b-7001-a695-2750badc673b', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'infirmier', 'Infirmier'),
  ('01a1c478-980c-7cb3-b90b-6163ba8de06f', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'agent', 'Agent de santé')
ON CONFLICT DO NOTHING;

-- Droits par code de rôle : valable aussi si les rôles ont été créés par l'application.
INSERT INTO role_permission (id, version, created_at, updated_at, role_id, permission)
SELECT CAST(v.id AS uuid), v.version, CAST(v.cree AS timestamptz), CAST(v.maj AS timestamptz), r.id, v.permission
FROM (VALUES
  ('01a1c478-980d-7f33-af40-7357909102cb', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'admin', 'comptes.gerer'),
  ('01a1c478-980e-775e-b4aa-9ce48aa34c5f', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'admin', 'parametres.modifier'),
  ('01a1c478-980f-74d2-a98d-dfb9f337f091', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'admin', 'etablissement.gerer'),
  ('01a1c478-9810-7f42-bdd5-b90a43bbf77a', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'admin', 'etablissement.archiver'),
  ('01a1c478-9811-7f16-9280-cf3810f44545', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'admin', 'import.executer'),
  ('01a1c478-9812-7b69-af2e-42d94e781bce', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'admin', 'statistiques.consulter'),
  ('01a1c478-9813-7f63-94ef-d5b80d10ff30', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'admin', 'sauvegarde.gerer'),
  ('01a1c478-9814-7166-80ac-7264b72484fb', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'admin', 'audit.consulter'),
  ('01a1c478-9815-770e-a330-9cbbf0fbd66b', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin_chef', 'parametres.modifier'),
  ('01a1c478-9816-7e61-b9f8-b3803d835380', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin_chef', 'etablissement.gerer'),
  ('01a1c478-9817-76a3-ae62-93ebe6a05e66', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin_chef', 'import.executer'),
  ('01a1c478-9818-71db-8bcb-c1f23772644d', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin_chef', 'visite.saisir'),
  ('01a1c478-9819-757e-af1b-884b77eb0748', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin_chef', 'visite.modifier_toutes'),
  ('01a1c478-981a-71e4-86f8-80519e1d72c1', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin_chef', 'visite.valider'),
  ('01a1c478-981b-77bb-b955-82bdcd7bfc4c', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin_chef', 'visite.rouvrir'),
  ('01a1c478-981c-7a9f-858b-1b8b14feee46', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin_chef', 'photo.prendre'),
  ('01a1c478-981d-77f0-a1bc-3778253f207a', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin_chef', 'photo.voir_toutes'),
  ('01a1c478-981e-7f09-8e58-4524bd5b8140', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin_chef', 'photo.telecharger'),
  ('01a1c478-981f-7248-a2f3-ef3d4dc95b04', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin_chef', 'inspection.realiser'),
  ('01a1c478-9820-762b-8c88-b32037227b2e', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin_chef', 'statistiques.consulter'),
  ('01a1c478-9821-77e1-890b-178fe44af836', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin_chef', 'rapport.exporter_nominatif'),
  ('01a1c478-9822-7f2c-9489-a6d5053c5c3c', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin_chef', 'conflit.resoudre'),
  ('01a1c478-9823-70ca-8713-58405075b14a', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin_chef', 'audit.consulter'),
  ('01a1c478-9824-7073-b250-3ba4733e6440', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin', 'import.executer'),
  ('01a1c478-9825-725f-8287-28063fbcadb2', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin', 'visite.saisir'),
  ('01a1c478-9826-7d47-a28a-8f6e760b27b7', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin', 'visite.modifier_siennes'),
  ('01a1c478-9827-718d-8ae0-9cb72bb3f7f4', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin', 'visite.valider'),
  ('01a1c478-9828-70cd-b12d-c37e7744bf7d', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin', 'photo.prendre'),
  ('01a1c478-9829-76e4-b087-699103f670fa', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin', 'photo.voir_toutes'),
  ('01a1c478-982a-79c7-8c5c-ec5d00f171e7', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin', 'inspection.realiser'),
  ('01a1c478-982b-7f75-a9a7-a771526c5724', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin', 'statistiques.consulter'),
  ('01a1c478-982c-7dfb-8740-86f9d7f60409', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'medecin', 'rapport.exporter_nominatif'),
  ('01a1c478-982d-7eeb-99d9-203da40590f7', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'infirmier', 'import.executer'),
  ('01a1c478-982e-7653-82a0-10c50ac885d2', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'infirmier', 'visite.saisir'),
  ('01a1c478-982f-77d4-8e2c-c9c5acc4cc16', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'infirmier', 'visite.modifier_siennes'),
  ('01a1c478-9830-79e4-95e0-631223db2189', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'infirmier', 'photo.prendre'),
  ('01a1c478-9831-72a5-a06b-0b9f102941a3', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'infirmier', 'inspection.realiser'),
  ('01a1c478-9832-7c56-84d9-490ba9a43b40', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'agent', 'visite.saisir'),
  ('01a1c478-9833-75e4-b7ca-718ff512db59', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'agent', 'visite.modifier_siennes'),
  ('01a1c478-9834-7c1e-a7c5-e13894df3ffa', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'agent', 'photo.prendre'),
  ('01a1c478-9835-77e4-bdbb-f0ee90f21158', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'agent', 'inspection.realiser')
) AS v(id, version, cree, maj, role_code, permission)
JOIN role r ON r.code = v.role_code
ON CONFLICT DO NOTHING;

INSERT INTO pathologie (id, version, created_at, updated_at, code, libelle, active, ordre, precision_requise) VALUES
  ('01a1c478-9836-7a3a-889b-e37cb3084aab', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'dermatoses', 'Dermatoses', TRUE, 1, FALSE),
  ('01a1c478-9837-7f00-b83d-fe43e0c025c0', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'gale', 'Gale', TRUE, 2, FALSE),
  ('01a1c478-9838-7e6c-bba0-f1a7b0e68087', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'mycoses', 'Mycoses', TRUE, 3, FALSE),
  ('01a1c478-9839-77b4-9474-c09a3a4c4d21', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'asthme', 'Asthme', TRUE, 4, FALSE),
  ('01a1c478-983a-7252-911f-439b66a15447', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'caries', 'Caries dentaires', TRUE, 5, FALSE),
  ('01a1c478-983b-7851-9494-f06c7215070b', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'gingivites', 'Gingivites', TRUE, 6, FALSE),
  ('01a1c478-983c-76ba-8e15-df8b19adf0f2', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'otites', 'Otites', TRUE, 7, FALSE),
  ('01a1c478-983d-70c3-ae36-fefbca410f0c', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'baisse_acuite_visuelle', 'Baisse de l''acuité visuelle', TRUE, 8, FALSE),
  ('01a1c478-983e-729e-b8d4-c4bfabc5f16c', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'anemie_clinique', 'Anémie clinique', TRUE, 9, FALSE),
  ('01a1c478-983f-725f-a093-f26e3e29b78a', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'hernie', 'Hernie', TRUE, 10, FALSE),
  ('01a1c478-9840-7152-9420-e90b19c20fef', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'ictere', 'Ictère', TRUE, 11, FALSE),
  ('01a1c478-9841-7f50-a5a5-14f798d39629', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'conjonctivite', 'Conjonctivite', TRUE, 12, FALSE),
  ('01a1c478-9842-725d-ac6d-37bb30e27d3b', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'handicap', 'Handicap', TRUE, 13, TRUE),
  ('01a1c478-9843-7f88-9ee9-f07295323432', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'ist', 'Infections sexuellement transmissibles', TRUE, 14, FALSE),
  ('01a1c478-9844-7fde-8856-30a836992210', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'grossesse', 'Grossesse', TRUE, 15, FALSE),
  ('01a1c478-9845-7e94-97ba-952ff51bd4ff', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'hematurie', 'Hématurie', TRUE, 16, FALSE),
  ('01a1c478-9846-7d16-ac01-7174ff64c2bd', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'autre', 'Autres pathologies', TRUE, 17, TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO critere_inspection (id, version, created_at, updated_at, rubrique, code, libelle, ordre, actif) VALUES
  ('01a1c478-9847-7bac-b0a9-1a66bda3940b', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'eau_potable', 'eau_disponibilite', 'Eau potable disponible', 1, TRUE),
  ('01a1c478-9848-7fff-885c-f53612ab3285', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'eau_potable', 'eau_accessibilite', 'Point d''eau accessible aux élèves', 2, TRUE),
  ('01a1c478-9849-7b65-a64d-9d3891ef2790', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'eau_potable', 'eau_qualite', 'Qualité de l''eau (aspect, protection du point d''eau)', 3, TRUE),
  ('01a1c478-984a-765c-aeac-3ea62f30abb2', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'toilettes', 'toilettes_nombre', 'Nombre de toilettes suffisant', 4, TRUE),
  ('01a1c478-984b-7fdb-8f1d-af0ae179ef3b', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'toilettes', 'toilettes_proprete', 'Propreté des toilettes', 5, TRUE),
  ('01a1c478-984c-755c-8019-b8e5614be136', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'toilettes', 'toilettes_fonctionnalite', 'Toilettes fonctionnelles', 6, TRUE),
  ('01a1c478-984d-7908-88ee-8eec3bc9f226', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'toilettes', 'toilettes_separation', 'Séparation filles / garçons', 7, TRUE),
  ('01a1c478-984e-7a98-9343-4fd65d94132d', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'lavage_mains', 'lavage_dispositif', 'Dispositif de lavage des mains', 8, TRUE),
  ('01a1c478-984f-7004-bc42-a34d50ee475f', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'lavage_mains', 'lavage_savon', 'Savon disponible', 9, TRUE),
  ('01a1c478-9850-7c7f-960e-e3b0d0c3c19a', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'dechets', 'dechets_poubelles', 'Poubelles en place', 10, TRUE),
  ('01a1c478-9851-7794-abce-6067f17e3340', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'dechets', 'dechets_collecte', 'Collecte et évacuation des déchets', 11, TRUE),
  ('01a1c478-9852-76a1-8777-b57821e86a88', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'environnement', 'env_cour', 'Propreté de la cour', 12, TRUE),
  ('01a1c478-9853-7656-a585-f08b40baec9e', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'environnement', 'env_salles', 'Propreté des salles', 13, TRUE),
  ('01a1c478-9854-72a7-bb96-ef1117cbbc3c', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'cantine', 'cantine_locaux', 'Hygiène des locaux de la cantine', 14, TRUE),
  ('01a1c478-9855-7672-8ce8-7e83cfe50a9a', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'cantine', 'cantine_aliments', 'Hygiène des aliments', 15, TRUE),
  ('01a1c478-9856-702c-b8d8-250d790fb53f', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'vendeuses', 'vendeuses_hygiene', 'Conditions d''hygiène des vendeuses', 16, TRUE),
  ('01a1c478-9857-7fde-8e60-0924080efffd', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'vendeuses', 'vendeuses_visite', 'Visite médicale des vendeuses', 17, TRUE),
  ('01a1c478-9858-7594-82d6-c64d869077d0', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'infirmerie', 'infirmerie_disponible', 'Infirmerie disponible', 18, TRUE),
  ('01a1c478-9859-7055-8e45-ebbab1258a6c', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'infirmerie', 'infirmerie_fonctionnelle', 'Infirmerie fonctionnelle', 19, TRUE),
  ('01a1c478-985a-78ba-ab20-400586001de1', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'securite', 'securite_batiments', 'État des bâtiments', 20, TRUE),
  ('01a1c478-985b-7d4e-8f56-e1f358874359', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'securite', 'securite_risques', 'Risques environnementaux maîtrisés', 21, TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO parametre (id, version, created_at, updated_at, cle, valeur) VALUES
  ('01a1c478-985c-7572-a2f3-5944141b6910', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'entete_ligne_1', 'MINISTÈRE EN CHARGE DE LA SANTÉ'),
  ('01a1c478-985d-7c1b-b513-a41d82e47b84', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'entete_ligne_2', 'DIRECTION RÉGIONALE DE LA SANTÉ DU N''ZI'),
  ('01a1c478-985e-7bf5-be69-4f84e819c196', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'entete_ligne_3', 'DISTRICT SANITAIRE DE KOUASSI-KOUASSIKRO'),
  ('01a1c478-985f-7062-9d59-390b648d0111', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'entete_ligne_4', 'SERVICE DE SANTÉ SCOLAIRE ET UNIVERSITAIRE – SANTÉ ADOLESCENTS ET JEUNES (SSSU-SAJ)'),
  ('01a1c478-9860-7d4d-a0ac-3da74fed4e09', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'nom_medecin_chef', ''),
  ('01a1c478-9861-722f-a329-18a775433591', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'verrouillage_mobile_minutes', '5'),
  ('01a1c478-9862-7da2-8042-fde205d94ea4', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'verrouillage_windows_minutes', '15'),
  ('01a1c478-9863-7f12-a7c6-9de7c552133a', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'seuil_conformite_satisfaisant', '80'),
  ('01a1c478-9864-730c-86dd-e454e7e571e8', 1, '2026-11-10T08:00:00Z', '2026-11-10T08:00:00Z', 'seuil_conformite_moyen', '50')
ON CONFLICT DO NOTHING;


-- Diffusion aux téléphones (journal des changements), sans doublon.

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'role', x.id, NULL, x.version FROM role x
WHERE NOT EXISTS (SELECT 1 FROM sync_changement s WHERE s.table_name = 'role' AND s.record_id = x.id)
ORDER BY x.created_at, x.id;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'role_permission', x.id, NULL, x.version FROM role_permission x
WHERE NOT EXISTS (SELECT 1 FROM sync_changement s WHERE s.table_name = 'role_permission' AND s.record_id = x.id)
ORDER BY x.created_at, x.id;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'pathologie', x.id, NULL, x.version FROM pathologie x
WHERE NOT EXISTS (SELECT 1 FROM sync_changement s WHERE s.table_name = 'pathologie' AND s.record_id = x.id)
ORDER BY x.created_at, x.id;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'critere_inspection', x.id, NULL, x.version FROM critere_inspection x
WHERE NOT EXISTS (SELECT 1 FROM sync_changement s WHERE s.table_name = 'critere_inspection' AND s.record_id = x.id)
ORDER BY x.created_at, x.id;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'parametre', x.id, NULL, x.version FROM parametre x
WHERE NOT EXISTS (SELECT 1 FROM sync_changement s WHERE s.table_name = 'parametre' AND s.record_id = x.id)
ORDER BY x.created_at, x.id;


COMMIT;
