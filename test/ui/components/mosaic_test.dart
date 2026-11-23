import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/ui/components/mosaic.dart';
import 'package:horas_y_vacaciones/ui/theme/app_colors.dart';

import '../test_app.dart';

// Datos inventados: noviembre de 2026 empieza en domingo.
final _nov1 = DateTime(2026, 11, 1);
List<MosaicDay> _days(int count, [Map<int, DataKind> kinds = const {}]) => [
  for (var i = 0; i < count; i++)
    MosaicDay(_nov1.add(Duration(days: i)), kinds[i + 1]),
];

BoxDecoration _tile(WidgetTester tester, int day) =>
    tester
            .widget<AnimatedContainer>(find.byKey(ValueKey('tile-11-$day')))
            .decoration!
        as BoxDecoration;

void main() {
  testWidgets('el día 1 sin horas muestra solo «1» (013, RF-18)', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(Mosaic(days: _days(3))));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('nov'), findsNothing);
  });

  testWidgets('un día no laborable va sin relleno y con contorno coral '
      '(013, RF-6)', (tester) async {
    await tester.pumpWidget(
      testApp(
        Mosaic(
          days: [
            MosaicDay.muted(DateTime(2026, 11, 1)),
            MosaicDay(DateTime(2026, 11, 2)),
          ],
        ),
      ),
    );
    final off = _tile(tester, 1);
    expect(off.color, Colors.transparent);
    expect(off.border!.top.color, AppColors.light.festive.strong);
    expect(_tile(tester, 2).border, isNull);
    expect(find.text('Festivo'), findsOneWidget); // en la leyenda (RF-7)
  });

  group('Semanas de lunes a domingo (RF-12)', () {
    test('el primer día se coloca en su día de la semana', () {
      final weeks = Mosaic.weeksOf(_days(3));
      expect(weeks.first.take(6), everyElement(isNull));
      expect(weeks.first[6]!.date, _nov1);
    });

    test('las semanas incompletas se rellenan hasta 7 huecos', () {
      final weeks = Mosaic.weeksOf(_days(3));
      expect(weeks.length, 2);
      expect(weeks.every((w) => w.length == 7), isTrue);
      expect(weeks[1].skip(2), everyElement(isNull));
    });

    test('sin días no hay semanas', () {
      expect(Mosaic.weeksOf(const []), isEmpty);
    });
  });

  testWidgets(
    'Cada baldosa toma el color de su tipo y la vacía el suyo (RF-12)',
    (tester) async {
      const c = AppColors.light;
      await tester.pumpWidget(
        testApp(
          Mosaic(
            days: _days(4, {
              1: DataKind.festive,
              2: DataKind.normal,
              3: DataKind.vacation,
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_tile(tester, 1).color, c.festive.fill);
      expect(_tile(tester, 2).color, c.normal.fill);
      expect(_tile(tester, 3).color, c.vacation.fill);
      expect(_tile(tester, 4).color, c.empty);
    },
  );

  testWidgets('El día seleccionado lleva borde (RF-12)', (tester) async {
    await tester.pumpWidget(
      testApp(Mosaic(days: _days(3), selected: DateTime(2026, 11, 2))),
    );
    expect(_tile(tester, 2).border, isNotNull);
    expect(_tile(tester, 1).border, isNull);
  });

  testWidgets('El tipo también se dice con texto (RF-5)', (tester) async {
    await tester.pumpWidget(
      testApp(Mosaic(days: _days(2, {2: DataKind.normal}))),
    );
    for (final t in ['Normal', 'Festiva', 'Vacaciones']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.bySemanticsLabel('2 nov: Normal'), findsOneWidget);
    expect(find.bySemanticsLabel('1 nov: sin datos'), findsOneWidget);
  });

  testWidgets('Al cambiar de tipo la baldosa da un salto (RF-13)', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(Mosaic(days: _days(3))));
    await tester.pumpWidget(
      testApp(Mosaic(days: _days(3, {3: DataKind.normal}))),
    );
    await tester.pump(const Duration(milliseconds: 80));
    final scale = tester
        .widgetList<ScaleTransition>(
          find.ancestor(
            of: find.byKey(const ValueKey('tile-11-3')),
            matching: find.byType(ScaleTransition),
          ),
        )
        .map((t) => t.scale.value)
        .reduce((a, b) => a > b ? a : b);
    expect(scale, greaterThan(1.0));

    await tester.pumpAndSettle();
    expect(_tile(tester, 3).color, AppColors.light.normal.strong);
  });

  testWidgets('Sin salto si las animaciones están reducidas (RF-10)', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(Mosaic(days: _days(3)), reduceMotion: true),
    );
    await tester.pumpWidget(
      testApp(Mosaic(days: _days(3, {3: DataKind.normal})), reduceMotion: true),
    );
    await tester.pump(const Duration(milliseconds: 80));
    final scale = tester
        .widgetList<ScaleTransition>(
          find.ancestor(
            of: find.byKey(const ValueKey('tile-11-3')),
            matching: find.byType(ScaleTransition),
          ),
        )
        .map((t) => t.scale.value)
        .reduce((a, b) => a > b ? a : b);
    expect(scale, 1.0);
  });

  testWidgets('con minWeeks, un mes de 4 semanas mide lo mismo que uno de 6 '
      '(el calendario de «Otro día» no cambia de alto)', (tester) async {
    Future<Size> sizeOf(List<MosaicDay> days) async {
      await tester.pumpWidget(
        testApp(
          Mosaic(
            key: UniqueKey(),
            days: days,
            minWeeks: 6,
            showLegend: false,
            onTap: (_) {},
          ),
        ),
      );
      return tester.getSize(find.byType(Mosaic));
    }

    // Noviembre de 2026 ocupa 6 semanas; febrero de 2027, solo 4.
    final nov = await sizeOf(_days(30));
    final feb = await sizeOf([
      for (var d = 1; d <= 28; d++) MosaicDay(DateTime(2027, 2, d)),
    ]);
    expect(Mosaic.weeksOf(_days(30)).length, 6);
    expect(feb.height, nov.height);
  });
}
