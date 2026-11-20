import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/ui/catalog/catalog_screen.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/catalog/marea_demo.dart';
import 'package:horas_y_vacaciones/ui/components/big_hours.dart';
import 'package:horas_y_vacaciones/ui/components/hour_preset_button.dart';
import 'package:horas_y_vacaciones/ui/components/summary_figure.dart';
import 'package:horas_y_vacaciones/ui/theme/app_colors.dart';

import '../test_app.dart';

/// Apuntar y borrar piden dos toques seguidos (013, RF-1 a RF-3 y RF-20).
Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// Fallos encontrados en la revisión del sistema visual (gauntlet).
/// Cada test impide que el fallo vuelva.
void main() {
  Iterable<String> numbers(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(of: find.byType(BigHours), matching: find.byType(Text)),
      )
      .map((t) => t.data!)
      .where((t) => t != 'h');

  testWidgets('Cambios seguidos: nunca se ven más de dos cifras', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(const BigHours(minutes: 180)));
    for (final m in [240, 180, 300, 120]) {
      await tester.pumpWidget(testApp(BigHours(minutes: m)));
      await tester.pump(const Duration(milliseconds: 60));
      expect(numbers(tester).length, lessThanOrEqualTo(2));
    }
    await tester.pumpAndSettle();
    expect(numbers(tester), ['2']);
  });

  testWidgets('Volver al mismo valor enseguida (3 → 4 → 3) termina en 3', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(const BigHours(minutes: 180)));
    await tester.pumpWidget(testApp(const BigHours(minutes: 240)));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(testApp(const BigHours(minutes: 180)));
    await tester.pumpAndSettle();
    expect(numbers(tester), ['3']);
  });

  testWidgets('La «h» se desliza sin saltos cuando cambia la cifra', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(const BigHours(minutes: 150)));
    final positions = [tester.getTopLeft(find.text('h')).dx];
    await tester.pumpWidget(testApp(const BigHours(minutes: 240)));
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      positions.add(tester.getTopLeft(find.text('h')).dx);
    }
    final distance = (positions.last - positions.first).abs();
    var biggestStep = 0.0;
    for (var i = 1; i < positions.length; i++) {
      final step = (positions[i] - positions[i - 1]).abs();
      if (step > biggestStep) biggestStep = step;
    }
    // Ningún fotograma mueve la «h» más de un tercio del recorrido.
    expect(biggestStep, lessThan(distance / 3 + 1));
  });

  for (final (from, to) in [(150, 60), (60, 210)]) {
    testWidgets('La «h» nunca pisa una cifra al cambiar ($from → $to min)', (
      tester,
    ) async {
      // Fallo corregido: la cifra que sobresalía del hueco se dibujaba bajo
      // la «h» durante los primeros instantes del cambio.
      await tester.pumpWidget(testApp(BigHours(minutes: from)));
      await tester.pumpWidget(testApp(BigHours(minutes: to)));
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final visible = tester.getRect(
          find.byKey(const ValueKey('big-hours-number')),
        );
        expect(
          tester.getRect(find.text('h')).left,
          greaterThanOrEqualTo(visible.right),
        );
      }
    });
  }

  testWidgets('La «h» llega junto a la cifra nueva en menos de medio segundo', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(const BigHours(minutes: 150)));
    await tester.pumpWidget(testApp(const BigHours(minutes: 240)));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 480));
    final digit = tester.getRect(find.text('4'));
    final unit = tester.getRect(find.text('h'));
    expect(unit.left - digit.right, lessThan(16));
  });

  testWidgets('No vibra al tocar las horas que ya están elegidas', (
    tester,
  ) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add('vibra');
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      testApp(
        HourPresetButton(
          minutes: 120,
          selected: true,
          kind: DataKind.normal,
          onPressed: () {},
        ),
      ),
    );
    await tester.tap(find.byType(HourPresetButton));
    expect(calls, isEmpty);
  });

  group('Demostración de Marea', () {
    Future<void> open(
      WidgetTester tester, {
      Size size = const Size(390, 844),
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      calmAnimations(tester);
      await tester.pumpWidget(
        HoursAndVacationApp(home: MareaDemo(today: DateTime(2026, 11, 3))),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Deshacer tras cerrar la pantalla no falla: el aviso se va', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      calmAnimations(tester);
      await tester.pumpWidget(const HoursAndVacationApp(home: CatalogScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir la pantalla de apuntar'));
      await tester.pumpAndSettle();
      // Se borra con doble toque en la cifra apuntada (2,5 h).
      await _doubleTap(tester, find.bySemanticsLabel('Apuntar 2,5 horas').last);
      await tester.pumpAndSettle();
      expect(find.text('Deshacer'), findsOneWidget);

      await tester.tap(find.byTooltip('Volver al catálogo'));
      await tester.pumpAndSettle();
      expect(find.text('Deshacer'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Apuntar y cambiar el tipo no muestran aviso (RF-20)', (
      tester,
    ) async {
      await open(tester);
      await _doubleTap(tester, find.bySemanticsLabel('Apuntar 4 horas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Normal · 15 €/h'));
      await tester.pumpAndSettle();
      expect(find.text('Festiva · 20 €/h'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Borrar avisa con el valor que se ha borrado', (tester) async {
      await open(tester);
      await _doubleTap(tester, find.bySemanticsLabel('Apuntar 2,5 horas'));
      await tester.pumpAndSettle();
      expect(find.text('2,5 h borradas de hoy'), findsOneWidget);
    });

    testWidgets('Un cambio posterior quita el aviso de borrado', (
      tester,
    ) async {
      // Si no, «Deshacer» devolvería un valor viejo encima del nuevo.
      await open(tester);
      await _doubleTap(tester, find.bySemanticsLabel('Apuntar 2,5 horas'));
      await tester.pumpAndSettle();
      await _doubleTap(tester, find.bySemanticsLabel('Apuntar 3 horas'));
      await tester.pumpAndSettle();
      expect(find.text('Deshacer'), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'(^|\n)3 horas')), findsWidgets);
    });

    testWidgets('Deshacer un borrado vuelve al día afectado', (tester) async {
      await open(tester);
      await _doubleTap(tester, find.bySemanticsLabel('Apuntar 2,5 horas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ayer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(find.text('Martes, 3 de noviembre'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'2,5 horas')), findsWidgets);
    });

    testWidgets('Los botones de horas están en la mitad de abajo', (
      tester,
    ) async {
      await open(tester);
      final y = tester.getTopLeft(find.bySemanticsLabel('Apuntar 1 hora')).dy;
      expect(y, greaterThan(844 / 2));
    });

    testWidgets('El aviso con Deshacer no tapa los botones de horas', (
      tester,
    ) async {
      await open(tester);
      await _doubleTap(tester, find.bySemanticsLabel('Apuntar 2,5 horas'));
      await tester.pumpAndSettle();
      final notice = tester.getRect(find.byType(SnackBar));
      final lastButton = tester.getRect(
        find.bySemanticsLabel('Apuntar 5 horas'),
      );
      expect(notice.top, greaterThanOrEqualTo(lastButton.bottom));
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets(
        'Las cifras del resumen no se pegan (letra al ${(scale * 100).toInt()} %)',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await open(tester, size: const Size(360, 780));
          final rects = [
            for (final e in find.byType(SummaryFigure).evaluate())
              tester.getRect(find.byWidget(e.widget)),
          ];
          for (var i = 1; i < rects.length; i++) {
            expect(
              rects[i].left - rects[i - 1].right,
              greaterThanOrEqualTo(12),
            );
          }
        },
      );
    }
  });

  testWidgets(
    'El selector de tema cabe en una línea a 360 px con letra grande',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      calmAnimations(tester);
      await tester.pumpWidget(const HoursAndVacationApp(home: CatalogScreen()));
      await tester.pumpAndSettle();
      final auto = tester.getSize(find.text('Automático'));
      final claro = tester.getSize(find.text('Claro'));
      expect(auto.height, claro.height);
    },
  );
}
