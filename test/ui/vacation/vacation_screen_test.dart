import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/holidays.dart';
import 'package:horas_y_vacaciones/domain/vacations.dart';
import 'package:horas_y_vacaciones/ui/theme/app_colors.dart';
import 'package:horas_y_vacaciones/ui/theme/app_theme.dart';
import 'package:horas_y_vacaciones/ui/vacation/vacation_controller.dart';
import 'package:horas_y_vacaciones/ui/vacation/vacation_screen.dart';

import '../../fakes/in_memory_vacation_repository.dart';
import '../test_app.dart';

/// Miércoles 18 de noviembre de 2026. Datos inventados.
final _now = DateTime(2026, 11, 18, 10);
final _settings = VacationSettings(firstYear: 2025, firstHalfDays: 44);

late InMemoryVacationRepository repo;
late VacationController vacation;

Future<void> _open(
  WidgetTester tester, {
  VacationSettings? settings,
  List<VacationDay> days = const [],
  double width = 390,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  calmAnimations(tester);
  await tester.binding.setSurfaceSize(Size(width, 1000));
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.platformDispatcher.clearAllTestValues();
  });
  repo = InMemoryVacationRepository(stored: settings, days: days);
  vacation = VacationController(
    repository: repo,
    clock: () => _now,
    calendar: HolidayCalendar.new,
  );
  await vacation.load();
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      home: VacationScreen(vacation: vacation),
    ),
  );
  await tester.pumpAndSettle();
}

/// La baldosa del día [day] del mes que se ve.
Finder _tile(int day, String month) =>
    find.bySemanticsLabel(RegExp('^$day $month:')).first;

void main() {
  testWidgets('sin configurar pide configurar (RF-4)', (tester) async {
    await _open(tester);
    expect(find.text('Configura tus vacaciones'), findsOneWidget);
    expect(find.text('Te quedan'), findsNothing);
    await tester.tap(find.text('Configurar'));
    await tester.pumpAndSettle();
    expect(find.text('Primer año'), findsOneWidget);
  });

  testWidgets('saldo, planificados y marcar un día (RF-5, RF-12)', (
    tester,
  ) async {
    await _open(
      tester,
      settings: _settings,
      days: [VacationDay(DateTime(2026, 12, 21), 2026)],
    );
    expect(find.text('43 días'), findsOneWidget); // 44 + 44 − 1
    expect(find.text('incluye 1 día planificado'), findsOneWidget);
    await tester.tap(_tile(19, 'nov'));
    await tester.pumpAndSettle();
    expect(repo.byDate[DateTime(2026, 11, 19)]!.year, 2026);
    expect(find.text('42 días'), findsOneWidget);
  });

  testWidgets('desmarcar con Deshacer (RF-5)', (tester) async {
    await _open(
      tester,
      settings: _settings,
      days: [VacationDay(DateTime(2026, 11, 2), 2026)],
    );
    await tester.tap(_tile(2, 'nov'));
    await tester.pumpAndSettle();
    expect(repo.byDate, isEmpty);
    expect(find.text('2 nov ya no es de vacaciones'), findsOneWidget);
    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(repo.byDate.values.single, VacationDay(DateTime(2026, 11, 2), 2026));
  });

  testWidgets('un sábado no se marca y lo explica (RF-6)', (tester) async {
    await _open(tester, settings: _settings);
    await tester.tap(_tile(21, 'nov'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Los sábados, domingos y festivos no gastan días de vacaciones',
      ),
      findsOneWidget,
    );
    expect(repo.byDate, isEmpty);
  });

  testWidgets('enero cuenta para el año anterior; pulsación larga lo cambia '
      '(RF-8 a RF-10)', (tester) async {
    await _open(tester, settings: _settings);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('Mes siguiente'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Enero 2027'), findsOneWidget);
    await tester.tap(_tile(4, 'ene'));
    await tester.pumpAndSettle();
    expect(repo.byDate[DateTime(2027, 1, 4)]!.year, 2026);
    expect(find.text('4 ene: cuenta para 2026'), findsOneWidget);
    expect(find.text('’26'), findsOneWidget);
    await tester.longPress(_tile(4, 'ene'));
    await tester.pumpAndSettle();
    // El menú ofrece el otro año (012, RF-9).
    expect(find.text('Ahora cuenta para 2026'), findsOneWidget);
    await tester.tap(find.text('Contar para 2027'));
    await tester.pumpAndSettle();
    expect(repo.byDate[DateTime(2027, 1, 4)]!.year, 2027);
    expect(find.text('4 ene: cuenta para 2027'), findsOneWidget);
    expect(find.text('’26'), findsNothing);
  });

  testWidgets('pulsación larga: medio día resta 0,5 y se ve a medias '
      '(012, RF-9 a RF-11)', (tester) async {
    await _open(
      tester,
      settings: _settings,
      days: [VacationDay(DateTime(2026, 11, 20), 2026)],
    );
    expect(find.text('43 días'), findsOneWidget);
    await tester.longPress(_tile(20, 'nov'));
    await tester.pumpAndSettle();
    expect(find.text('20 de noviembre'), findsOneWidget);
    await tester.tap(find.text('Medio día'));
    await tester.pumpAndSettle();
    expect(repo.byDate[DateTime(2026, 11, 20)]!.half, isTrue);
    expect(find.text('20 nov: medio día'), findsOneWidget);
    expect(find.text('43,5 días'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('^20 nov: Vacaciones, medio día')),
      findsOneWidget,
    );
    expect(find.text('½'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('fila-2026')),
        matching: find.text('Generados 22 · Disfrutados 0,5'),
      ),
      findsOneWidget,
    );
    // Y vuelta a día entero.
    await tester.longPress(_tile(20, 'nov'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Día entero'));
    await tester.pumpAndSettle();
    expect(repo.byDate[DateTime(2026, 11, 20)]!.half, isFalse);
    expect(find.text('43 días'), findsOneWidget);
  });

  testWidgets('el primer año no ofrece contar para el anterior (012, RF-9)', (
    tester,
  ) async {
    await _open(
      tester,
      settings: VacationSettings(firstYear: 2026, firstHalfDays: 44),
      days: [VacationDay(DateTime(2026, 11, 20), 2026)],
    );
    await tester.longPress(_tile(20, 'nov'));
    await tester.pumpAndSettle();
    expect(find.text('Medio día'), findsOneWidget);
    expect(find.textContaining('Contar para'), findsNothing);
  });

  testWidgets('no se pasa del final del año que viene (RF-7)', (tester) async {
    await _open(tester, settings: _settings);
    for (var i = 0; i < 13; i++) {
      await tester.tap(find.byTooltip('Mes siguiente'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Diciembre 2027'), findsOneWidget);
    final next = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Mes siguiente'),
        matching: find.byType(IconButton),
      ),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('las dos vistas y saltar a un año (RF-13 a RF-15)', (
    tester,
  ) async {
    await _open(
      tester,
      settings: _settings,
      days: [
        VacationDay(DateTime(2026, 1, 2), 2025),
        VacationDay(DateTime(2026, 6, 1), 2026),
      ],
    );
    expect(find.text('Por año de vacaciones'), findsOneWidget);
    final row2025 = find.byKey(const ValueKey('fila-2025'));
    expect(
      find.descendant(
        of: row2025,
        matching: find.text('Generados 22 · Disfrutados 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row2025, matching: find.text('Quedan 21')),
      findsOneWidget,
    );
    await tester.tap(find.text('Por año natural'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Generados'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('fila-2026')),
        matching: find.text('2 días'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('fila-2025')));
    await tester.tap(find.byKey(const ValueKey('fila-2025')));
    await tester.pumpAndSettle();
    expect(find.text('Enero 2025'), findsOneWidget);
    // El total ya está arriba: sin repetirlo al pie (012, RF-7).
    expect(find.textContaining('Te quedan 4'), findsNothing);
  });

  testWidgets('ir a un mes de otro año con el selector (011, RF-1)', (
    tester,
  ) async {
    await _open(tester, settings: _settings);
    await tester.tap(find.byKey(const ValueKey('elegir-mes')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Año anterior'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('2025'),
      ),
      findsOneWidget,
    );
    // 2024 queda fuera: el primer año es 2025.
    final back = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Año anterior'),
        matching: find.byType(IconButton),
      ),
    );
    expect(back.onPressed, isNull);
    await tester.tap(find.text('Marzo'));
    await tester.pumpAndSettle();
    expect(find.text('Marzo 2025'), findsOneWidget);
  });

  testWidgets('la explicación de «’25» solo sale cuando hace falta '
      '(011, RF-2)', (tester) async {
    await _open(
      tester,
      settings: _settings,
      days: [VacationDay(DateTime(2026, 1, 2), 2025)],
    );
    expect(find.text('Toca un día para marcarlo o quitarlo'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('elegir-mes')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enero'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        '’25: estos días se descuentan de las vacaciones '
        'de 2025',
      ),
      findsOneWidget,
    );
  });

  testWidgets('sábados y festivos se ven atenuados (011, RF-3)', (
    tester,
  ) async {
    await _open(tester, settings: _settings);
    expect(find.bySemanticsLabel('21 nov: no laborable'), findsOneWidget);
    expect(find.bySemanticsLabel('20 nov: sin datos'), findsOneWidget);
  });

  testWidgets('años antiguos en un desplegable, con color (011, RF-4)', (
    tester,
  ) async {
    await _open(
      tester,
      settings: VacationSettings(firstYear: 2021, firstHalfDays: 23),
      days: [
        for (var d = 1; d <= 31; d++)
          if (DateTime(2021, 8, d).weekday <= 5)
            VacationDay(DateTime(2021, 8, d), 2021),
      ],
    );
    expect(find.byKey(const ValueKey('fila-2026')), findsOneWidget);
    expect(find.byKey(const ValueKey('fila-2025')), findsOneWidget);
    // 2021 está en negativo: el desplegable viene abierto (012, RF-8).
    expect(find.byKey(const ValueKey('fila-2021')), findsOneWidget);
    expect(find.text('Quedan −10,5'), findsOneWidget); // 11,5 − 22: en rojo
    // −10,5 + 3 × 22 = 55,5
    expect(find.text('Años anteriores (4) · 55,5'), findsOneWidget);
  });

  testWidgets('el desplegable suma sus años y va cerrado sin negativos '
      '(012, RF-8)', (tester) async {
    await _open(
      tester,
      settings: VacationSettings(firstYear: 2021, firstHalfDays: 23),
    );
    expect(find.byKey(const ValueKey('fila-2021')), findsNothing);
    // 11,5 + 3 × 22 = 77,5
    await tester.ensureVisible(find.text('Años anteriores (4) · 77,5'));
    await tester.tap(find.text('Años anteriores (4) · 77,5'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fila-2021')), findsOneWidget);
  });

  testWidgets('un desplegable en negativo se ve en rojo (012, RF-8)', (
    tester,
  ) async {
    await _open(
      tester,
      settings: VacationSettings(firstYear: 2024, firstHalfDays: 7),
      days: [
        for (var d = 1; d <= 31; d++)
          if (DateTime(2024, 8, d).weekday <= 5)
            VacationDay(DateTime(2024, 8, d), 2024),
      ],
    );
    // 2024: 3,5 − 22 = −18,5; 2025 y 2026: 22 cada uno; total 25,5
    final title = tester.widget<Text>(find.text('Años anteriores (1) · −18,5'));
    expect(title.style?.color, AppColors.light.error);
    expect(find.text('25,5 días'), findsOneWidget);
  });

  testWidgets('un día marcado que es festivo se avisa (RF-11)', (tester) async {
    await _open(
      tester,
      settings: _settings,
      days: [VacationDay(DateTime(2026, 12, 8), 2026)],
    );
    await tester.tap(find.byTooltip('Mes siguiente'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('El 8 de diciembre no es laborable'),
      findsOneWidget,
    );
  });

  group('tamaños sin desbordes', () {
    for (final width in [360.0, 412.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('$width px, letra al 130 %, ${brightness.name}', (
          tester,
        ) async {
          await _open(
            tester,
            settings: _settings,
            width: width,
            scale: 1.3,
            brightness: brightness,
            days: [VacationDay(DateTime(2026, 1, 2), 2025)],
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Por año natural'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
