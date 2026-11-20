import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/ui/components/big_hours.dart';
import 'package:horas_y_vacaciones/ui/components/day_heading.dart';
import 'package:horas_y_vacaciones/ui/components/day_selector.dart';
import 'package:horas_y_vacaciones/ui/components/hour_preset_button.dart';
import 'package:horas_y_vacaciones/ui/components/mosaic.dart';
import 'package:horas_y_vacaciones/ui/components/pressable.dart';
import 'package:horas_y_vacaciones/ui/components/tide.dart';
import 'package:horas_y_vacaciones/ui/components/undo.dart';
import 'package:horas_y_vacaciones/ui/theme/app_colors.dart';
import 'package:horas_y_vacaciones/ui/theme/tokens.dart';

import '../test_app.dart';

WavePainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byKey(const ValueKey('tide-level')),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as WavePainter;

Widget _tide(double v) =>
    Tide(value: v, max: 5, kind: DataKind.normal, height: 300);

/// Registra las vibraciones que pide la app.
List<String> _recordHaptics(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

void main() {
  group('Agua viva (RF-26)', () {
    testWidgets('la ola se mece sola', (tester) async {
      await tester.pumpWidget(testApp(_tide(2)));
      final start = _painter(tester).sway.value;
      await tester.pump(const Duration(milliseconds: 1500));
      expect(_painter(tester).sway.value, isNot(start));
    });

    testWidgets('el vaivén es lento: un ciclo cada 5 segundos o más', (
      tester,
    ) async {
      expect(Tide.swayPeriod, greaterThanOrEqualTo(const Duration(seconds: 5)));
    });

    testWidgets('quieta con las animaciones reducidas', (tester) async {
      await tester.pumpWidget(testApp(_tide(2), reduceMotion: true));
      final start = _painter(tester).sway.value;
      await tester.pump(const Duration(seconds: 2));
      expect(_painter(tester).sway.value, start);
    });

    testWidgets('quieta cuando la pantalla no se ve', (tester) async {
      await tester.pumpWidget(
        testApp(TickerMode(enabled: false, child: _tide(2))),
      );
      final start = _painter(tester).sway.value;
      await tester.pump(const Duration(seconds: 2));
      expect(_painter(tester).sway.value, start);
    });
  });

  group('Burbujas (RF-27)', () {
    testWidgets('suben al apuntar más horas y terminan en menos de 1 s', (
      tester,
    ) async {
      await tester.pumpWidget(testApp(_tide(1)));
      await tester.pumpWidget(testApp(_tide(3)));
      await tester.pump(const Duration(milliseconds: 300));
      final mid = _painter(tester).bubbles.value;
      expect(mid, greaterThan(0));
      expect(mid, lessThan(1));
      await tester.pump(const Duration(milliseconds: 700));
      expect(_painter(tester).bubbles.isAnimating, isFalse);
    });

    testWidgets('no suben al bajar las horas', (tester) async {
      await tester.pumpWidget(testApp(_tide(3)));
      await tester.pumpWidget(testApp(_tide(1)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_painter(tester).bubbles.value, 0);
    });

    testWidgets('no suben con las animaciones reducidas', (tester) async {
      await tester.pumpWidget(testApp(_tide(1), reduceMotion: true));
      await tester.pumpWidget(testApp(_tide(3), reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_painter(tester).bubbles.value, 0);
    });
  });

  group('Cambio de cifra tipo marcador (RF-28)', () {
    Iterable<String> shown(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(BigHours),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data!)
        .where((t) => t != 'h');

    Offset slideOf(WidgetTester tester, String text) => tester
        .widget<SlideTransition>(
          find
              .ancestor(
                of: find.text(text),
                matching: find.byType(SlideTransition),
              )
              .first,
        )
        .position
        .value;

    testWidgets('sin valores intermedios: solo el anterior y el nuevo', (
      tester,
    ) async {
      // Fallo corregido: antes contaba 1,5, 2, 2,5… tan rápido que parecía
      // que los números se liaban.
      await tester.pumpWidget(testApp(const BigHours(minutes: 60)));
      await tester.pumpWidget(testApp(const BigHours(minutes: 300)));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(shown(tester).toSet().difference({'1', '5'}), isEmpty);
      }
      await tester.pumpAndSettle();
      expect(shown(tester), ['5']);
      expect(Motion.roll, lessThan(const Duration(milliseconds: 500)));
    });

    testWidgets('al subir, el nuevo entra por abajo', (tester) async {
      await tester.pumpWidget(testApp(const BigHours(minutes: 60)));
      await tester.pumpWidget(testApp(const BigHours(minutes: 300)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(slideOf(tester, '5').dy, greaterThan(0));
      expect(slideOf(tester, '1').dy, lessThan(0));
    });

    testWidgets('al bajar, el nuevo entra por arriba', (tester) async {
      await tester.pumpWidget(testApp(const BigHours(minutes: 300)));
      await tester.pumpWidget(testApp(const BigHours(minutes: 60)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(slideOf(tester, '1').dy, lessThan(0));
      expect(slideOf(tester, '5').dy, greaterThan(0));
    });

    testWidgets('sin movimiento con las animaciones reducidas', (tester) async {
      await tester.pumpWidget(
        testApp(const BigHours(minutes: 60), reduceMotion: true),
      );
      await tester.pumpWidget(
        testApp(const BigHours(minutes: 240), reduceMotion: true),
      );
      await tester.pump();
      expect(shown(tester), ['4']);
    });
  });

  group('Vibración ligera (RF-29)', () {
    testWidgets('al apuntar, cambiar de día, borrar y deshacer', (
      tester,
    ) async {
      final calls = _recordHaptics(tester);
      var day = 0;
      await tester.pumpWidget(
        testApp(
          StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                DaySelector(
                  selected: day,
                  onChanged: (i) => setState(() => day = i),
                ),
                HourPresetButton(
                  minutes: 120,
                  selected: false,
                  kind: DataKind.normal,
                  onPressed: () {},
                ),
                BigHours(
                  minutes: 120,
                  onDelete: () =>
                      showUndo(context, message: 'Borradas', onUndo: () {}),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Apuntar 2 horas'));
      await tester.tap(find.text('Ayer'));
      await tester.tap(find.byTooltip('Borrar las horas del día'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();

      expect(calls, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.lightImpact',
      ]);
    });

    testWidgets('no vibra al tocar el día que ya está elegido', (tester) async {
      final calls = _recordHaptics(tester);
      await tester.pumpWidget(
        testApp(DaySelector(selected: 0, onChanged: (_) {})),
      );
      await tester.tap(find.text('Hoy'));
      expect(calls, isEmpty);
    });
  });

  group('Botones con muelle (RF-30)', () {
    double scale(WidgetTester tester) => tester
        .widget<AnimatedScale>(
          find.descendant(
            of: find.byType(Pressable).first,
            matching: find.byType(AnimatedScale),
          ),
        )
        .scale;

    Widget button() => HourPresetButton(
      minutes: 180,
      selected: false,
      kind: DataKind.normal,
      onPressed: () {},
    );

    testWidgets('se hunde al pulsar y vuelve al soltar', (tester) async {
      await tester.pumpWidget(testApp(button()));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HourPresetButton)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(scale(tester), Pressable.pressedScale);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scale(tester), 1);
    });

    testWidgets('el selector de día también tiene muelle', (tester) async {
      await tester.pumpWidget(
        testApp(DaySelector(selected: 0, onChanged: (_) {})),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Ayer')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final scales = tester
          .widgetList<AnimatedScale>(find.byType(AnimatedScale))
          .map((s) => s.scale);
      expect(scales, contains(Pressable.pressedScale));
      await gesture.up();
    });

    testWidgets('quieto con las animaciones reducidas', (tester) async {
      await tester.pumpWidget(testApp(button(), reduceMotion: true));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HourPresetButton)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(scale(tester), 1);
      await gesture.up();
    });
  });

  group('Cambio de día (RF-31)', () {
    testWidgets('la fecha nueva entra deslizándose', (tester) async {
      await tester.pumpWidget(
        testApp(const DayHeading(text: 'Martes, 3 de noviembre')),
      );
      await tester.pumpWidget(
        testApp(const DayHeading(text: 'Lunes, 2 de noviembre')),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Martes, 3 de noviembre'), findsOneWidget);
      expect(find.text('Lunes, 2 de noviembre'), findsOneWidget);
      final slide = tester.widget<SlideTransition>(
        find
            .ancestor(
              of: find.text('Lunes, 2 de noviembre'),
              matching: find.byType(SlideTransition),
            )
            .first, // la más cercana: la de la fecha
      );
      // Hacia el pasado: entra desde la derecha, como el dedo que desliza
      // hacia la izquierda para ir a Ayer (0.6.1).
      expect(slide.position.value.dx, greaterThan(0));

      await tester.pumpAndSettle();
      expect(find.text('Martes, 3 de noviembre'), findsNothing);
      expect(find.text('Lunes, 2 de noviembre'), findsOneWidget);
    });

    testWidgets('sin deslizar con las animaciones reducidas', (tester) async {
      await tester.pumpWidget(
        testApp(const DayHeading(text: 'Martes'), reduceMotion: true),
      );
      await tester.pumpWidget(
        testApp(const DayHeading(text: 'Lunes'), reduceMotion: true),
      );
      await tester.pump();
      expect(find.text('Martes'), findsNothing);
      expect(find.text('Lunes'), findsOneWidget);
    });
  });

  group('Mosaico en ola (RF-32)', () {
    final days = [
      for (var i = 0; i < 21; i++) MosaicDay(DateTime(2026, 10, 5 + i)),
    ];

    List<double> opacities(WidgetTester tester) => tester
        .widgetList<FadeTransition>(
          find.descendant(
            of: find.byType(Mosaic),
            matching: find.byType(FadeTransition),
          ),
        )
        .map((f) => f.opacity.value)
        .toList();

    testWidgets('aparece en diagonal y termina en menos de 1 s', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(Mosaic(days: days, animateEntrance: true)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final o = opacities(tester);
      // La primera baldosa (arriba a la izquierda) va por delante de la última.
      expect(o.first, greaterThan(o.last));
      await tester.pump(const Duration(milliseconds: 800));
      expect(opacities(tester), everyElement(1.0));
      expect(Mosaic.entranceDuration, lessThan(const Duration(seconds: 1)));
    });

    testWidgets('sin ola si no se pide', (tester) async {
      await tester.pumpWidget(testApp(Mosaic(days: days)));
      expect(opacities(tester), everyElement(1.0));
    });

    testWidgets('sin ola con las animaciones reducidas', (tester) async {
      await tester.pumpWidget(
        testApp(Mosaic(days: days, animateEntrance: true), reduceMotion: true),
      );
      await tester.pump();
      expect(opacities(tester), everyElement(1.0));
    });
  });
}
