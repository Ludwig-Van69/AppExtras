import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'haptics.dart';
import 'pressable.dart';

/// Marca del doble toque (013, RF-1 a RF-3): el botón espera el segundo
/// toque para apuntar o para borrar.
enum PresetArm { none, save, delete }

/// Botón de horas preseleccionadas (RF-15).
class HourPresetButton extends StatelessWidget {
  const HourPresetButton({
    super.key,
    required this.minutes,
    required this.selected,
    required this.kind,
    required this.onPressed,
    this.text,
    this.semanticsLabel,
    this.arm = PresetArm.none,
  });

  final int minutes;
  final bool selected;

  /// Marcado a la espera del segundo toque: contorno grueso, sin relleno.
  final PresetArm arm;

  /// Tipo de hora del día: da el color al botón seleccionado.
  final DataKind kind;
  final VoidCallback onPressed;

  /// Texto en lugar de la cifra, p. ej. «Otra» o «6 h».
  final String? text;

  /// Lo que lee el lector de pantalla en lugar de «Apuntar X horas».
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = c.of(kind);
    final shown = text ?? formatMinutes(minutes);
    final armed = arm != PresetArm.none;
    // Borrar se marca en coral; apuntar, en el color del día.
    final armColor = arm == PresetArm.delete ? c.festive.strong : k.strong;
    final filled = selected && !armed;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel ?? 'Apuntar ${hoursPhrase(minutes)}',
      hint: switch (arm) {
        PresetArm.none => null,
        PresetArm.save => 'Toca otra vez para apuntar',
        PresetArm.delete => 'Toca otra vez para borrar',
      },
      excludeSemantics: true,
      child: Pressable(
        child: AnimatedContainer(
          duration: context.motion(Motion.fast),
          height: Sizes.presetHeight,
          decoration: BoxDecoration(
            color: filled ? k.strong : c.surface,
            borderRadius: BorderRadius.circular(Radii.medium),
            border: armed
                ? Border.all(color: armColor, width: 2.5)
                : Border.all(color: selected ? k.strong : c.outline),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.medium),
              onTap: () {
                if (!selected) Haptics.tap();
                onPressed();
              },
              child: Center(
                // El texto cambia de color al mismo ritmo que el fondo, para
                // que nunca quede del mismo color que este.
                child: AnimatedDefaultTextStyle(
                  duration: context.motion(Motion.fast),
                  style: AppText.title.copyWith(
                    color: armed
                        ? armColor
                        : filled
                        ? k.onStrong
                        : c.text,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(shown, maxLines: 1),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
