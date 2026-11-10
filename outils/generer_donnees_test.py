"""Génère sql/seed/donnees_test.sql : données FICTIVES, communes à SQLite et PostgreSQL."""
import random, uuid, sys, os, datetime

ROOT = sys.argv[1]
rnd = random.Random(20261110)
TS = '2026-11-10T08:00:00Z'
_ms = int(datetime.datetime(2026, 11, 10, 8, 0, tzinfo=datetime.timezone.utc).timestamp() * 1000)


def uid():
    """UUID version 7 déterministe (horodatage fixe + aléa à graine fixe)."""
    global _ms
    _ms += 1
    r = rnd.getrandbits(80)
    v = (_ms << 80) | r
    v &= ~(0xF << 76); v |= (0x7 << 76)          # version 7
    v &= ~(0x3 << 62); v |= (0x2 << 62)          # variante RFC 4122
    return str(uuid.UUID(int=v))


def q(v):
    if v is None:
        return 'NULL'
    if v is True:
        return 'TRUE'
    if v is False:
        return 'FALSE'
    if isinstance(v, (int, float)):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


out = ["-- Jeu de données de TEST : toutes les personnes et tous les établissements sont FICTIFS.",
       "-- Compatible SQLite (application mobile) et PostgreSQL (poste central).",
       "-- Les comptes utilisateurs ne sont pas créés ici : voir README (création du premier administrateur",
       "-- et comptes de test créés par le code, avec mots de passe hachés en Argon2id).",
       ""]


def ins(table, rows):
    if not rows:
        return
    cols = list(rows[0].keys())
    out.append(f"INSERT INTO {table} ({', '.join(cols)}) VALUES")
    out.append(",\n".join("  (" + ", ".join(q(r[c]) for c in cols) + ")" for r in rows) + ";")
    out.append("")


def base(**kw):
    d = {'id': uid(), 'version': 1, 'created_at': TS, 'updated_at': TS}
    d.update(kw)
    return d


annee = base(libelle='2026-2027', date_debut='2026-09-14', date_fin='2027-07-16', active=True)
ins('annee_scolaire', [annee])

etabs = [
    base(nom='EPP TEST Kouassi-Kouassikro A', code='TEST-EPP-A', type='primaire', statut='public',
         region="N'Zi", district_sanitaire='Kouassi-Kouassikro', localite='Kouassi-Kouassikro',
         responsable='Directeur fictif', telephone='0700000001'),
    base(nom='Collège TEST Kouassi-Kouassikro', code='TEST-COL-B', type='secondaire', statut='prive',
         region="N'Zi", district_sanitaire='Kouassi-Kouassikro', localite='Kouassi-Kouassikro',
         responsable='Principal fictif', telephone='0700000002'),
]
ins('etablissement', etabs)

classes_def = [(etabs[0], 'CE1 A', 'CE1', (2018, 2019)), (etabs[0], 'CM2 A', 'CM2', (2015, 2016)),
               (etabs[1], '6e 1', '6e', (2014, 2015)), (etabs[1], '3e 2', '3e', (2011, 2012))]
classes = [base(etablissement_id=e['id'], annee_scolaire_id=annee['id'], libelle=lib, niveau=niv)
           for e, lib, niv, _ in classes_def]
ins('classe', classes)

ROLES = [('admin', 'Administrateur'), ('medecin_chef', 'Médecin-Chef'), ('medecin', 'Médecin'),
         ('infirmier', 'Infirmier'), ('agent', 'Agent de santé')]
roles = {code: base(code=code, libelle=lib) for code, lib in ROLES}
ins('role', list(roles.values()))

# Doit rester identique à matriceParDefaut (sssu_core/lib/src/auth/permissions.dart).
MATRICE = {
    'admin': ['comptes.gerer', 'parametres.modifier', 'etablissement.gerer', 'etablissement.archiver',
              'import.executer', 'statistiques.consulter', 'sauvegarde.gerer', 'audit.consulter'],
    'medecin_chef': ['parametres.modifier', 'etablissement.gerer', 'import.executer', 'visite.saisir',
                     'visite.modifier_toutes', 'visite.valider', 'visite.rouvrir', 'photo.prendre',
                     'photo.voir_toutes', 'photo.telecharger', 'inspection.realiser', 'statistiques.consulter',
                     'rapport.exporter_nominatif', 'conflit.resoudre', 'audit.consulter'],
    'medecin': ['import.executer', 'visite.saisir', 'visite.modifier_siennes', 'visite.valider', 'photo.prendre',
                'photo.voir_toutes', 'inspection.realiser', 'statistiques.consulter', 'rapport.exporter_nominatif'],
    'infirmier': ['import.executer', 'visite.saisir', 'visite.modifier_siennes', 'photo.prendre',
                  'inspection.realiser'],
    'agent': ['visite.saisir', 'visite.modifier_siennes', 'photo.prendre', 'inspection.realiser'],
}
ins('role_permission', [base(role_id=roles[r]['id'], permission=p) for r, ps in MATRICE.items() for p in ps])

PATHOS = [('dermatoses', 'Dermatoses', False), ('gale', 'Gale', False), ('mycoses', 'Mycoses', False),
          ('asthme', 'Asthme', False), ('caries', 'Caries dentaires', False), ('gingivites', 'Gingivites', False),
          ('otites', 'Otites', False), ('baisse_acuite_visuelle', "Baisse de l'acuité visuelle", False),
          ('anemie_clinique', 'Anémie clinique', False), ('hernie', 'Hernie', False), ('ictere', 'Ictère', False),
          ('conjonctivite', 'Conjonctivite', False), ('handicap', 'Handicap', True),
          ('ist', 'Infections sexuellement transmissibles', False), ('grossesse', 'Grossesse', False),
          ('hematurie', 'Hématurie', False), ('autre', 'Autres pathologies', True)]
ins('pathologie', [base(code=c, libelle=l, active=True, ordre=i + 1, precision_requise=p)
                   for i, (c, l, p) in enumerate(PATHOS)])

CRITERES = [
    ('eau_potable', 'eau_disponibilite', "Eau potable disponible"),
    ('eau_potable', 'eau_accessibilite', "Point d'eau accessible aux élèves"),
    ('eau_potable', 'eau_qualite', "Qualité de l'eau (aspect, protection du point d'eau)"),
    ('toilettes', 'toilettes_nombre', "Nombre de toilettes suffisant"),
    ('toilettes', 'toilettes_proprete', "Propreté des toilettes"),
    ('toilettes', 'toilettes_fonctionnalite', "Toilettes fonctionnelles"),
    ('toilettes', 'toilettes_separation', "Séparation filles / garçons"),
    ('lavage_mains', 'lavage_dispositif', "Dispositif de lavage des mains"),
    ('lavage_mains', 'lavage_savon', "Savon disponible"),
    ('dechets', 'dechets_poubelles', "Poubelles en place"),
    ('dechets', 'dechets_collecte', "Collecte et évacuation des déchets"),
    ('environnement', 'env_cour', "Propreté de la cour"),
    ('environnement', 'env_salles', "Propreté des salles"),
    ('cantine', 'cantine_locaux', "Hygiène des locaux de la cantine"),
    ('cantine', 'cantine_aliments', "Hygiène des aliments"),
    ('vendeuses', 'vendeuses_hygiene', "Conditions d'hygiène des vendeuses"),
    ('vendeuses', 'vendeuses_visite', "Visite médicale des vendeuses"),
    ('infirmerie', 'infirmerie_disponible', "Infirmerie disponible"),
    ('infirmerie', 'infirmerie_fonctionnelle', "Infirmerie fonctionnelle"),
    ('securite', 'securite_batiments', "État des bâtiments"),
    ('securite', 'securite_risques', "Risques environnementaux maîtrisés"),
]
ins('critere_inspection', [base(rubrique=r, code=c, libelle=l, ordre=i + 1, actif=True)
                           for i, (r, c, l) in enumerate(CRITERES)])

PARAMS = [
    ('entete_ligne_1', 'MINISTÈRE EN CHARGE DE LA SANTÉ'),
    ('entete_ligne_2', "DIRECTION RÉGIONALE DE LA SANTÉ DU N'ZI"),
    ('entete_ligne_3', 'DISTRICT SANITAIRE DE KOUASSI-KOUASSIKRO'),
    ('entete_ligne_4', 'SERVICE DE SANTÉ SCOLAIRE ET UNIVERSITAIRE – SANTÉ ADOLESCENTS ET JEUNES (SSSU-SAJ)'),
    ('nom_medecin_chef', ''),
    ('verrouillage_mobile_minutes', '5'),
    ('verrouillage_windows_minutes', '15'),
    ('seuil_conformite_satisfaisant', '80'),
    ('seuil_conformite_moyen', '50'),
]
ins('parametre', [base(cle=k, valeur=v) for k, v in PARAMS])

NOMS = ['Kouassi', 'Konan', 'Kouadio', "N'Guessan", 'Yao', 'Koffi', 'Kouamé', 'Bamba', 'Traoré', 'Coulibaly',
        'Ouattara', 'Koné', 'Diallo', 'Touré', 'Assi', 'Aka', 'Brou', 'Ehui', 'Gnagne', 'Amani']
PRENOMS_F = ['Aya', 'Akissi', 'Adjoua', 'Amenan', 'Affoué', 'Ahou', 'Fatou', 'Mariam', 'Awa', 'Christelle',
             'Grâce', 'Estelle', 'Marie-Ange', 'Rokia', 'Salimata']
PRENOMS_M = ['Kouamé', 'Yao Jean', 'Koffi', 'Konan', 'Aboubacar', 'Ibrahim', 'Moussa', 'Serge', 'Hervé',
             'Jean-Marc', 'Didier', 'Lassina', 'Arnaud', 'Junior', 'Fabrice']
eleves, inscrs = [], []
used = set()
for (e, lib, niv, (y0, y1)), cl in zip(classes_def, classes):
    for i in range(30):
        sexe = 'F' if i % 2 == 0 else 'M'
        while True:
            nom = rnd.choice(NOMS)
            pre = rnd.choice(PRENOMS_F if sexe == 'F' else PRENOMS_M)
            if (nom, pre) not in used:
                used.add((nom, pre)); break
        y = rnd.choice([y0, y1]); m = rnd.randint(1, 12); d = rnd.randint(1, 28)
        mat = None if (lib == 'CE1 A' and i in (7, 19)) else f"{rnd.randint(10000000, 99999999)}{rnd.choice('ABCDEFGHJKLMNPQRSTUVWXYZ')}"
        el = base(matricule=mat, nom=nom.upper(), prenoms=pre, date_naissance=f"{y}-{m:02d}-{d:02d}",
                  sexe=sexe, telephone_contact=f"07{rnd.randint(10000000, 99999999)}")
        eleves.append(el)
        inscrs.append(base(eleve_id=el['id'], classe_id=cl['id'], annee_scolaire_id=annee['id'], statut='inscrit'))
ins('eleve', eleves)
ins('inscription', inscrs)

path = os.path.join(ROOT, 'sql/seed/donnees_test.sql')
os.makedirs(os.path.dirname(path), exist_ok=True)
open(path, 'w', encoding='utf-8').write("\n".join(out) + "\n")
print(len(eleves), 'élèves')
