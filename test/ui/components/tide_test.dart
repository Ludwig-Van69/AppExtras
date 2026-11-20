import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/ui/components/tide.dart';
import 'package:horas_y_vacaciones/ui/theme/app_colors.dart';

import '../test_app.dart';

double _level(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey('tide-level'))).height -
    Tide.waveHeight;

Widget _tide(double value, {DataKind kind = DataKind.normal}) =>
    Tide(value: value, max: 5, kind: kind, height: 400);

void main() {
  group('Nivel del agua (RF-11)', () {
    double level(double v) =>
        Tide.levelFor(value: v, max: 5, height: 400, minLevel: 36);

    test('con 0 horas queda el nivel mínimo', () => expect(level(0), 36));
    test('con el máximo llega arriba sin tapar la ola', () {
      expect(level(5), 400 - Tide.waveHeight);
    });
    test('sube en proporción al valor', () {
      expect(level(2.5), closeTo((36 + 378) / 2, 0.001));
    });
    test('por encima del máximo no se desborda', () {
      expect(level(11), level(5));
    });
    test('un valor negativo se queda en el mínimo', () {
      expect(level(-3), 36);
    });
  });

  testWidgets('Sube con animación y termina en menos de 1 segundo (RF-11)', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(_tide(1)));
    final start = _level(tester);

    await tester.pumpWidget(testApp(_tide(4)));
    await tester.pump(const Duration(milliseconds: 100));
    final midway = _level(tester);
    expect(midway, greaterThan(start));

    await tester.pump(const Duration(milliseconds: 900));
    expect(
      _level(tester),
      closeTo(Tide.levelFor(value: 4, max: 5, height: 400, minLevel: 36), 0.01),
    );
  });

  testWidgets('Sin animación si el móvil las tiene reducidas (RF-10)', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(_tide(1), reduceMotion: true));
    await tester.pumpWidget(testApp(_tide(4), reduceMotion: true));
    await tester.pump();
    expect(
      _level(tester),
      closeTo(Tide.levelFor(value: 4, max: 5, height: 400, minLevel: 36), 0.01),
    );
  });

  testWidgets('El agua toma el color del tipo de hora (RF-11)', (tester) async {
    await tester.pumpWidget(testApp(_tide(2, kind: DataKind.festive)));
    await tester.pump(const Duration(seconds: 1));
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey('tide-level')),
        matching: find.byType(CustomPaint),
      ),
    );
    final painter = paint.painter!;
    // El pintor guarda el color con el que dibuja el agua.
    expect((painter as dynamic).color, AppColors.light.festive.soft);
  });
}
