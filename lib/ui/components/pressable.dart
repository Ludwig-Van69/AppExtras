import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Hunde ligeramente a [child] mientras se pulsa y lo devuelve a su sitio al
/// soltar, rápido y sin rebote: un toque no lanza nada (RF-30). Con las
/// animaciones reducidas no se mueve.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child});

  /// Escala mientras se pulsa.
  static const pressedScale = 0.94;

  final Widget child;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final motionOn = context.motion(Motion.fast) > Duration.zero;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed && motionOn ? Pressable.pressedScale : 1,
        duration: _pressed ? Motion.pressIn : Motion.pressOut,
        curve: Motion.easeOut,
        child: widget.child,
      ),
    );
  }
}
