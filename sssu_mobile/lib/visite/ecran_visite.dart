/// Formulaire de visite médicale (systématique ou d'aptitude), en rubriques :
/// A Identification · B Antécédents · C Examen clinique · D Examen physique ·
/// E Dépistage · [Vaccination : enfant du préscolaire] · [Vaccin HPV : fille
/// de 9 à 14 ans, visite systématique] · F Conclusion (et décision
/// d'aptitude) · Photos.
///
/// Sauvegarde automatique toutes les 30 secondes, à chaque changement de
/// rubrique, à la mise en arrière-plan et à la sortie de l'écran.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../data/requetes.dart';
import '../photo/section_photos.dart';
import '../photo/service_photo.dart';
import '../services.dart';
import '../ui/etablissements.dart' show formaterDateFr;
import '../vaccination/editeur_vaccination.dart';
import '../vaccination/service_vaccination.dart';
import 'depot_visite.dart';
import 'table_oms.dart';

class EcranVisite extends ConsumerStatefulWidget {
  final String eleveId;
  final String? visiteId;

  /// Type d'une nouvelle visite (une visite existante garde le sien).
  final TypeVisite type;
  const EcranVisite({super.key, required this.eleveId, this.visiteId, this.type = TypeVisite.systematique});

  @override
  ConsumerState<EcranVisite> createState() => _EcranVisiteState();
}

class _EcranVisiteState extends ConsumerState<EcranVisite> with WidgetsBindingObserver, TickerProviderStateMixin {
  TabController? _onglets;
  late final DepotVisite _depotVisite;
  late final ServicePhoto _photos;
  DossierVisite? _dossier;
  LigneEleve? _eleve;
  List<Pathologie> _pathologies = const [];
  TableImcOms? _tableOms;

  /// Enfant du préscolaire : vaccins de la liste et suivi vaccinal.
  List<Vaccin> _vaccins = const [];
  SuiviVaccinal? _suivi;
  bool _suiviModifie = false;

  /// Vaccin HPV déjà noté (autre visite, suivi vaccinal).
  HpvAnterieur? _hpvAnterieur;
  Timer? _minuterie;
  bool _modifie = false;
  bool _enregistrement = false;
  String? _derniereSauvegarde;

  Session get _session => ref.read(sessionProvider)!;
  FormulaireVisite get _f => _dossier!.formulaire;

  @override
  void initState() {
    super.initState();
    final s = ref.read(servicesProvider);
    _depotVisite = DepotVisite(s.base, s.depot);
    _photos = ServicePhoto(s.depot, s.fichiers);
    WidgetsBinding.instance.addObserver(this);
    _minuterie = Timer.periodic(const Duration(seconds: 30), (_) => _sauver(silencieux: true));
    _charger();
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _onglets?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) _sauver(silencieux: true);
  }

  Future<void> _charger() async {
    final s = ref.read(servicesProvider);
    final annee = await s.requetes.anneeCourante();
    final eleve = annee == null ? null : await s.requetes.eleve(widget.eleveId, annee);
    final pathologies = await s.requetes.pathologies();
    final table = await chargerTableOms();
    final dossier = widget.visiteId != null
        ? await _depotVisite.charger(widget.visiteId!)
        : await _depotVisite.nouvelle(
            eleveId: widget.eleveId,
            inscriptionId: eleve?.inscriptionId,
            etablissementId: eleve?.etablissementId,
            agent: _session.utilisateur,
            date: DateTime.now().toUtc(),
            type: widget.type,
          );
    final prescolaire = eleve?.prescolaire ?? false;
    final vaccins = prescolaire ? vaccinsPrescolaire(await s.requetes.vaccins()) : const <Vaccin>[];
    final suivi = !prescolaire
        ? null
        : await s.requetes.suiviVaccinal(widget.eleveId) ??
            SuiviVaccinal(eleveId: widget.eleveId, parentTelephone: eleve?.eleve.telephoneContact ?? '');
    final hpvAnterieur = await s.requetes.hpvAnterieur(widget.eleveId, saufVisite: widget.visiteId);
    if (!mounted) return;
    setState(() {
      _eleve = eleve;
      _pathologies = pathologies;
      _tableOms = table;
      _dossier = dossier;
      _vaccins = vaccins;
      _suivi = suivi;
      _hpvAnterieur = hpvAnterieur;
      // Vaccin HPV déjà noté : repris dans une nouvelle visite.
      if (_hpvVisible && hpvAnterieur != null && dossier.formulaire.hpv == null && dossier.formulaire.modifiable) {
        dossier.formulaire.hpv = StatutHpv.dejaFait;
        _modifie = true;
      }
      _construireOnglets();
    });
  }

  /// Visite systématique d'une fille de 9 à 14 ans : onglet du vaccin HPV.
  bool get _hpvVisible {
    final e = _eleve?.eleve;
    return e != null &&
        _dossier != null &&
        hpvConcerne(sexe: e.sexe, dateNaissance: e.dateNaissance, dateVisite: _f.dateVisite, type: _f.type);
  }

  /// Enfant du préscolaire : onglet de vaccination (PEV et hors PEV).
  bool get _vaccinationVisible => _suivi != null && _f.type == TypeVisite.systematique;

  List<(String, Widget Function())> get _rubriques => [
        ('A. Identité', _identification),
        ('B. Antécédents', _antecedents),
        ('C. Clinique', _examenClinique),
        ('D. Appareils', _examenPhysique),
        ('E. Dépistage', _depistage),
        if (_vaccinationVisible) ('Vaccination', _vaccination),
        if (_hpvVisible)
          (
            switch (_f.hpv) {
              StatutHpv.dejaFait => 'Vaccin HPV : fait',
              null => 'Vaccin HPV',
              _ => 'Proposer le vaccin HPV',
            },
            _vaccinHpv
          ),
        (_f.type == TypeVisite.aptitude ? 'F. Aptitude et conclusion' : 'F. Conclusion', _conclusion),
        ('Photos', _rubriquePhotos),
      ];

  /// (Re)crée les onglets quand leur nombre change (date de visite modifiée…).
  void _construireOnglets() {
    final n = _rubriques.length;
    final ancien = _onglets;
    if (ancien != null && ancien.length == n) return;
    final c = TabController(length: n, vsync: this, initialIndex: ancien == null ? 0 : (ancien.index < n ? ancien.index : n - 1));
    c.addListener(() {
      if (!c.indexIsChanging) _sauver(silencieux: true);
    });
    _onglets = c;
    if (ancien != null) WidgetsBinding.instance.addPostFrameCallback((_) => ancien.dispose());
  }

  /// La visite peut-elle être modifiée par l'utilisateur connecté ?
  bool get _modifiable {
    final d = _dossier;
    if (d == null) return false;
    final droits = _session.droits;
    if (d.formulaire.id == null) return droits.peut(Permission.visiteSaisir);
    return droits.peutModifierVisite(agentId: d.formulaire.agentId, validee: d.formulaire.statut == StatutVisite.valide);
  }

  InterpretationImc? get _interpretation => _eleve == null
      ? null
      : _f.interpretationImc(sexe: _eleve!.eleve.sexe, dateNaissance: _eleve!.eleve.dateNaissance, table: _tableOms);

  void _changer(VoidCallback modification) {
    setState(modification);
    _modifie = true;
  }

  Future<void> _sauver({bool silencieux = false, bool forcer = false}) async {
    if (_dossier == null || !_modifiable || _enregistrement) return;
    if (!_modifie && !forcer) return;
    _enregistrement = true;
    try {
      await _depotVisite.enregistrer(_dossier!, utilisateurId: _session.utilisateur.id, interpretation: _interpretation);
      await _sauverSuivi();
      _modifie = false;
      final h = DateTime.now();
      _derniereSauvegarde = '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';
      if (mounted) setState(() {});
    } catch (e) {
      if (!silencieux && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : $e')));
      }
    } finally {
      _enregistrement = false;
    }
  }

  /// Suivi vaccinal de l'enfant du préscolaire, s'il a changé.
  Future<void> _sauverSuivi() async {
    final s = _suivi;
    if (s == null || !_suiviModifie) return;
    s.dateVerification = _f.dateVisite;
    await ServiceVaccination(ref.read(servicesProvider).depot)
        .enregistrer(s, utilisateurId: _session.utilisateur.id, etablissementId: _eleve?.etablissementId);
    _suiviModifie = false;
  }

  void _message(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _enregistrerSous(StatutVisite statut) async {
    _f.statut = statut;
    await _sauver(forcer: true);
    if (mounted) _message(statut == StatutVisite.ebauche ? 'Ébauche enregistrée.' : 'Visite enregistrée sur le téléphone.');
  }

  Set<String> get _pathologiesAPreciser => {for (final p in _pathologies) if (p.precisionRequise) p.id};

  Future<void> _validerEtSynchroniser() async {
    final c = controlerVisite(_f, pathologiesAPreciser: _pathologiesAPreciser, hpv: _hpvVisible);
    if (!c.transmissible) {
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('À compléter avant validation'),
          content: Text(c.erreurs.map((e) => '• $e').join('\n')),
          actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Compléter'))],
        ),
      );
      return;
    }
    if (c.avertissements.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Points à vérifier'),
          content: SingleChildScrollView(child: Text(c.avertissements.map((e) => '• $e').join('\n'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Corriger')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Valider quand même')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _depotVisite.transmettre(_dossier!, utilisateurId: _session.utilisateur.id, interpretation: _interpretation);
    await _sauverSuivi();
    _modifie = false;
    if (!mounted) return;
    setState(() {});
    try {
      final r = await ref.read(servicesProvider).synchroniser();
      _message(r.sansIncident ? 'Visite validée et synchronisée.' : 'Visite validée. Synchronisation : $r');
    } catch (_) {
      _message('Visite validée. Elle sera transmise à la prochaine synchronisation.');
    }
    final maj = await _depotVisite.charger(_f.id!);
    if (mounted) setState(() => _dossier = maj);
  }

  Future<void> _validerMedicalement() async {
    await _depotVisite.valider(_dossier!, medecinId: _session.utilisateur.id, interpretation: _interpretation);
    _modifie = false;
    if (mounted) {
      setState(() {});
      _message('Visite validée médicalement. Elle sera transmise à la prochaine synchronisation.');
    }
  }

  Future<void> _supprimerEbauche() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Supprimer cette ébauche ?'),
        content: const Text('Toutes les informations saisies et les photos de cette visite seront effacées.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await _depotVisite.supprimerEbauche(_dossier!,
        utilisateurId: _session.utilisateur.id, supprimerFichier: ref.read(servicesProvider).fichiers.supprimer);
    _modifie = false;
    if (mounted) Navigator.pop(context);
  }

  // ----------------------------------------------------------------- champs

  Widget _texte(String libelle, String valeur, void Function(String) maj, {int lignes = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          initialValue: valeur,
          enabled: _modifiable,
          maxLines: lignes,
          decoration: InputDecoration(labelText: libelle),
          onChanged: (v) => _changer(() => maj(v)),
        ),
      );

  Widget _nombre(String libelle, num? valeur, String unite, void Function(String) maj) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          initialValue: valeur == null ? '' : '$valeur',
          enabled: _modifiable,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: libelle, suffixText: unite),
          onChanged: (v) => _changer(() => maj(v.replaceAll(',', '.').trim())),
        ),
      );

  Future<DateTime?> _choisirDate(DateTime? initiale, {DateTime? min, DateTime? max}) => showDatePicker(
        context: context,
        initialDate: initiale ?? DateTime.now(),
        firstDate: min ?? DateTime(2000),
        lastDate: max ?? DateTime(2100),
        locale: const Locale('fr'),
      );

  // --------------------------------------------------------------- rubriques

  Widget _identification() {
    final e = _eleve;
    final s = _session.utilisateur;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (e == null)
        const Text('Élève introuvable sur ce téléphone.')
      else ...[
        Text(e.eleve.nomComplet, style: Theme.of(context).textTheme.titleLarge),
        Text('Matricule : ${e.eleve.matricule ?? 'non renseigné'}'),
        Text('Sexe : ${e.eleve.sexe.libelle}'),
        if (e.eleve.dateNaissance != null)
          Text('Né(e) le ${formaterDateFr(e.eleve.dateNaissance!)} · ${calculerAge(e.eleve.dateNaissance!, _f.dateVisite)}'),
        if (e.eleve.telephoneContact != null) Text('Téléphone : ${e.eleve.telephoneContact}'),
        Text('${e.etablissementNom ?? ''} · ${e.classeLibelle ?? 'non inscrit cette année'}'),
      ],
      const Divider(height: 32),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.event),
        title: Text('Date de la visite : ${formaterDateFr(_f.dateVisite)}'),
        trailing: _modifiable ? const Icon(Icons.edit) : null,
        onTap: !_modifiable
            ? null
            : () async {
                final d = await _choisirDate(_f.dateVisite, max: DateTime.now());
                if (d != null) {
                  _changer(() {
                    _f.dateVisite = DateTime.utc(d.year, d.month, d.day);
                    _construireOnglets();
                  });
                }
              },
      ),
      Text('Agent de santé : ${s.nomAffiche}${s.fonction == null ? '' : ' (${s.fonction})'}'),
      const SizedBox(height: 12),
      _texte('Structure sanitaire d\'origine', _f.structureOrigine ?? '', (v) => _f.structureOrigine = v),
    ]);
  }

  Widget _antecedents() {
    final e = _eleve?.eleve;
    final gyneco = e == null || rubriqueGynecologiqueVisible(e.sexe, e.dateNaissance, _f.dateVisite);
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Repris de la visite précédente le cas échéant : vérifier et compléter.'),
      for (final t in TypeAntecedent.values)
        if (t != TypeAntecedent.gynecologique || gyneco) ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.libelle),
            value: _f.antecedents[t]!.coche,
            onChanged: _modifiable ? (v) => _changer(() => _f.antecedents[t]!.coche = v ?? false) : null,
          ),
          _texte('Précisions', _f.antecedents[t]!.commentaire, (v) => _f.antecedents[t]!.commentaire = v, lignes: 2),
        ],
    ]);
  }

  Widget _examenClinique() {
    final imc = _f.imc;
    final interp = _interpretation;
    final alertes = verifierConstantes(
        poidsKg: _f.poidsKg,
        tailleCm: _f.tailleCm,
        taSys: _f.taSys,
        taDia: _f.taDia,
        temperatureC: _f.temperatureC,
        fc: _f.fc,
        fr: _f.fr);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: _nombre('Poids', _f.poidsKg, 'kg', (v) => _f.poidsKg = double.tryParse(v))),
        const SizedBox(width: 12),
        Expanded(child: _nombre('Taille', _f.tailleCm, 'cm', (v) => _f.tailleCm = double.tryParse(v))),
      ]),
      Card(
        child: ListTile(
          leading: const Icon(Icons.monitor_weight),
          title: Text(imc == null ? 'IMC : saisir le poids et la taille' : 'IMC : $imc kg/m²'),
          subtitle: interp == null
              ? null
              : Text('${interp.categorie.libelle}'
                  '${interp.scoreZ == null ? '' : ' (score z ${interp.scoreZ})'}'
                  '${interp.message == null ? '' : '\n${interp.message}'}'),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _nombre('TA systolique', _f.taSys, 'mmHg', (v) => _f.taSys = int.tryParse(v))),
        const SizedBox(width: 12),
        Expanded(child: _nombre('TA diastolique', _f.taDia, 'mmHg', (v) => _f.taDia = int.tryParse(v))),
      ]),
      _nombre('Température', _f.temperatureC, '°C', (v) => _f.temperatureC = double.tryParse(v)),
      Row(children: [
        Expanded(child: _nombre('Fréquence cardiaque', _f.fc, 'bat/min', (v) => _f.fc = int.tryParse(v))),
        const SizedBox(width: 12),
        Expanded(child: _nombre('Fréquence respiratoire', _f.fr, 'cycles/min', (v) => _f.fr = int.tryParse(v))),
      ]),
      for (final a in alertes)
        ListTile(
          dense: true,
          leading: const Icon(Icons.warning_amber, color: Colors.orange),
          title: Text(a.message),
        ),
    ]);
  }

  Widget _examenPhysique() => ListView(padding: const EdgeInsets.all(16), children: [
        for (final a in AppareilExamen.values) ...[
          Text(a.libelle, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SegmentedButton<ResultatExamen>(
            segments: [for (final r in ResultatExamen.values) ButtonSegment(value: r, label: Text(r.libelle))],
            selected: {_f.examens[a]!.resultat},
            onSelectionChanged: _modifiable ? (s) => _changer(() => _f.examens[a]!.resultat = s.first) : null,
          ),
          const SizedBox(height: 8),
          _texte('Observations', _f.examens[a]!.observation, (v) => _f.examens[a]!.observation = v),
          const SizedBox(height: 8),
        ],
      ]);

  Widget _depistage() => ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Pathologies dépistées (plusieurs choix possibles)'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final p in _pathologies)
            FilterChip(
              label: Text(p.libelle),
              selected: _f.pathologies.containsKey(p.id),
              onSelected: !_modifiable
                  ? null
                  : (v) => _changer(() {
                        if (v) {
                          _f.pathologies.putIfAbsent(p.id, () => '');
                        } else {
                          _f.pathologies.remove(p.id);
                        }
                      }),
            ),
        ]),
        const SizedBox(height: 16),
        for (final p in _pathologies.where((p) => _f.pathologies.containsKey(p.id)))
          _texte(p.precisionRequise ? 'Préciser : ${p.libelle} (obligatoire)' : 'Précision : ${p.libelle}',
              _f.pathologies[p.id]!, (v) => _f.pathologies[p.id] = v),
      ]);

  Widget _vaccination() => EditeurVaccination(
        key: ValueKey('vaccination-${_f.id}'),
        suivi: _suivi!,
        vaccins: _vaccins,
        modifiable: _modifiable,
        onChange: () => setState(() {
          _suiviModifie = true;
          _modifie = true;
        }),
      );

  Widget _vaccinHpv() {
    final a = _hpvAnterieur;
    final titre = Theme.of(context).textTheme.titleMedium;
    final propose = _f.hpv == StatutHpv.aProposer || _f.hpv == StatutHpv.fait || _f.hpv == StatutHpv.nonFait;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Fille de 9 à 14 ans : vérifier si elle a reçu le vaccin contre le papillomavirus (HPV), qui prévient '
          'le cancer du col de l\'utérus, et le lui proposer sinon.'),
      if (a != null)
        Card(
          child: ListTile(
            leading: Icon(Icons.verified, color: Colors.green.shade700),
            title: const Text('Vaccin HPV déjà noté comme fait'),
            subtitle: Text(a.source == 'visite'
                ? 'Lors de la visite du ${formaterDateFr(a.date!)}'
                : 'Dans le suivi vaccinal${a.date == null ? '' : ' (vérifié le ${formaterDateFr(a.date!)})'}'),
          ),
        ),
      const SizedBox(height: 12),
      Text('1. Vérification', style: titre),
      const Text('La fille a-t-elle déjà reçu le vaccin HPV (carnet de vaccination, déclaration) ?'),
      RadioListTile<bool>(
        contentPadding: EdgeInsets.zero,
        title: const Text('Oui, déjà vaccinée'),
        value: true,
        groupValue: _f.hpv == null ? null : _f.hpv == StatutHpv.dejaFait,
        onChanged: _modifiable
            ? (_) => _changer(() {
                  _f.hpv = StatutHpv.dejaFait;
                  _f.hpvMotif = null;
                })
            : null,
      ),
      RadioListTile<bool>(
        contentPadding: EdgeInsets.zero,
        title: const Text('Non, pas encore vaccinée'),
        value: false,
        groupValue: _f.hpv == null ? null : _f.hpv == StatutHpv.dejaFait,
        onChanged: _modifiable
            ? (_) => _changer(() {
                  if (!propose) _f.hpv = StatutHpv.aProposer;
                })
            : null,
      ),
      if (propose) ...[
        const Divider(height: 28),
        Text('2. Proposer le vaccin HPV', style: titre),
        const Text('Expliquer le vaccin à la fille (et à ses parents), puis cocher :'),
        RadioListTile<StatutHpv>(
          contentPadding: EdgeInsets.zero,
          title: const Text('Fait : vaccin HPV administré'),
          value: StatutHpv.fait,
          groupValue: _f.hpv == StatutHpv.aProposer ? null : _f.hpv,
          onChanged: _modifiable
              ? (_) => _changer(() {
                    _f.hpv = StatutHpv.fait;
                    _f.hpvMotif = null;
                  })
              : null,
        ),
        RadioListTile<StatutHpv>(
          contentPadding: EdgeInsets.zero,
          title: const Text('Pas fait'),
          value: StatutHpv.nonFait,
          groupValue: _f.hpv == StatutHpv.aProposer ? null : _f.hpv,
          onChanged: _modifiable ? (_) => _changer(() => _f.hpv = StatutHpv.nonFait) : null,
        ),
        if (_f.hpv == StatutHpv.nonFait) ...[
          const SizedBox(height: 8),
          const Text('Motif (obligatoire) :'),
          for (final m in MotifHpv.values)
            RadioListTile<MotifHpv>(
              contentPadding: const EdgeInsets.only(left: 16),
              dense: true,
              title: Text(m.libelle),
              value: m,
              groupValue: _f.hpvMotif,
              onChanged: _modifiable ? (v) => _changer(() => _f.hpvMotif = v) : null,
            ),
          const Text('Précisions éventuelles : rubrique F, « Observations complémentaires ».',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ],
    ]);
  }

  Widget _conclusion() => ListView(padding: const EdgeInsets.all(16), children: [
        if (_f.type == TypeVisite.aptitude) ...[
          Text('Décision d\'aptitude', style: Theme.of(context).textTheme.titleMedium),
          for (final d in DecisionAptitude.values)
            RadioListTile<DecisionAptitude>(
              contentPadding: EdgeInsets.zero,
              title: Text(d.libelle),
              value: d,
              groupValue: _f.aptitude,
              onChanged: _modifiable ? (v) => _changer(() => _f.aptitude = v) : null,
            ),
          if (_f.aptitude?.aPreciser ?? false)
            _texte(
                _f.aptitude == DecisionAptitude.aptePartiel
                    ? 'Restrictions (activités à éviter ou à adapter) — obligatoire'
                    : 'Motif et durée de l\'inaptitude — obligatoire',
                _f.aptitudeRestrictions,
                (v) => _f.aptitudeRestrictions = v,
                lignes: 2),
          const Divider(height: 24),
          Text('Conclusion médicale', style: Theme.of(context).textTheme.titleMedium),
        ],
        for (final c in ConclusionVisite.values)
          RadioListTile<ConclusionVisite>(
            contentPadding: EdgeInsets.zero,
            title: Text(c.libelle),
            value: c,
            groupValue: _f.conclusion,
            onChanged: _modifiable ? (v) => _changer(() => _f.conclusion = v) : null,
          ),
        const SizedBox(height: 8),
        _texte('Diagnostic ou problème identifié', _f.diagnostic, (v) => _f.diagnostic = v, lignes: 2),
        _texte('Conduite à tenir', _f.conduiteATenir, (v) => _f.conduiteATenir = v, lignes: 2),
        _texte('Traitement ou conseils', _f.traitementConseils, (v) => _f.traitementConseils = v, lignes: 2),
        _texte('Structure de référence', _f.structureReference, (v) => _f.structureReference = v),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_repeat),
          title: Text(_f.dateControle == null
              ? 'Date du rendez-vous de contrôle : aucune'
              : 'Rendez-vous de contrôle : ${formaterDateFr(_f.dateControle!)}'),
          trailing: _f.dateControle != null && _modifiable
              ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _changer(() => _f.dateControle = null))
              : null,
          onTap: !_modifiable
              ? null
              : () async {
                  final d = await _choisirDate(_f.dateControle, min: DateTime.now());
                  if (d != null) _changer(() => _f.dateControle = DateTime.utc(d.year, d.month, d.day));
                },
        ),
        _texte('Observations complémentaires', _f.observations, (v) => _f.observations = v, lignes: 3),
      ]);

  Widget _rubriquePhotos() {
    if (_f.id == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FilledButton(
            onPressed: _modifiable
                ? () async {
                    await _sauver(forcer: true);
                    if (mounted) setState(() {});
                  }
                : null,
            child: const Text('Enregistrer la visite pour joindre des photos'),
          ),
        ),
      );
    }
    final libelles = {for (final p in _pathologies) p.id: p.libelle};
    return SectionPhotos(
      key: ValueKey('photos-${_f.id}-${_dossier!.idsPathologies.length}'),
      service: _photos,
      visiteId: _f.id!,
      eleveId: _f.eleveId,
      etablissementId: _dossier!.etablissementId,
      session: _session,
      lectureSeule: !_modifiable,
      aTransmettre: !_f.modifiable,
      pathologies: [
        for (final e in _dossier!.idsPathologies.entries) PathologieLiable(e.value, libelles[e.key] ?? 'Pathologie'),
      ],
    );
  }

  // ------------------------------------------------------------------- écran

  @override
  Widget build(BuildContext context) {
    final onglets = _onglets;
    if (_dossier == null || onglets == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final rubriques = _rubriques;
    final droits = _session.droits;
    final statut = statutAffiche(_f.statut, _dossier!.etat);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (aQuitte, _) async {
        if (aQuitte) return;
        await _sauver(silencieux: true);
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_eleve?.eleve.nomComplet ?? 'Visite médicale'),
          bottom: TabBar(
            controller: onglets,
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [for (final r in rubriques) Tab(text: r.$1)],
          ),
          actions: [
            if (_f.modifiable && _f.id != null && _modifiable)
              IconButton(tooltip: 'Supprimer l\'ébauche', icon: const Icon(Icons.delete_outline), onPressed: _supprimerEbauche),
          ],
        ),
        body: Column(children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text('${_f.type.libelle} · statut : $statut'
                '${_derniereSauvegarde == null ? '' : ' · enregistré à $_derniereSauvegarde'}'
                '${_modifiable ? '' : ' · lecture seule'}'),
          ),
          Expanded(
            child: TabBarView(controller: onglets, children: [for (final r in rubriques) r.$2()]),
          ),
        ]),
        bottomNavigationBar: !_modifiable
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _f.modifiable
                      ? Row(children: [
                          Expanded(
                            child: OutlinedButton(
                                onPressed: () => _enregistrerSous(StatutVisite.ebauche), child: const Text('Ébauche')),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: OutlinedButton(
                                onPressed: () => _enregistrerSous(StatutVisite.enregistre), child: const Text('Enregistrer')),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 2,
                            child: FilledButton(onPressed: _validerEtSynchroniser, child: const Text('Valider et synchroniser')),
                          ),
                        ])
                      : Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                await _sauver(forcer: true);
                                if (mounted) _message('Modifications enregistrées, en attente de synchronisation.');
                              },
                              child: const Text('Enregistrer les modifications'),
                            ),
                          ),
                          if (droits.peut(Permission.visiteValider) && _f.statut != StatutVisite.valide) ...[
                            const SizedBox(width: 6),
                            Expanded(
                                child: FilledButton(onPressed: _validerMedicalement, child: const Text('Validation médicale'))),
                          ],
                        ]),
                ),
              ),
      ),
    );
  }
}
