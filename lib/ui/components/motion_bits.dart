import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Cambia de un contenido a otro con un fundido corto, sin moverlo. Para
/// textos o marcas que cambian de estado (un mes que pasa a «Cobrado», un
/// importe con pronto pago). Con las animaciones reducidas cambia sin más.
class FadeSwap extends StatelessWidget {
  const FadeSwap({
    super.key,
    required this.value,
    required this.child,
    this.alignment = Alignment.centerLeft,
  });

  /// Identifica el contenido: al cambiar, se funde.
  final Object value;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: context.motion(Motion.fast),
    switchInCurve: Motion.easeOut,
    switchOutCurve: Motion.easeOut,
    layoutBuilder: (current, previous) =>
        Stack(alignment: alignment, children: [...previous, ?current]),
    child: KeyedSubtree(key: ValueKey(value), child: child),
  );
}

/// Hace aparecer a [child] una sola vez, al construirse: fundido y un ligero
/// crecimiento desde 0,9 (nunca desde cero), tras [delay]. Para momentos poco
/// frecuentes, como los trofeos. Con las animaciones reducidas, solo el
/// fundido y sin espera.
class AppearOnce extends StatefulWidget {
  const AppearOnce({
    super.key,
    this.delay = Duration.zero,
    required this.child,
  });

  final Duration delay;
  final Widget child;

  @override
  State<AppearOnce> createState() => _AppearOnceState();
}

class _AppearOnceState extends State<AppearOnce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late Animation<double> _t;
  var _reduced = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this);
    _t = CurvedAnimation(parent: _c, curve: Motion.easeOut);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.value > 0) return;
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final total = widget.delay + Motion.appear;
    _c.duration = _reduced ? Motion.fast : total;
    // La espera va dentro de la misma animación: así no hay temporizadores
    // sueltos y se puede cortar en cualquier momento.
    if (!_reduced && widget.delay > Duration.zero) {
      _t = CurvedAnimation(
        parent: _c,
        curve: Interval(
          widget.delay.inMicroseconds / total.inMicroseconds,
          1,
          curve: Motion.easeOut,
        ),
      );
    }
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (context, child) => Opacity(
      opacity: _t.value,
      child: Transform.scale(
        scale: _reduced ? 1 : 0.9 + 0.1 * _t.value,
        child: child,
      ),
    ),
    child: widget.child,
  );
}
