import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/ui/theme/app_colors.dart';

/// Contraste según WCAG 2.x.
double contrast(Color a, Color b) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  const text = 4.5;
  const large = 3.0;

  for (final (name, c) in [
    ('claro', AppColors.light),
    ('oscuro', AppColors.dark),
  ]) {
    group('Contraste del tema $name (RF-6)', () {
      final pairs = <String, (Color, Color, double)>{
        'texto sobre fondo': (c.text, c.background, text),
        'texto sobre superficie': (c.text, c.surface, text),
        'texto suave sobre fondo': (c.textSoft, c.background, text),
        'texto suave sobre superficie': (c.textSoft, c.surface, text),
        'texto suave sobre baldosa vacía': (c.textSoft, c.empty, text),
        'aviso: fondo sobre texto': (c.background, c.text, text),
        'error sobre fondo': (c.error, c.background, text),
        'error sobre superficie': (c.error, c.surface, text),
        'borde sobre fondo': (c.outline, c.background, large),
        'borde sobre superficie': (c.outline, c.surface, large),
      };
      for (final kind in DataKind.values) {
        final k = c.of(kind);
        pairs['${kind.name}: color como texto sobre fondo'] = (
          k.strong,
          c.background,
          text,
        );
        pairs['${kind.name}: color como texto sobre superficie'] = (
          k.strong,
          c.surface,
          text,
        );
        pairs['${kind.name}: texto sobre su color'] = (
          k.onStrong,
          k.strong,
          text,
        );
        pairs['${kind.name}: texto sobre su relleno (013, RF-8)'] = (
          k.onFill,
          k.fill,
          text,
        );
        pairs['${kind.name}: texto sobre su color suave'] = (
          c.text,
          k.soft,
          text,
        );
      }

      pairs.forEach((label, p) {
        test(label, () {
          final ratio = contrast(p.$1, p.$2);
          expect(
            ratio,
            greaterThanOrEqualTo(p.$3),
            reason: '$label: ${ratio.toStringAsFixed(2)}:1, mínimo ${p.$3}:1',
          );
        });
      });
    });
  }

  test('Cada tipo de dato tiene un color distinto (RF-4)', () {
    for (final c in [AppColors.light, AppColors.dark]) {
      final strong = DataKind.values.map((k) => c.of(k).strong).toSet();
      expect(strong.length, DataKind.values.length);
    }
  });
}
