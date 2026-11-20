import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'roll_switcher.dart';

/// Fecha del día elegido. Al cambiar, la nueva entra deslizándose en la
/// dirección del cambio (RF-31): como al deslizar el dedo hacia la izquierda
/// se va al pasado, un día anterior entra por la derecha.
class DayHeading extends StatelessWidget {
  const DayHeading({super.key, required this.text, this.towardsPast = true});

  final String text;

  /// Si el nuevo día es anterior (Hoy → Ayer), entra desde la derecha.
  final bool towardsPast;

  @override
  Widget build(BuildContext context) {
    return RollSwitcher(
      value: text,
      forward: !towardsPast,
      vertical: false,
      duration: Motion.slide,
      child: Text(
        text,
        style: AppText.bodyStrong,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
