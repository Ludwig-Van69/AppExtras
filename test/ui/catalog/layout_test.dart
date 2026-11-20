import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/catalog/catalog_screen.dart';
import 'package:horas_y_vacaciones/ui/catalog/marea_demo.dart';

import '../test_app.dart';

/// Recorre la pantalla de arriba abajo para que se dibuje entera y
/// comprueba que nada se desborda.
Future<void> _scrollThrough(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 40; i++) {
    final position = tester.state<ScrollableState>(scrollable).position;
    if (position.pixels >= position.maxScrollExtent) break;
    await tester.drag(scrollable, const Offset(0, -400));
    // El indicador de «cargando» gira sin parar: se espera un tiempo fijo.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  }
}

void main() {
  const widths = [360.0, 390.0, 412.0];
  const scales = [1.0, 1.3];

  for (final brightness in Brightness.values) {
    for (final width in widths) {
      for (final scale in scales) {
        final name =
            '${width.toInt()} px, letra al ${(scale * 100).toInt()} %, '
            'tema ${brightness == Brightness.light ? 'claro' : 'oscuro'}';

        Future<void> pump(WidgetTester tester, Widget? home) async {
          await tester.binding.setSurfaceSize(Size(width, 780));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearAllTestValues);
          calmAnimations(tester);
          await tester.pumpWidget(HoursAndVacationApp(home: home));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        testWidgets('Catálogo sin desbordes: $name', (tester) async {
          await pump(tester, const CatalogScreen());
          await _scrollThrough(tester);
        });

        testWidgets('Demostración sin desbordes: $name', (tester) async {
          await pump(tester, MareaDemo(today: DateTime(2026, 11, 3)));
          // La cifra más ancha posible y un día festivo.
          await tester.tap(find.text('Anteayer'));
          await tester.pumpAndSettle();
          await tester.tap(find.bySemanticsLabel('Apuntar 10 horas'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await _scrollThrough(tester);
        });
      }
    }
  }
}
