-- Version 1.2.0 : grille d'inspection sanitaire des établissements scolaires
-- (SSSU-SAJ de Kouassi-Kouassikro, normes MENA 2022 et OMS) : 118 critères
-- cotés C / NC / NA (sections B à J, dont 7 critères critiques ★) ; les
-- données de la grille (identification, structure et effectifs, équipements,
-- constats et plan d'action) sont dans inspection.grille (JSON).
-- Les critères de l'ancienne grille sont désactivés : les inspections déjà
-- faites les gardent ; l'administrateur peut en réactiver un.

ALTER TABLE critere_inspection DROP CONSTRAINT IF EXISTS critere_inspection_rubrique_check;
ALTER TABLE critere_inspection ADD CONSTRAINT critere_inspection_rubrique_check CHECK (rubrique IN (
  'eau_potable', 'toilettes', 'lavage_mains', 'dechets', 'environnement', 'cantine', 'vendeuses', 'infirmerie', 'securite',
  'eau_boisson', 'latrines', 'hygiene_mains', 'hygiene_menstruelle', 'cour_dechets', 'salles_classe', 'cantine_vente',
  'securite_environnement', 'sante_scolaire'));

ALTER TABLE inspection ADD COLUMN IF NOT EXISTS grille TEXT;

-- Ancienne grille désactivée (et diffusée aux téléphones).
WITH maj AS (
  UPDATE critere_inspection SET actif = FALSE, version = version + 1, updated_at = now()
  WHERE actif AND deleted_at IS NULL
    AND rubrique IN ('eau_potable', 'toilettes', 'lavage_mains', 'dechets', 'environnement', 'cantine', 'vendeuses',
                     'infirmerie', 'securite')
  RETURNING id, version
)
INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'critere_inspection', id, NULL, version FROM maj;

INSERT INTO critere_inspection (id, version, created_at, updated_at, rubrique, code, libelle, ordre, actif) VALUES
  ('019a7c3e-8001-7d58-885c-eb495d3437a2', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'eau_boisson', 'B1', 'Au moins un point d''eau de boisson existe dans l''enceinte de l''établissement', 1, TRUE),
  ('019a7c3e-8002-7027-9d4e-83ee10d13958', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'eau_boisson', 'B2', 'La source est améliorée (réseau, forage, puits protégé, citerne)', 2, TRUE),
  ('019a7c3e-8003-70c6-990d-8d6e0d57462f', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'eau_boisson', 'B3', 'L''eau est disponible au moment de la visite', 3, TRUE),
  ('019a7c3e-8004-74e0-81fd-e2d44cae7be7', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'eau_boisson', 'B4', 'Le nombre de points d''eau fonctionnels respecte la norme (ratio section A)', 4, TRUE),
  ('019a7c3e-8005-7a71-ab7d-dc8fbe51a7f1', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'eau_boisson', 'B5', 'L''eau stockée est dans des récipients propres, couverts et munis d''un robinet', 5, TRUE),
  ('019a7c3e-8006-7811-acd4-6f21f1722c8d', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'eau_boisson', 'B6', 'Les élèves boivent avec un gobelet ou une gourde personnels (pas de gobelet commun)', 6, TRUE),
  ('019a7c3e-8007-7cd2-8300-d8f67ce086c8', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'eau_boisson', 'B7', 'Les abords du point d''eau sont propres, drainés, sans eau stagnante', 7, TRUE),
  ('019a7c3e-8008-7551-abca-4863ba44a587', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'eau_boisson', 'B8', 'Le point d''eau est protégé (margelle, couvercle, clôture si puits ou forage)', 8, TRUE),
  ('019a7c3e-8009-72a7-b98d-e076dbd99d30', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'eau_boisson', 'B9', 'Un programme d''entretien existe et le nettoyage des réservoirs est daté', 9, TRUE),
  ('019a7c3e-800a-77b5-b015-ec3bcc540450', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'eau_boisson', 'B10', 'La qualité de l''eau est suivie (contrôle ou traitement daté du mois en cours)', 10, TRUE),
  ('019a7c3e-800b-7c97-994b-866050526201', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'eau_boisson', 'B11', 'Le point d''eau est accessible aux plus petits et aux élèves handicapés', 11, TRUE),
  ('019a7c3e-800c-7708-aa59-6af6bcb2b3f5', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'eau_boisson', 'B12', 'Aucune fuite ni gaspillage d''eau n''est constaté', 12, TRUE),
  ('019a7c3e-800d-7776-8651-d66d49461da4', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C1', 'Des latrines améliorées existent et sont utilisables le jour de la visite', 1, TRUE),
  ('019a7c3e-800e-7003-af77-b344284db68e', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C2', 'Les latrines des filles sont séparées de celles des garçons et signalées', 2, TRUE),
  ('019a7c3e-800f-7ac5-bd0a-2013d92b1f21', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C3', 'Les latrines du personnel sont distinctes de celles des élèves', 3, TRUE),
  ('019a7c3e-8010-7f93-97c7-24fef9a12f8a', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C4', 'Le nombre de cabines fonctionnelles respecte la norme (ratio section A)', 4, TRUE),
  ('019a7c3e-8011-762d-9457-3dddad91301f', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C5', 'Les urinoirs des garçons sont en nombre suffisant', 5, TRUE),
  ('019a7c3e-8012-7535-85ff-9499dda39a59', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C6', 'Au moins une cabine est accessible aux personnes à mobilité réduite (rampe, porte large)', 6, TRUE),
  ('019a7c3e-8013-7de0-85d6-855bf0f676a6', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C7', 'Les latrines sont à l''écart des classes et du point d''eau, dans un lieu discret mais surveillable', 7, TRUE),
  ('019a7c3e-8014-79b3-8fe9-80e8b6861638', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C8', 'La toiture est en bon état (sans fuite)', 8, TRUE),
  ('019a7c3e-8015-7b6b-ad96-bc2a9e239f36', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C9', 'Murs et portes sont opaques, sans trou ni interstice', 9, TRUE),
  ('019a7c3e-8016-7237-b651-cafb04bb5c14', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C10', 'Chaque porte ferme de l''intérieur (serrure, verrou ou crochet)', 10, TRUE),
  ('019a7c3e-8017-78c8-a95b-d757999f0fdb', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C11', 'De l''eau est disponible dans chaque bloc (robinet ou récipient rempli)', 11, TRUE),
  ('019a7c3e-8018-7ee4-b95c-2c4ec3e47df5', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C12', 'Du papier hygiénique ou un moyen de nettoyage est disponible', 12, TRUE),
  ('019a7c3e-8019-7d9a-a70a-aac8f8ddabfa', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C13', 'Les eaux usées sont bien évacuées (fosse non pleine, aucun débordement)', 13, TRUE),
  ('019a7c3e-801a-7878-8d0a-7c6ef9278f96', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C14', 'Les cabines sont aérées et éclairées', 14, TRUE),
  ('019a7c3e-801b-7e60-8360-8ba7a4b07f23', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C15', 'Cuvettes et dalles sont propres', 15, TRUE),
  ('019a7c3e-801c-7007-ad88-36c6946a37c3', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C16', 'Aucune matière fécale, urine ou crachat visible', 16, TRUE),
  ('019a7c3e-801d-764e-96e7-8078ca41ca4a', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C17', 'Aucun déchet ni toile d''araignée', 17, TRUE),
  ('019a7c3e-801e-70c7-a7ea-4ffbc3fd5b9a', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C18', 'Aucune eau stagnante ni mauvaise odeur', 18, TRUE),
  ('019a7c3e-801f-73b8-b19c-2963c69dfb37', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C19', 'Aucune présence de mouches ou de cafards', 19, TRUE),
  ('019a7c3e-8020-7599-8ffe-c4acd38c7e7f', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C20', 'Un responsable du nettoyage est désigné et le nettoyage est quotidien', 20, TRUE),
  ('019a7c3e-8021-7e5d-8d02-1293efd2918d', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C21', 'Le matériel d''entretien est disponible (balai, seau, gants, détergent ou eau de Javel)', 21, TRUE),
  ('019a7c3e-8022-7363-a3d1-2170dc72290e', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'latrines', 'C22', 'Aucune trace de défécation à l''air libre dans l''enceinte', 22, TRUE),
  ('019a7c3e-8023-7691-8a3a-8478a511d50a', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_mains', 'D1', 'Au moins un dispositif de lavage des mains (DLM) avec eau ET savon fonctionne le jour de la visite', 1, TRUE),
  ('019a7c3e-8024-7ed0-9911-3d37e8525f11', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_mains', 'D2', 'Un DLM est installé à la sortie de chaque bloc de latrines', 2, TRUE),
  ('019a7c3e-8025-7440-b789-903d1138769a', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_mains', 'D3', 'Un DLM est installé près de la cantine ou de la zone de vente d''aliments', 3, TRUE),
  ('019a7c3e-8026-7d5d-bd6f-a58f4a404500', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_mains', 'D4', 'Le nombre de DLM fonctionnels respecte la norme (ratio section A)', 4, TRUE),
  ('019a7c3e-8027-75cf-9fed-3a3f4d28a5d0', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_mains', 'D5', 'Du savon est présent sur chaque DLM au moment de la visite', 5, TRUE),
  ('019a7c3e-8028-785e-ac9a-9b652e13e7b4', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_mains', 'D6', 'Le savon est renouvelé régulièrement (stock ou registre d''approvisionnement)', 6, TRUE),
  ('019a7c3e-8029-70c4-af86-51078d31c26a', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_mains', 'D7', 'Les eaux usées des DLM sont évacuées (aire d''infiltration, pas de bourbier)', 7, TRUE),
  ('019a7c3e-802a-7977-886d-8fd128819537', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_mains', 'D8', 'Les DLM sont à une hauteur adaptée à la taille des élèves', 8, TRUE),
  ('019a7c3e-802b-7101-abb4-4da9e3008069', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_mains', 'D9', 'Des affiches sur le lavage des mains sont visibles par les élèves', 9, TRUE),
  ('019a7c3e-802c-71d0-8a9c-09f09b1638bf', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_mains', 'D10', 'Une séance collective de lavage des mains est organisée chaque jour', 10, TRUE),
  ('019a7c3e-802d-7b5c-a62a-7f65b4d829a9', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_mains', 'D11', 'Les élèves interrogés citent au moins 3 moments clés du lavage des mains', 11, TRUE),
  ('019a7c3e-802e-72a5-a671-c56114c1e7f3', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_mains', 'D12', 'Les élèves interrogés montrent correctement la technique', 12, TRUE),
  ('019a7c3e-802f-7f78-89e1-2fde4055ba0e', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_menstruelle', 'E1', 'Au moins une cabine filles dispose d''eau à l''intérieur (robinet bas ou tablette pour récipient) et d''une évacuation au sol', 1, TRUE),
  ('019a7c3e-8030-7fcd-87f1-f3416ec1371e', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_menstruelle', 'E2', 'Chaque cabine filles a une poubelle munie d''un couvercle', 2, TRUE),
  ('019a7c3e-8031-7269-953d-06569f79d7c6', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_menstruelle', 'E3', 'Les protections usagées sont éliminées de façon sûre (incinérateur, fosse dédiée ou collecte)', 3, TRUE),
  ('019a7c3e-8032-71ae-b74f-174203d15dc5', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_menstruelle', 'E4', 'Un crochet ou une étagère permet de poser les effets personnels', 4, TRUE),
  ('019a7c3e-8033-74d8-bf72-83b2336b24df', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_menstruelle', 'E5', 'Une affiche indique de jeter les protections dans la poubelle et non dans la fosse', 5, TRUE),
  ('019a7c3e-8034-787c-8d2b-9720bfbf3ea7', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_menstruelle', 'E6', 'Des serviettes hygiéniques de dépannage sont disponibles dans l''établissement', 6, TRUE),
  ('019a7c3e-8035-796a-90d0-516d2ce6457f', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_menstruelle', 'E7', 'Une personne référente (enseignante ou éducatrice) est identifiée pour les filles', 7, TRUE),
  ('019a7c3e-8036-77c1-86b1-7ec3b37576d1', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_menstruelle', 'E8', 'Une séance d''éducation à l''hygiène menstruelle a eu lieu cette année scolaire', 8, TRUE),
  ('019a7c3e-8037-7def-8945-91898d047d05', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'hygiene_menstruelle', 'E9', 'Les filles interrogées déclarent pouvoir se changer à l''école sans gêne', 9, TRUE),
  ('019a7c3e-8038-794f-9a35-ed22e746572e', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cour_dechets', 'F1', 'Les poubelles sont en nombre suffisant dans la cour', 1, TRUE),
  ('019a7c3e-8039-7488-8449-99a8f6f1a254', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cour_dechets', 'F2', 'Aucun dépôt d''ordures dans la cour ni aux abords immédiats', 2, TRUE),
  ('019a7c3e-803a-7d88-8ca6-2a4245423f97', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cour_dechets', 'F3', 'Un site de regroupement des déchets existe, éloigné des classes et de la cantine', 3, TRUE),
  ('019a7c3e-803b-7a9a-8688-116f9c494257', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cour_dechets', 'F4', 'Les déchets sont collectés au moins tous les 3 jours et éliminés (enlèvement, incinérateur, fosse)', 4, TRUE),
  ('019a7c3e-803c-7673-b4dc-06290c7720f7', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cour_dechets', 'F5', 'Aucun brûlage de déchets à l''air libre près des classes', 5, TRUE),
  ('019a7c3e-803d-7f1a-9552-37c29bb9afd8', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cour_dechets', 'F6', 'Le gazon est taillé et il n''y a pas de broussailles', 6, TRUE),
  ('019a7c3e-803e-72c5-8330-91c1594dde66', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cour_dechets', 'F7', 'Aucun gîte larvaire (eau stagnante, pneus, boîtes, récipients abandonnés)', 7, TRUE),
  ('019a7c3e-803f-787f-905c-90f921d30c06', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cour_dechets', 'F8', 'Les caniveaux sont propres et les eaux de pluie s''évacuent', 8, TRUE),
  ('019a7c3e-8040-7696-95a6-e1db328db066', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cour_dechets', 'F9', 'Aucun animal en divagation ni déjection animale dans la cour', 9, TRUE),
  ('019a7c3e-8041-7f67-8068-05456ec21939', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cour_dechets', 'F10', 'Aucun objet dangereux au sol (verre, ferraille, objets tranchants)', 10, TRUE),
  ('019a7c3e-8042-7943-9502-e0f793997029', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cour_dechets', 'F11', 'Une journée de salubrité a eu lieu au cours du mois écoulé (date : ____________)', 11, TRUE),
  ('019a7c3e-8043-7c49-bf79-aa7dd4c84cf1', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'salles_classe', 'G1', 'Chaque classe a une poubelle', 1, TRUE),
  ('019a7c3e-8044-7cd1-a88b-b0493590678d', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'salles_classe', 'G2', 'Les poubelles sont vidées', 2, TRUE),
  ('019a7c3e-8045-7a38-84c4-3163043460a1', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'salles_classe', 'G3', 'Le sol est balayé, sans déchets dans les rangées', 3, TRUE),
  ('019a7c3e-8046-77fd-bab0-29cb58814ca2', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'salles_classe', 'G4', 'L''effectif respecte la norme (préscolaire ≤ 25, primaire ≤ 50)', 4, TRUE),
  ('019a7c3e-8047-75a6-81fb-b24dbddef384', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'salles_classe', 'G5', 'Chaque élève a une place assise ; tables-bancs sans clous ni échardes', 5, TRUE),
  ('019a7c3e-8048-7c66-9c3f-d069df826d60', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'salles_classe', 'G6', 'L''aération est suffisante (fenêtres ouvrantes, non obstruées)', 6, TRUE),
  ('019a7c3e-8049-78f9-895b-c54acf6b5158', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'salles_classe', 'G7', 'L''éclairage naturel permet de lire au fond de la classe', 7, TRUE),
  ('019a7c3e-804a-7972-b2fa-3ae3180eb0b1', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'salles_classe', 'G8', 'Au moins deux ampoules fonctionnent par classe (NA sans électricité)', 8, TRUE),
  ('019a7c3e-804b-74b2-a8ec-c6abfd63f33b', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'salles_classe', 'G9', 'La toiture et le plafond sont sans fuite ni trou', 9, TRUE),
  ('019a7c3e-804c-7df8-893f-b5f9ee5a4c9b', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'salles_classe', 'G10', 'Murs et sol sont sans fissure dangereuse', 10, TRUE),
  ('019a7c3e-804d-7bb3-b5a1-b85c2e9e9fee', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'salles_classe', 'G11', 'Le tableau est en bon état et lisible de tous les rangs', 11, TRUE),
  ('019a7c3e-804e-7a95-9fb9-b5c5f03c13db', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'salles_classe', 'G12', 'Aucun fil électrique dénudé ni prise accessible non protégée', 12, TRUE),
  ('019a7c3e-804f-74c9-8f6a-c8574e03ad24', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'salles_classe', 'G13', 'Aucun nuisible visible (chauves-souris, rongeurs, termites, nids)', 13, TRUE),
  ('019a7c3e-8050-7d4c-a1b1-523b2a8a0e5b', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cantine_vente', 'H1', 'La cuisine est un local couvert, propre et éloigné des latrines', 1, TRUE),
  ('019a7c3e-8051-7f17-9bac-64ea205a016a', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cantine_vente', 'H2', 'Les vivres sont stockés sur palettes, au sec, à l''abri des rongeurs, sans produit périmé', 2, TRUE),
  ('019a7c3e-8052-7169-bab7-c1f53abaac43', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cantine_vente', 'H3', 'De l''eau potable sert à la cuisson et à la vaisselle', 3, TRUE),
  ('019a7c3e-8053-7ad4-b2a4-8b4ee4cf8767', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cantine_vente', 'H4', 'Ustensiles et vaisselle sont propres et rangés à l''abri', 4, TRUE),
  ('019a7c3e-8054-787a-b326-a897f0e760d9', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cantine_vente', 'H5', 'Les plats préparés sont couverts et protégés des mouches', 5, TRUE),
  ('019a7c3e-8055-715d-80d7-e1785a8c5376', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cantine_vente', 'H6', 'Les cuisinières ont une visite médicale à jour (certificat de l''année)', 6, TRUE),
  ('019a7c3e-8056-7835-8264-da39d900127c', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cantine_vente', 'H7', 'Les cuisinières portent une tenue propre (tablier, coiffe), ongles courts', 7, TRUE),
  ('019a7c3e-8057-766b-ac75-4cfeb0105fce', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cantine_vente', 'H8', 'Les élèves se lavent les mains au savon avant le repas', 8, TRUE),
  ('019a7c3e-8058-7d3e-b7bb-90ca5d23f3de', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cantine_vente', 'H9', 'La fumée de cuisson n''envahit pas les salles de classe', 9, TRUE),
  ('019a7c3e-8059-7813-b972-5c9d571ccabe', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cantine_vente', 'H10', 'Les restes alimentaires sont éliminés le jour même', 10, TRUE),
  ('019a7c3e-805a-77ea-b9e8-b1a6eb270afb', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cantine_vente', 'H11', 'Les vendeuses sont recensées et installées dans un espace aménagé et propre', 11, TRUE),
  ('019a7c3e-805b-7018-859d-76b059ce571d', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cantine_vente', 'H12', 'Les vendeuses ont une visite médicale à jour', 12, TRUE),
  ('019a7c3e-805c-7e31-8901-66a4fb787194', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cantine_vente', 'H13', 'Les aliments sont couverts et posés en hauteur, jamais à même le sol', 13, TRUE),
  ('019a7c3e-805d-7f64-95f3-c0a7756d7039', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cantine_vente', 'H14', 'Les vendeuses servent avec un ustensile et ont une tenue propre', 14, TRUE),
  ('019a7c3e-805e-722a-ae42-a01f7384e7ec', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'cantine_vente', 'H15', 'Aucune vente d''alcool, de tabac ou d''aliments avariés aux abords', 15, TRUE),
  ('019a7c3e-805f-7169-980c-95eede69b4d5', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'securite_environnement', 'I1', 'Une clôture empêche le passage incontrôlé d''animaux et de personnes', 1, TRUE),
  ('019a7c3e-8060-7a02-a1b8-4819bb715cec', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'securite_environnement', 'I2', 'Le portail est fermé pendant les cours et les entrées sont contrôlées', 2, TRUE),
  ('019a7c3e-8061-7559-b68c-5f05e138f592', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'securite_environnement', 'I3', 'L''établissement dispose d''au moins un gardien', 3, TRUE),
  ('019a7c3e-8062-7460-b207-72808a6cadae', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'securite_environnement', 'I4', 'Aucun bâtiment utilisé ne présente de risque d''effondrement (murs fissurés, toiture instable)', 4, TRUE),
  ('019a7c3e-8063-754a-a98a-e4f23eefd27d', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'securite_environnement', 'I5', 'Aucun puits, fosse ou trou non couvert dans l''enceinte', 5, TRUE),
  ('019a7c3e-8064-7135-9826-859b90ba7fd3', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'securite_environnement', 'I6', 'Le compteur et les câbles électriques extérieurs sont hors de portée des élèves', 6, TRUE),
  ('019a7c3e-8065-7721-978e-c04b7b20b157', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'securite_environnement', 'I7', 'L''aire de jeux et les équipements sportifs sont sans danger', 7, TRUE),
  ('019a7c3e-8066-73a0-a1b7-261c13b2b7bf', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'securite_environnement', 'I8', 'Les abords routiers sont sécurisés (panneaux, ralentisseurs, passage piéton)', 8, TRUE),
  ('019a7c3e-8067-73ba-bba6-a439c6948be0', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'securite_environnement', 'I9', 'Un moyen de lutte contre l''incendie existe près de la cuisine et des laboratoires', 9, TRUE),
  ('019a7c3e-8068-7914-8a61-38f7b0b05894', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'securite_environnement', 'I10', 'Les produits dangereux (Javel, produits de laboratoire, carburant) sont sous clé', 10, TRUE),
  ('019a7c3e-8069-7177-8a0c-b0016cfe21d5', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'securite_environnement', 'I11', 'Un préau ou un espace ombragé accueille les élèves pendant la récréation', 11, TRUE),
  ('019a7c3e-806a-7ecc-927c-065005214bde', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'securite_environnement', 'I12', 'Aucune nuisance majeure à proximité (dépotoir, débit de boissons, garage, bruit)', 12, TRUE),
  ('019a7c3e-806b-7f3d-a535-44bdf43f44d1', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'sante_scolaire', 'J1', 'Une boîte à pharmacie complète et non périmée est disponible (antiseptique, compresses, gants, pansements, thermomètre)', 1, TRUE),
  ('019a7c3e-806c-7fa1-8e5d-6b6e6673aeb5', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'sante_scolaire', 'J2', 'Un espace de repos permet d''isoler un élève malade', 2, TRUE),
  ('019a7c3e-806d-7ae4-90d4-362fca6eb9b5', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'sante_scolaire', 'J3', 'Un point focal santé (enseignant référent) est désigné', 3, TRUE),
  ('019a7c3e-806e-73ec-a540-beb248e27fe4', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'sante_scolaire', 'J4', 'Les numéros d''urgence sont affichés (ESPC, SSSU-SAJ, SAMU 185, sapeurs-pompiers 180)', 4, TRUE),
  ('019a7c3e-806f-7594-8826-035ab7688586', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'sante_scolaire', 'J5', 'Un registre des soins et des évacuations est tenu à jour', 5, TRUE),
  ('019a7c3e-8070-7b68-8cd0-c464eedfd979', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'sante_scolaire', 'J6', 'La visite médicale systématique des classes cibles est faite ou programmée cette année', 6, TRUE),
  ('019a7c3e-8071-7fa7-9252-29a9d7db7f3b', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'sante_scolaire', 'J7', 'Les élèves atteints de maladie chronique (asthme, drépanocytose, épilepsie, diabète) sont connus et la conduite à tenir est affichée', 7, TRUE),
  ('019a7c3e-8072-7223-aeda-844055e28a2d', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'sante_scolaire', 'J8', 'Les carnets de vaccination des nouveaux élèves sont vérifiés', 8, TRUE),
  ('019a7c3e-8073-79d2-a28c-3d03e529a5d0', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'sante_scolaire', 'J9', 'Le déparasitage de masse a été réalisé selon le calendrier national', 9, TRUE),
  ('019a7c3e-8074-7e7e-821d-c4008f66bf4c', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'sante_scolaire', 'J10', 'Un club santé ou d''hygiène a mené au moins une activité ce trimestre', 10, TRUE),
  ('019a7c3e-8075-77aa-a083-cb6e7aee70de', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'sante_scolaire', 'J11', 'Des affiches d''éducation à la santé sont visibles (hygiène, paludisme, nutrition, IST/VIH au secondaire)', 11, TRUE),
  ('019a7c3e-8076-7fa8-8c6a-e129953147c9', 1, '2026-11-13T08:00:00Z', '2026-11-13T08:00:00Z', 'sante_scolaire', 'J12', 'Le personnel sait vers quelle structure orienter un élève malade', 12, TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO sync_changement (table_name, record_id, scope, version)
SELECT 'critere_inspection', x.id, NULL, x.version FROM critere_inspection x
WHERE x.rubrique IN ('eau_boisson', 'latrines', 'hygiene_mains', 'hygiene_menstruelle', 'cour_dechets', 'salles_classe',
                     'cantine_vente', 'securite_environnement', 'sante_scolaire')
  AND NOT EXISTS (SELECT 1 FROM sync_changement s WHERE s.table_name = 'critere_inspection' AND s.record_id = x.id)
ORDER BY x.rubrique, x.ordre;
