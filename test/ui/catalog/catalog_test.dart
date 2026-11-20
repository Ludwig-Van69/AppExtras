import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/catalog/catalog_screen.dart';
import 'package:horas_y_vacaciones/ui/catalog/marea_demo.dart';
import 'package:horas_y_vacaciones/ui/theme/app_colors.dart';

import '../test_app.dart';

/// Apuntar y borrar piden dos toques seguidos (013, RF-1 a RF-3 y RF-20).
Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.tap(finder);
}

Color _background(WidgetTester tester, Type screen) =>
    Theme.of(tester.element(find.byType(screen)))
        .extension<AppColors>()!
        .background;

/// La lista lee juntos los textos de cada bloque; se busca la línea de horas.
Finder _hoursLabel(String hours) =>
    find.bySemanticsLabel(RegExp('(^|\n)$hours horas(\n|\$)'));

void main() {
  testWidgets('El catálogo reúne todas las piezas y cambia de tema (RF-24)', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    calmAnimations(tester);
    await tester.pumpWidget(const HoursAndVacationApp(home: CatalogScreen()));
    await tester.pumpAndSettle();

    for (final section in [
      'Tema',
      'Demostración',
      'Colores por tipo',
      'Tipografía',
      'Marea',
      'Mosaico',
      'Apuntar',
      'Botones y campos',
      'Tarjetas y listas',
      'Diálogos y avisos',
      'Estados',
    ]) {
      await tester.scrollUntilVisible(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text(section),
        ),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(section), findsWidgets, reason: section);
    }

    await tester.scrollUntilVisible(
      find.text('Oscuro'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();
    expect(_background(tester, CatalogScreen), AppColors.dark.background);

    await tester.tap(find.text('Automático'));
    await tester.pumpAndSettle();
    expect(_background(tester, CatalogScreen), AppColors.light.background);
  });

  group('Demostración de Marea (RF-25)', () {
    // Datos inventados: martes 3 de noviembre de 2026.
    Future<void> openDemo(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      calmAnimations(tester);
      await tester.pumpWidget(
        HoursAndVacationApp(home: MareaDemo(today: DateTime(2026, 11, 3))),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Apuntar, borrar y deshacer', (tester) async {
      await openDemo(tester);
      expect(find.text('Martes, 3 de noviembre'), findsOneWidget);
      expect(find.text('2,5'), findsWidgets);

      await _doubleTap(tester, find.bySemanticsLabel('Apuntar 3 horas'));
      await tester.pumpAndSettle();
      // Apuntar no muestra aviso: el cambio se ve en la cifra (RF-20).
      expect(find.text('Deshacer'), findsNothing);
      expect(_hoursLabel('3'), findsOneWidget);

      await _doubleTap(tester, find.bySemanticsLabel('Apuntar 3 horas'));
      await tester.pumpAndSettle();
      expect(_hoursLabel('0'), findsOneWidget);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(_hoursLabel('3'), findsOneWidget);
    });

    testWidgets('Anteayer es domingo: festiva, con sus horas y su tarifa', (
      tester,
    ) async {
      await openDemo(tester);
      await tester.tap(find.text('Anteayer'));
      await tester.pumpAndSettle();
      expect(find.text('Domingo, 1 de noviembre'), findsOneWidget);
      expect(find.text('Festiva · 20 €/h'), findsOneWidget);
      expect(find.bySemanticsLabel('Apuntar 11 horas'), findsOneWidget);

      await tester.tap(find.text('Festiva · 20 €/h'));
      await tester.pumpAndSettle();
      expect(find.text('Normal · 15 €/h'), findsOneWidget);
    });

    testWidgets('Lo que se apunta suma a lo que se debe', (tester) async {
      await openDemo(tester);
      // 412,50 € previos + 2,5 h y 1 h a 15 €.
      expect(find.text('465,00 €'), findsOneWidget);
      await _doubleTap(tester, find.bySemanticsLabel('Apuntar 4 horas'));
      await tester.pumpAndSettle();
      expect(find.text('487,50 €'), findsOneWidget);
    });
  });
}
