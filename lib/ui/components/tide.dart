import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Marea: un fondo de agua que sube con el valor (RF-11).
///
/// El agua ocupa la parte de abajo de la pieza; [child] se dibuja encima.
/// Si no se indica [height], la pieza mide lo que mida [child].
/// La ola se mece despacio (RF-26) y, al subir el valor, suben burbujas
/// (RF-27). Nada de eso ocurre con las animaciones reducidas (RF-10).
class Tide extends StatefulWidget {
  const Tide({
    super.key,
    required this.value,
    required this.max,
    required this.kind,
    this.height,
    this.minLevel = 36,
    this.ambient = true,
    this.child,
  });

  final double value;
  final double max;
  final DataKind kind;

  /// Alto total de la pieza; si es nulo, lo marca [child].
  final double? height;

  /// Nivel del agua con valor 0, para que siempre se vea algo de agua.
  final double minLevel;

  /// Si la ola se mece sola.
  final bool ambient;
  final Widget? child;

  /// Alto de la ola dibujada encima del agua.
  static const waveHeight = 22.0;

  /// Un vaivén completo de la ola.
  static const swayPeriod = Motion.sway;

  /// Lo que tardan en subir las burbujas.
  static const bubblesDuration = Motion.bubbles;

  /// Nivel del agua para [value]. Nunca baja de [minLevel] ni pasa del
  /// máximo, que deja sitio a la ola dentro de [height].
  static double levelFor({
    required double value,
    required double max,
    required double height,
    required double minLevel,
  }) {
    final top = height - waveHeight;
    final fraction = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return minLevel + fraction * (top - minLevel);
  }

  @override
  State<Tide> createState() => _TideState();
}

class _TideState extends State<Tide> with TickerProviderStateMixin {
  late final _sway = AnimationController(
    vsync: this,
    duration: Tide.swayPeriod,
  );
  late final _bubbles = AnimationController(
    vsync: this,
    duration: Tide.bubblesDuration,
  );

  bool get _motionOn => context.motion(Motion.tide) > Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateSway();
  }

  void _updateSway() {
    if (widget.ambient && _motionOn) {
      if (!_sway.isAnimating) _sway.repeat();
    } else {
      _sway.stop();
      _bubbles.stop();
      _bubbles.value = 0;
    }
  }

  @override
  void didUpdateWidget(Tide old) {
    super.didUpdateWidget(old);
    _updateSway();
    if (widget.value > old.value && _motionOn) {
      _bubbles.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _sway.dispose();
    _bubbles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final water = c.of(widget.kind).soft;
    // Burbujas siempre más claras que el agua, en los dos temas.
    final bubble = Color.lerp(
      water,
      Colors.white,
      0.6,
    )!.withValues(alpha: 0.85);
    // En claro, un contorno fino del color del tipo para que se distingan.
    final bubbleEdge = Theme.of(context).brightness == Brightness.light
        ? c.of(widget.kind).strong.withValues(alpha: 0.45)
        : null;

    final stack = Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // El agua se repinta sola, sin arrastrar al contenido de encima.
        Positioned.fill(
          child: RepaintBoundary(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final h = constraints.maxHeight;
                final level = Tide.levelFor(
                  value: widget.value,
                  max: widget.max,
                  height: h,
                  minLevel: widget.minLevel,
                );
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: TweenAnimationBuilder<double>(
                    key: const ValueKey('tide-water'),
                    tween: Tween(end: level),
                    duration: context.motion(Motion.tide),
                    curve: Curves.easeOutBack,
                    builder: (context, l, _) => TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: water),
                      duration: context.motion(Motion.theme),
                      builder: (context, color, _) => SizedBox(
                        key: const ValueKey('tide-level'),
                        height:
                            l.clamp(0, (h - Tide.waveHeight).clamp(0, h)) +
                            Tide.waveHeight,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: WavePainter(
                            color: color ?? water,
                            bubbleColor: bubble,
                            bubbleEdge: bubbleEdge,
                            sway: _sway,
                            bubbles: _bubbles,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        ?widget.child,
      ],
    );
    return widget.height == null
        ? stack
        : SizedBox(height: widget.height, child: stack);
  }
}

/// Dibuja el agua con su ola y las burbujas.
class WavePainter extends CustomPainter {
  WavePainter({
    required this.color,
    required this.bubbleColor,
    this.bubbleEdge,
    required this.sway,
    required this.bubbles,
  }) : super(repaint: Listenable.merge([sway, bubbles]));

  final Color color;
  final Color bubbleColor;

  /// Contorno de las burbujas; nulo si no lo llevan.
  final Color? bubbleEdge;
  final Animation<double> sway;
  final Animation<double> bubbles;

  /// Posición horizontal, tamaño y retraso de cada burbuja (fijos, para que
  /// el efecto sea siempre igual de discreto).
  static const _bubbleSpecs = [
    (0.12, 5.0, 0.00),
    (0.27, 3.5, 0.15),
    (0.41, 6.0, 0.05),
    (0.58, 4.0, 0.25),
    (0.70, 5.5, 0.10),
    (0.84, 3.5, 0.30),
    (0.93, 4.5, 0.18),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    const crest = Tide.waveHeight;
    final phase = sway.value * 2 * math.pi;

    final path = Path()..moveTo(0, size.height);
    const steps = 32;
    for (var i = 0; i <= steps; i++) {
      final x = w * i / steps;
      final y =
          crest * 0.5 +
          math.sin(2 * math.pi * i / steps * 1.2 + phase) * crest * 0.35 +
          math.sin(2 * math.pi * i / steps * 0.5 - phase) * crest * 0.12;
      path.lineTo(x, y);
    }
    path
      ..lineTo(w, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);

    final t = bubbles.value;
    if (t <= 0 || t >= 1) return;
    final paint = Paint();
    for (final (fx, radius, delay) in _bubbleSpecs) {
      final p = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final y = size.height - p * (size.height - crest);
      final x = w * fx + math.sin(p * math.pi * 3) * 4;
      paint.color = bubbleColor.withValues(alpha: bubbleColor.a * (1 - p));
      canvas.drawCircle(Offset(x, y), radius, paint);
      final edge = bubbleEdge;
      if (edge != null) {
        canvas.drawCircle(
          Offset(x, y),
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = edge.withValues(alpha: edge.a * (1 - p)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(WavePainter old) =>
      old.color != color ||
      old.bubbleColor != bubbleColor ||
      old.bubbleEdge != bubbleEdge;
}
