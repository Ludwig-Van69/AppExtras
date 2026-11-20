import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'haptics.dart';
import 'pressable.dart';

/// Selector de día: Hoy, Ayer y Anteayer (RF-14), y en la pantalla de
/// apuntar también «Otro día».
class DaySelector extends StatelessWidget {
  const DaySelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.labels = const ['Hoy', 'Ayer', 'Anteayer'],
  });

  final int selected;
  final ValueChanged<int> onChanged;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: Space.s),
          Expanded(
            child: Semantics(
              button: true,
              selected: i == selected,
              child: Pressable(
                child: AnimatedContainer(
                  duration: context.motion(Motion.fast),
                  height: Sizes.touch,
                  decoration: BoxDecoration(
                    color: i == selected ? c.text : c.surface,
                    borderRadius: BorderRadius.circular(Radii.large),
                    border: Border.all(
                      color: i == selected ? c.text : c.outline,
                    ),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.large),
                      onTap: () {
                        if (i != selected) Haptics.select();
                        onChanged(i);
                      },
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: context.motion(Motion.fast),
                          style: AppText.label.copyWith(
                            color: i == selected ? c.background : c.text,
                          ),
                          // Con cuatro opciones y letra grande, el texto se
                          // encoge un poco antes que cortarse.
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.xs,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(labels[i], maxLines: 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
