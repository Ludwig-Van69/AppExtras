import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Cambia de un contenido a otro deslizándolos: el anterior sale y el nuevo
/// entra en la dirección del cambio. Lo usan la cifra grande (RF-28) y la
/// fecha (RF-31).
///
/// Cada contenido guarda su propia dirección al aparecer, y si llegan
/// cambios seguidos solo se ven el último que sale y el que entra: nunca
/// tres a la vez.
class RollSwitcher extends StatefulWidget {
  const RollSwitcher({
    super.key,
    required this.value,
    required this.forward,
    required this.vertical,
    required this.duration,
    required this.child,
    this.alignment = Alignment.centerLeft,
    this.clip = false,
  });

  /// Identifica el contenido: al cambiar, se anima el cambio.
  final Object value;

  /// En vertical: `true` si el valor sube (el nuevo entra por abajo).
  /// En horizontal: `true` si se va hacia atrás (el nuevo entra por la
  /// izquierda).
  final bool forward;
  final bool vertical;
  final Duration duration;
  final Alignment alignment;

  /// Recorta lo que sale de la caja, como en un marcador.
  final bool clip;
  final Widget child;

  @override
  State<RollSwitcher> createState() => _RollSwitcherState();
}

class _RollSwitcherState extends State<RollSwitcher> {
  int _serial = 0;
  final _forwardOf = <int, bool>{0: true};

  @override
  void didUpdateWidget(RollSwitcher old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _serial++;
      _forwardOf[_serial] = widget.forward;
      // Solo hacen falta el actual y el que está saliendo.
      _forwardOf.removeWhere((k, _) => k < _serial - 1);
    }
  }

  Offset _offset(bool forward) {
    const distance = 0.6;
    final sign = forward ? 1.0 : -1.0;
    return widget.vertical
        ? Offset(0, distance * sign)
        : Offset(-0.4 * sign, 0);
  }

  @override
  Widget build(BuildContext context) {
    final switcher = AnimatedSwitcher(
      duration: context.motion(widget.duration),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: widget.alignment,
        children: [if (previous.isNotEmpty) previous.last, ?current],
      ),
      transitionBuilder: (child, animation) {
        final serial = (child.key! as ValueKey<int>).value;
        final incoming = serial == _serial;
        // La dirección del contenido que entra marca hacia dónde sale el
        // que se va; cada uno conserva la suya aunque lleguen más cambios.
        final from = _offset(_forwardOf[serial] ?? widget.forward);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: incoming ? from : -_offset(_forwardOf[_serial] ?? true),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey<int>(_serial), child: widget.child),
    );
    return widget.clip ? ClipRect(child: switcher) : switcher;
  }
}
