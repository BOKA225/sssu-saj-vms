import 'dart:async';

import 'package:flutter/material.dart';

/// Verrouille la session après une période sans interaction
/// (5 minutes sur le téléphone, réglable dans les paramètres).
class VerrouInactivite extends StatefulWidget {
  final Duration duree;
  final VoidCallback onVerrouillage;
  final Widget child;

  const VerrouInactivite({super.key, required this.duree, required this.onVerrouillage, required this.child});

  @override
  State<VerrouInactivite> createState() => _VerrouInactiviteState();
}

class _VerrouInactiviteState extends State<VerrouInactivite> with WidgetsBindingObserver {
  Timer? _minuterie;
  DateTime _derniereActivite = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _relancer();
  }

  void _relancer() {
    _derniereActivite = DateTime.now();
    _minuterie?.cancel();
    _minuterie = Timer(widget.duree, widget.onVerrouillage);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour au premier plan après une longue absence : verrouillage immédiat.
    if (state == AppLifecycleState.resumed && DateTime.now().difference(_derniereActivite) >= widget.duree) {
      widget.onVerrouillage();
    }
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _relancer(),
        child: widget.child,
      );
}
