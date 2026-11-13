/// Parties de la grille d'inspection nationale sur le téléphone, en dehors
/// des critères : identification de la visite, section A (structure,
/// effectifs, équipements, ratios), scores, niveaux de service, constats et
/// plan d'action. Chaque modification appelle [onChange] (enregistrement de
/// l'ébauche et nouveau calcul des scores).
library;

import 'package:flutter/material.dart';
import 'package:sssu_core/sssu_core.dart';

import '../ui/etablissements.dart' show formaterDateFr;

Color couleurClassement(ClassementGrille? c) => switch (c) {
      ClassementGrille.satisfaisant => Colors.green.shade700,
      ClassementGrille.acceptable => Colors.amber.shade800,
      ClassementGrille.insuffisant => Colors.orange.shade800,
      ClassementGrille.critique => Colors.red.shade700,
      null => Colors.grey,
    };

String _pc(double? v) => v == null ? '—' : '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1).replaceAll('.', ',')} %';

class _Texte extends StatelessWidget {
  final String libelle;
  final String valeur;
  final bool actif;
  final ValueChanged<String> onChanged;
  final int lignes;
  final TextInputType? clavier;
  const _Texte(this.libelle, this.valeur, this.actif, this.onChanged, {this.lignes = 1, this.clavier});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          initialValue: valeur,
          enabled: actif,
          keyboardType: clavier,
          maxLines: lignes == 1 ? 1 : null,
          minLines: lignes == 1 ? 1 : lignes,
          decoration: InputDecoration(labelText: libelle, isDense: true),
          onChanged: onChanged,
        ),
      );
}

class _Nombre extends StatelessWidget {
  final String libelle;
  final int? valeur;
  final bool actif;
  final ValueChanged<int?> onChanged;
  const _Nombre(this.libelle, this.valeur, this.actif, this.onChanged);

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: valeur?.toString() ?? '',
        enabled: actif,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: InputDecoration(labelText: libelle, isDense: true),
        onChanged: (t) => onChanged(int.tryParse(t.trim())),
      );
}

/// Choix à une réponse (cases ☐ de la grille).
class ChoixGrille extends StatelessWidget {
  final String libelle;
  final List<Choix> choix;
  final String? valeur;
  final bool actif;
  final ValueChanged<String?> onChanged;
  const ChoixGrille(this.libelle, this.choix, this.valeur, this.actif, this.onChanged, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(libelle, style: const TextStyle(fontSize: 13, color: Colors.black54)),
          Wrap(spacing: 6, runSpacing: 2, children: [
            for (final c in choix)
              ChoiceChip(
                label: Text(c.libelle, style: const TextStyle(fontSize: 12)),
                selected: valeur == c.code,
                onSelected: actif ? (s) => onChanged(s ? c.code : null) : null,
              ),
          ]),
        ]),
      );
}

Future<DateTime?> _date(BuildContext context, DateTime? initiale, {bool futur = false}) async {
  final d = await showDatePicker(
    context: context,
    initialDate: initiale ?? DateTime.now(),
    firstDate: DateTime(2015),
    lastDate: futur ? DateTime.now().add(const Duration(days: 730)) : DateTime.now(),
  );
  return d == null ? null : DateTime.utc(d.year, d.month, d.day);
}

class _ChampDate extends StatelessWidget {
  final String libelle;
  final DateTime? valeur;
  final bool actif;
  final bool futur;
  final ValueChanged<DateTime?> onChanged;
  const _ChampDate(this.libelle, this.valeur, this.actif, this.onChanged, {this.futur = false});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text('$libelle : ${valeur == null ? '—' : formaterDateFr(valeur!)}')),
        if (actif) ...[
          TextButton(
            onPressed: () async {
              final d = await _date(context, valeur, futur: futur);
              if (d != null) onChanged(d);
            },
            child: const Text('Choisir'),
          ),
          if (valeur != null) IconButton(onPressed: () => onChanged(null), icon: const Icon(Icons.clear, size: 18)),
        ],
      ]);
}

// ------------------------------------------------------------------- scores

class CarteScores extends StatelessWidget {
  final FormulaireInspection f;
  const CarteScores(this.f, {super.key});

  @override
  Widget build(BuildContext context) {
    final ev = f.evaluation();
    final cl = ev.classement;
    final couleur = couleurClassement(cl);
    return Card(
      color: couleur.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Score global : ${_pc(ev.scoreGlobal)}${cl == null ? '' : ' · ${cl.libelle} (${cl.couleur})'}',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: couleur)),
          if (ev.plafonne)
            const Text('Classement plafonné à « Insuffisant » : critère ★ non conforme.',
                style: TextStyle(color: Colors.red, fontSize: 13)),
          if (ev.critiquesNonConformes.isNotEmpty)
            Text('Critère(s) ★ NC : ${ev.critiquesNonConformes.map((c) => c.code).join(', ')}',
                style: const TextStyle(fontSize: 13)),
          if (cl != null) Text('Conduite à tenir : ${cl.conduite}', style: const TextStyle(fontSize: 13)),
          Text('${f.nombreRepondus} / ${f.criteres.length} critères cotés', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final d in ev.domaines)
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text('${d.rubrique.lettre} ${_pc(d.score)}', style: const TextStyle(fontSize: 12)),
                backgroundColor: d.score == null ? null : couleurClassement(ClassementGrille.depuisScore(d.score!)).withOpacity(0.15),
              ),
          ]),
        ]),
      ),
    );
  }
}

// ----------------------------------------------------------- identification

class SectionIdentification extends StatelessWidget {
  final DonneesGrille g;
  final bool actif;
  final VoidCallback onChange;
  const SectionIdentification(this.g, this.actif, this.onChange, {super.key});

  @override
  Widget build(BuildContext context) {
    void m(void Function() f) {
      f();
      onChange();
    }

    return Card(
      child: ExpansionTile(
        title: const Text('Identification de la visite'),
        subtitle: Text(libelleChoix(typesVisite, g.typeVisite) ?? 'Type de visite à préciser'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          _Texte('Fiche n°', g.ficheNumero, actif, (v) => m(() => g.ficheNumero = v)),
          _Texte('DRENA / IEPP', g.drenaIepp, actif, (v) => m(() => g.drenaIepp = v)),
          _Texte('Localité / quartier', g.localite, actif, (v) => m(() => g.localite = v)),
          _Texte('Aire sanitaire (ESPC de rattachement)', g.aireSanitaire, actif, (v) => m(() => g.aireSanitaire = v)),
          _Texte('Chef d\'établissement (nom, téléphone)', g.chefEtablissement, actif,
              (v) => m(() => g.chefEtablissement = v)),
          _Texte('Personne ayant accompagné l\'inspection (nom, fonction)', g.accompagnateur, actif,
              (v) => m(() => g.accompagnateur = v)),
          Row(children: [
            Expanded(child: _Texte('Heure d\'arrivée', g.heureArrivee, actif, (v) => m(() => g.heureArrivee = v))),
            const SizedBox(width: 12),
            Expanded(child: _Texte('Heure de départ', g.heureDepart, actif, (v) => m(() => g.heureDepart = v))),
          ]),
          ChoixGrille('Type de visite', typesVisite, g.typeVisite, actif, (v) => m(() => g.typeVisite = v)),
          _ChampDate('Dernière inspection sanitaire', g.dateDerniereInspection, actif,
              (v) => m(() => g.dateDerniereInspection = v)),
          _Texte('Équipe d\'inspection (noms, fonctions)', g.equipe, actif, (v) => m(() => g.equipe = v), lignes: 2),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- section A

class SectionStructure extends StatelessWidget {
  final FormulaireInspection f;
  final bool actif;
  final VoidCallback onChange;
  const SectionStructure(this.f, this.actif, this.onChange, {super.key});

  @override
  Widget build(BuildContext context) {
    final g = f.grille;
    void m(void Function() x, {bool structure = false}) {
      x();
      // Choix de structure : cotation NA des critères qui ne s'appliquent pas.
      if (structure) {
        final n = f.appliquerNonApplicablesAutomatiques();
        if (n > 0) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('$n critère(s) cotés « Non applicable » d\'après la structure (motif en observation).')));
        }
      }
      onChange();
    }

    return Card(
      child: ExpansionTile(
        title: const Text('A. Structure et effectifs (non coté)'),
        subtitle: const Text('Sert à calculer les ratios des sections B à E'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          ChoixGrille('Ordre d\'enseignement', ordresEnseignement, g.ordreEnseignement, actif,
              (v) => m(() => g.ordreEnseignement = v, structure: true)),
          ChoixGrille('Statut', statutsGrille, g.statut, actif, (v) => m(() => g.statut = v)),
          ChoixGrille('Fréquentation', frequentations, g.frequentation, actif,
              (v) => m(() => g.frequentation = v, structure: true)),
          ChoixGrille('Régime', regimes, g.regime, actif, (v) => m(() => g.regime = v)),
          ChoixGrille('Milieu', milieux, g.milieu, actif, (v) => m(() => g.milieu = v)),
          ChoixGrille('Électricité', electricites, g.electricite, actif,
              (v) => m(() => g.electricite = v, structure: true)),
          ChoixGrille('Cantine scolaire', const [Choix('oui', 'Oui'), Choix('non', 'Non')],
              g.cantine == null ? null : (g.cantine! ? 'oui' : 'non'), actif,
              (v) => m(() => g.cantine = v == null ? null : v == 'oui', structure: true)),
          const Divider(),
          const Text('Effectifs (garçons / hommes · filles / femmes)', style: TextStyle(fontWeight: FontWeight.w600)),
          for (final c in categoriesEffectifs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(flex: 3, child: Text(c.libelle, style: const TextStyle(fontSize: 13))),
                Expanded(
                    flex: 2,
                    child: _Nombre('G/H', g.effectifs[c.code]!.a, actif,
                        (v) => m(() => g.effectifs[c.code]!.a = v, structure: c.code == 'eleves'))),
                const SizedBox(width: 6),
                Expanded(
                    flex: 2,
                    child: _Nombre('F', g.effectifs[c.code]!.b, actif,
                        (v) => m(() => g.effectifs[c.code]!.b = v, structure: c.code == 'eleves'))),
                SizedBox(
                    width: 44,
                    child: Text('${g.effectifs[c.code]!.total ?? '—'}', textAlign: TextAlign.right)),
              ]),
            ),
          const Divider(),
          const Text('Inventaire des équipements (existant · fonctionnel)', style: TextStyle(fontWeight: FontWeight.w600)),
          for (final e in equipementsGrille)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(
                  flex: 3,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.libelle, style: const TextStyle(fontSize: 13)),
                    if (e.norme != '—') Text(e.norme, style: const TextStyle(fontSize: 11, color: Colors.black45)),
                  ]),
                ),
                Expanded(
                    flex: 2,
                    child: _Nombre('Exist.', g.equipements[e.code]!.a, actif, (v) => m(() => g.equipements[e.code]!.a = v))),
                const SizedBox(width: 6),
                Expanded(
                    flex: 2,
                    child: e.sansFonctionnel
                        ? const SizedBox()
                        : _Nombre('Fonct.', g.equipements[e.code]!.b, actif, (v) => m(() => g.equipements[e.code]!.b = v))),
              ]),
            ),
          const Divider(),
          const Text('Ratios calculés', style: TextStyle(fontWeight: FontWeight.w600)),
          for (final r in g.ratios)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(r.libelle),
              subtitle: Text('${r.calcul} · seuil : ${r.seuil}'),
              trailing: Text(
                r.valeur == null ? '—' : r.valeur!.toStringAsFixed(r.valeur! == r.valeur!.roundToDouble() ? 0 : 1).replaceAll('.', ','),
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: r.horsNorme ? Colors.red.shade700 : null, fontSize: 15),
              ),
            ),
        ],
      ),
    );
  }
}

/// Précisions demandées en tête de certaines sections (source d'eau, type
/// de latrines, classes visitées, cuisinières et vendeuses).
List<Widget> precisionsSection(RubriqueInspection r, DonneesGrille g, bool actif, VoidCallback onChange) {
  void m(void Function() f) {
    f();
    onChange();
  }

  return switch (r) {
    RubriqueInspection.eauBoisson => [
        ChoixGrille('Source principale', sourcesEau, g.sourceEau, actif, (v) => m(() => g.sourceEau = v)),
      ],
    RubriqueInspection.latrines => [
        ChoixGrille('Type principal', typesLatrines, g.typeLatrine, actif, (v) => m(() => g.typeLatrine = v)),
      ],
    RubriqueInspection.courDechets => [
        _Texte('Date de la dernière journée de salubrité (F11)', g.dateJourneeSalubrite, actif,
            (v) => m(() => g.dateJourneeSalubrite = v)),
      ],
    RubriqueInspection.sallesClasse => [
        _Texte('Classes visitées', g.classesVisitees, actif, (v) => m(() => g.classesVisitees = v)),
      ],
    RubriqueInspection.cantineVente => [
        Row(children: [
          Expanded(child: _Nombre('Nombre de cuisinières', g.nbCuisinieres, actif, (v) => m(() => g.nbCuisinieres = v))),
          const SizedBox(width: 12),
          Expanded(child: _Nombre('Nombre de vendeuses', g.nbVendeuses, actif, (v) => m(() => g.nbVendeuses = v))),
        ]),
        const SizedBox(height: 8),
      ],
    _ => const [],
  };
}

// -------------------------------------------------------- niveaux de service

class SectionNiveauxService extends StatelessWidget {
  final FormulaireInspection f;
  final bool actif;
  final VoidCallback onChange;
  const SectionNiveauxService(this.f, this.actif, this.onChange, {super.key});

  @override
  Widget build(BuildContext context) => Card(
        child: ExpansionTile(
          title: const Text('Niveau de service eau, assainissement et hygiène'),
          subtitle: const Text('Définitions OMS/UNICEF reprises par les normes MENA'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            for (final d in DomaineService.values) ...[
              Builder(builder: (context) {
                final propose = niveauServicePropose(d, f.resultatsParCode, f.grille);
                final choisi = f.grille.niveauxService[d];
                return ChoixGrille(
                  '${d.libelle}${propose == null ? '' : ' — proposé : ${propose.libelle}'}',
                  [
                    for (final n in NiveauService.values)
                      Choix(n.code, '${n.libelle} : ${d.definitions[n.index]}'),
                  ],
                  (choisi ?? propose)?.code,
                  actif,
                  (v) {
                    f.grille.niveauxService[d] = NiveauService.depuisCode(v);
                    onChange();
                  },
                );
              }),
            ],
          ],
        ),
      );
}

// ------------------------------------------------------------------ constats

class SectionConstats extends StatefulWidget {
  final FormulaireInspection f;
  final bool actif;
  final VoidCallback onChange;
  final String? nomInspecteur;
  const SectionConstats(this.f, this.actif, this.onChange, {super.key, this.nomInspecteur});

  @override
  State<SectionConstats> createState() => _SectionConstatsState();
}

class _SectionConstatsState extends State<SectionConstats> {
  DonneesGrille get g => widget.f.grille;

  @override
  void initState() {
    super.initState();
    if (g.chefEquipe.isEmpty && widget.nomInspecteur != null && widget.actif) g.chefEquipe = widget.nomInspecteur!;
  }

  void _m(void Function() f) {
    setState(f);
    widget.onChange();
  }

  /// Problèmes proposés d'après les critères NC (★ d'abord), à compléter.
  void _proposer() {
    final deja = g.problemes.map((p) => p.criteres).join(' ');
    final nc = [
      for (final c in widget.f.criteres)
        if (widget.f.reponses[c.id]?.resultat == ResultatInspection.nonConforme && !deja.contains(c.code)) c
    ]..sort((a, b) => (b.critique ? 1 : 0) - (a.critique ? 1 : 0));
    final places = g.problemes.length >= 5 ? 0 : 5 - g.problemes.length;
    _m(() {
      for (final c in nc.take(places)) {
        final obs = widget.f.reponses[c.id]?.observation.trim() ?? '';
        g.problemes.add(ProblemeConstate(probleme: obs.isEmpty ? c.libelle : '${c.libelle} ($obs)', criteres: c.code));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final actif = widget.actif;
    return Card(
      child: ExpansionTile(
        title: const Text('Constats, recommandations et signatures'),
        subtitle: Text('${g.problemes.length} problème(s) prioritaire(s)'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          _Texte('Points forts', g.pointsForts, actif, (v) {
            g.pointsForts = v;
            widget.onChange();
          }, lignes: 3),
          Row(children: [
            const Expanded(child: Text('Problèmes prioritaires', style: TextStyle(fontWeight: FontWeight.w600))),
            if (actif)
              TextButton.icon(
                  onPressed: _proposer, icon: const Icon(Icons.auto_fix_high), label: const Text('Depuis les NC')),
            if (actif)
              IconButton(
                  tooltip: 'Ajouter', onPressed: () => _m(() => g.problemes.add(ProblemeConstate())), icon: const Icon(Icons.add)),
          ]),
          for (final (i, p) in g.problemes.indexed)
            Card(
              key: ObjectKey(p),
              color: Colors.grey.shade50,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  Row(children: [
                    Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (actif)
                      IconButton(
                          onPressed: () => _m(() => g.problemes.remove(p)), icon: const Icon(Icons.delete_outline, size: 20)),
                  ]),
                  _Texte('Problème constaté', p.probleme, actif, (v) {
                    p.probleme = v;
                    widget.onChange();
                  }, lignes: 2),
                  _Texte('N° du critère', p.criteres, actif, (v) {
                    p.criteres = v;
                    widget.onChange();
                  }),
                  _Texte('Mesure recommandée', p.mesure, actif, (v) {
                    p.mesure = v;
                    widget.onChange();
                  }, lignes: 2),
                  Row(children: [
                    Expanded(
                        child: _Texte('Responsable', p.responsable, actif, (v) {
                      p.responsable = v;
                      widget.onChange();
                    })),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _Texte('Délai', p.delai, actif, (v) {
                      p.delai = v;
                      widget.onChange();
                    })),
                  ]),
                  ChoixGrille('Réalisé à la contre-visite', const [Choix('oui', 'Oui'), Choix('non', 'Non')],
                      p.realise == null ? null : (p.realise! ? 'oui' : 'non'), actif,
                      (v) => _m(() => p.realise = v == null ? null : v == 'oui')),
                ]),
              ),
            ),
          _ChampDate('Date de la contre-visite', g.dateContreVisite, actif, (v) => _m(() => g.dateContreVisite = v),
              futur: true),
          _Texte('Chef de l\'équipe d\'inspection (nom)', g.chefEquipe, actif, (v) {
            g.chefEquipe = v;
            widget.onChange();
          }),
          const Text('Le chef d\'établissement signe et appose son cachet (« lu et approuvé ») sur le rapport imprimé.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }
}
