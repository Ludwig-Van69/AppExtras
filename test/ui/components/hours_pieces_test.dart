import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/ui/components/big_hours.dart';
import 'package:horas_y_vacaciones/ui/components/day_selector.dart';
import 'package:horas_y_vacaciones/ui/components/hour_preset_button.dart';
import 'package:horas_y_vacaciones/ui/components/summary_figure.dart';
import 'package:horas_y_vacaciones/ui/format.dart';
import 'package:horas_y_vacaciones/ui/theme/app_colors.dart';

import '../test_app.dart';

void main() {
  group('Formatos', () {
    test('horas con coma y sin ceros sobrantes', () {
      expect(formatMinutes(150), '2,5');
      expect(formatMinutes(180), '3');
      expect(formatMinutes(0), '0');
      expect(formatMinutes(75), '1,25');
      expect(formatMinutes(45), '0,75');
      expect(formatMinutes(80), '1,33');
      expect(formatMinutes(-90), '-1,5');
    });
    test('nunca deja una coma colgando (fallo corregido)', () {
      // Antes, 2,001 h se mostraba «2,» y 7,999 h «8,».
      for (var m = 0; m <= 24 * 60; m++) {
        expect(formatMinutes(m), isNot(endsWith(',')), reason: '$m min');
      }
    });
    test('«1 hora» en singular y el resto en plural', () {
      expect(hoursPhrase(60), '1 hora');
      expect(hoursPhrase(90), '1,5 horas');
      expect(hoursPhrase(0), '0 horas');
    });
    test('euros desde céntimos, con miles y signo', () {
      expect(formatEuros(41250), '412,50 €');
      expect(formatEuros(123450), '1.234,50 €');
      expect(formatEuros(5), '0,05 €');
      expect(formatEuros(-10000), '-100,00 €');
    });
  });

  testWidgets('Selector de día: cambia y marca el elegido (RF-14)', (
    tester,
  ) async {
    var picked = 0;
    await tester.pumpWidget(
      testApp(
        StatefulBuilder(
          builder: (context, setState) => DaySelector(
            selected: picked,
            onChanged: (i) => setState(() => picked = i),
          ),
        ),
      ),
    );
    for (final t in ['Hoy', 'Ayer', 'Anteayer']) {
      expect(find.text(t), findsOneWidget);
    }
    await tester.tap(find.text('Anteayer'));
    await tester.pumpAndSettle();
    expect(picked, 2);
    expect(
      tester.getSemantics(find.text('Anteayer')),
      matchesSemantics(
        isSelected: true,
        isButton: true,
        hasSelectedState: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
        label: 'Anteayer',
      ),
    );
    expect(
      tester.getSize(find.byType(DaySelector)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('Botón de horas: seleccionado con el color del tipo (RF-15)', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      testApp(
        Column(
          children: [
            HourPresetButton(
              minutes: 150,
              selected: true,
              kind: DataKind.festive,
              onPressed: () => taps++,
            ),
            HourPresetButton(
              minutes: 180,
              selected: false,
              kind: DataKind.festive,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boxes = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((w) => (w.decoration! as BoxDecoration).color)
        .toList();
    expect(boxes, [AppColors.light.festive.strong, AppColors.light.surface]);
    await tester.tap(find.bySemanticsLabel('Apuntar 2,5 horas'));
    expect(taps, 1);
  });

  testWidgets('Cifra grande: muestra el valor nuevo al terminar (RF-16)', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(const BigHours(minutes: 60)));
    await tester.pumpWidget(testApp(const BigHours(minutes: 150)));
    await tester.pumpAndSettle();
    expect(find.text('2,5'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('Borrar solo aparece cuando el día tiene horas (RF-17)', (
    tester,
  ) async {
    var deleted = false;
    await tester.pumpWidget(testApp(BigHours(minutes: 0, onDelete: () {})));
    expect(find.byTooltip('Borrar las horas del día'), findsNothing);

    await tester.pumpWidget(
      testApp(BigHours(minutes: 120, onDelete: () => deleted = true)),
    );
    await tester.tap(find.byTooltip('Borrar las horas del día'));
    expect(deleted, isTrue);
    expect(
      tester.getSize(find.byTooltip('Borrar las horas del día')).width,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('Resumen de cifra con su etiqueta y color de tipo', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        const SummaryFigure(label: 'Bolsa', value: '24 h', kind: DataKind.bag),
      ),
    );
    expect(find.bySemanticsLabel('Bolsa: 24 h'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('24 h')).style!.color,
      AppColors.light.bag.strong,
    );
  });

  testWidgets(
    'La cifra y el botón de borrar no se mueven al cambiar de valor (fallo corregido)',
    (tester) async {
      // Antes, «3,5» y «3» tenían tamaños distintos y todo saltaba al contar.
      // Y con minutos sueltos (10,75 h) se salía de su sitio a 360 px.
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Size? size;
      Offset? delete;
      for (final h in [60, 150, 180, 210, 630, 645, 660, 5325]) {
        await tester.pumpWidget(
          testApp(BigHours(minutes: h, onDelete: () {}), reduceMotion: true),
        );
        await tester.pump();
        final s = tester.getSize(find.byType(BigHours));
        final d = tester.getTopLeft(find.byTooltip('Borrar las horas del día'));
        size ??= s;
        delete ??= d;
        expect(s, size, reason: 'tamaño con $h h');
        expect(d, delete, reason: 'botón de borrar con $h h');
      }
    },
  );

  testWidgets('Sin horas, el hueco del botón de borrar se mantiene', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(BigHours(minutes: 120, onDelete: () {}), reduceMotion: true),
    );
    final withButton = tester.getSize(find.byType(BigHours));
    await tester.pumpWidget(
      testApp(BigHours(minutes: 0, onDelete: () {}), reduceMotion: true),
    );
    await tester.pump();
    expect(tester.getSize(find.byType(BigHours)), withButton);
  });
}
