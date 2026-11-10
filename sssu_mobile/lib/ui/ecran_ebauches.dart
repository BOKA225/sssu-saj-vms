import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sssu_core/sssu_core.dart';

import '../data/requetes.dart';
import '../services.dart';
import '../visite/ecran_visite.dart';
import 'etablissements.dart' show formaterDateFr;

/// Visites non transmises de l'agent : ébauches et visites enregistrées
/// localement, à reprendre ou à valider.
class EcranEbauches extends ConsumerStatefulWidget {
  const EcranEbauches({super.key});
  @override
  ConsumerState<EcranEbauches> createState() => _EcranEbauchesState();
}

class _EcranEbauchesState extends ConsumerState<EcranEbauches> {
  List<EbaucheVisite>? _liste;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final session = ref.read(sessionProvider)!;
    // Le Médecin-Chef voit les ébauches de tous les agents du téléphone.
    final tous = session.droits.peut(Permission.visiteModifierToutes);
    final l = await ref.read(servicesProvider).requetes.ebauches(agentId: tous ? null : session.utilisateur.id);
    if (mounted) setState(() => _liste = l);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ébauches et visites non transmises')),
        body: _liste == null
            ? const Center(child: CircularProgressIndicator())
            : _liste!.isEmpty
                ? const Padding(padding: EdgeInsets.all(24), child: Text('Aucune visite en cours.'))
                : ListView.separated(
                    itemCount: _liste!.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, i) {
                      final e = _liste![i];
                      return ListTile(
                        leading: Icon(e.statut == StatutVisite.ebauche ? Icons.edit_note : Icons.save),
                        title: Text(e.eleveNom),
                        subtitle: Text('${formaterDateFr(lireDate(e.date))} · ${e.classeLibelle ?? ''} · '
                            '${e.statut.libelle}'),
                        onTap: () async {
                          await Navigator.push(
                              c, MaterialPageRoute(builder: (_) => EcranVisite(eleveId: e.eleveId, visiteId: e.visiteId)));
                          _charger();
                        },
                      );
                    },
                  ),
      );
}
