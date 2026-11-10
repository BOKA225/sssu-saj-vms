/// Zone de signature tracée au doigt, exportée en image PNG.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class ControleurSignature extends ChangeNotifier {
  final List<List<Offset>> _traits = [];
  Size _taille = Size.zero;

  List<List<Offset>> get traits => _traits;
  bool get vide => _traits.every((t) => t.isEmpty);

  void _commencer(Offset p) {
    _traits.add([p]);
    notifyListeners();
  }

  void _prolonger(Offset p) {
    if (_traits.isEmpty) return;
    _traits.last.add(p);
    notifyListeners();
  }

  void effacer() {
    _traits.clear();
    notifyListeners();
  }

  /// Image PNG de la signature (trait noir sur fond blanc), ou `null` si vide.
  Future<Uint8List?> versPng({double ratio = 2}) async {
    if (vide || _taille.isEmpty) return null;
    final enregistreur = ui.PictureRecorder();
    final canevas = Canvas(enregistreur);
    canevas.scale(ratio);
    canevas.drawRect(Offset.zero & _taille, Paint()..color = Colors.white);
    _PeintreSignature._dessiner(canevas, _traits);
    final image = await enregistreur
        .endRecording()
        .toImage((_taille.width * ratio).round(), (_taille.height * ratio).round());
    final octets = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return octets?.buffer.asUint8List();
  }
}

class ZoneSignature extends StatelessWidget {
  final ControleurSignature controleur;

  /// Signature déjà enregistrée, affichée tant que rien n'est retracé.
  final Uint8List? existante;
  final bool modifiable;
  const ZoneSignature({super.key, required this.controleur, this.existante, this.modifiable = true});

  @override
  Widget build(BuildContext context) => Container(
        height: 160,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26)),
        child: LayoutBuilder(builder: (context, c) {
          controleur._taille = Size(c.maxWidth, c.maxHeight);
          return ListenableBuilder(
            listenable: controleur,
            builder: (context, _) {
              if (controleur.vide && existante != null) {
                return Image.memory(existante!, fit: BoxFit.contain, width: c.maxWidth, height: c.maxHeight);
              }
              final dessin = CustomPaint(painter: _PeintreSignature(controleur.traits), size: Size.infinite);
              if (!modifiable) return dessin;
              return GestureDetector(
                onPanStart: (d) => controleur._commencer(d.localPosition),
                onPanUpdate: (d) => controleur._prolonger(d.localPosition),
                child: Stack(children: [
                  dessin,
                  if (controleur.vide)
                    const Center(child: Text('Signez ici avec le doigt', style: TextStyle(color: Colors.black38))),
                ]),
              );
            },
          );
        }),
      );
}

class _PeintreSignature extends CustomPainter {
  final List<List<Offset>> traits;
  _PeintreSignature(this.traits);

  static void _dessiner(Canvas canevas, List<List<Offset>> traits) {
    final p = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final t in traits) {
      if (t.length == 1) {
        canevas.drawCircle(t.first, 1.2, p..style = PaintingStyle.fill);
        p.style = PaintingStyle.stroke;
        continue;
      }
      final chemin = Path()..moveTo(t.first.dx, t.first.dy);
      for (final o in t.skip(1)) {
        chemin.lineTo(o.dx, o.dy);
      }
      canevas.drawPath(chemin, p);
    }
  }

  @override
  void paint(Canvas canvas, Size size) => _dessiner(canvas, traits);

  @override
  bool shouldRepaint(covariant _PeintreSignature old) => true;
}
