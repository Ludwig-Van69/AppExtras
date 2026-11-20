import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/vacations.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/components/app_nav_bar.dart';
import 'package:horas_y_vacaciones/data/holiday_store.dart';
import 'package:horas_y_vacaciones/ui/extras/extras_controller.dart';
import 'package:horas_y_vacaciones/ui/holidays/holidays_controller.dart';
import 'package:horas_y_vacaciones/ui/money/money_controller.dart';
import 'package:horas_y_vacaciones/ui/vacation/vacation_controller.dart';

import '../../fakes/in_memory_day_entry_repository.dart';
import '../../fakes/in_memory_extras_repository.dart';
import '../../fakes/in_memory_money_repository.dart';
import '../../fakes/in_memory_vacation_repository.dart';
import '../test_app.dart';

/// Miércoles 18 de noviembre de 2026. Datos inventados.
final _now = DateTime(2026, 11, 18, 10);

late InMemoryVacationRepository repo;

Future<void> _open(
  WidgetTester tester, {
  bool configured = true,
  double width = 390,
  double scale = 1,
  bool half = false,
}) async {
  calmAnimations(tester);
  await tester.binding.setSurfaceSize(Size(width, 844));
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.platformDispatcher.clearAllTestValues();
  });
  repo = InMemoryVacationRepository(
    stored: configured
        ? VacationSettings(firstYear: 2025, firstHalfDays: 44)
        : null,
    days: [VacationDay(DateTime(2026, 11, 18), 2026, half: half)],
  );
  final vacation = VacationController(repository: repo, clock: () => _now);
  await vacation.load();
  final money = MoneyController(
    days: InMemoryDayEntryRepository(),
    money: InMemoryMoneyRepository(),
    clock: () => _now,
  );
  await money.load();
  final extras = ExtrasController(
    repository: InMemoryExtrasRepository(),
    clock: () => _now,
  );
  await extras.load();
  await tester.pumpWidget(
    HoursAndVacationApp(
      repository: InMemoryDayEntryRepository(),
      money: money,
      extras: extras,
      vacation: vacation,
      clock: () => _now,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('orden de la barra: Vacaciones antes que Extra (015, RF-1)', (
    tester,
  ) async {
    await _open(tester);
    final bar = tester.widget<AppNavBar>(find.byType(AppNavBar));
    expect(bar.sections, [
      AppSection.log,
      AppSection.money,
      AppSection.vacation,
      AppSection.extra,
      AppSection.metrics,
    ]);
  });

  testWidgets('Vacaciones entra en la barra (RF-16)', (tester) async {
    await _open(tester);
    final bar = find.byType(AppNavBar);
    for (final label in ['Apuntar', 'Resumen', 'Extra', 'Vacaciones']) {
      expect(
        find.descendant(of: bar, matching: find.text(label)),
        findsOneWidget,
      );
    }
    await tester.tap(
      find.descendant(of: bar, matching: find.text('Vacaciones')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Te quedan'), findsOneWidget);
    expect(find.text('43 días'), findsOneWidget);
  });

  testWidgets('Apuntar señala el día de vacaciones (RF-17)', (tester) async {
    await _open(tester);
    expect(find.byKey(const ValueKey('dia-de-vacaciones')), findsOneWidget);
    expect(find.text('Vacaciones (medio día)'), findsNothing);
    await tester.tap(find.text('Ayer'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dia-de-vacaciones')), findsNothing);
    // En el calendario de «Otro día», el 18 sale en ámbar.
    await tester.tap(find.text('Otro día'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'^18 nov: Vacaciones')), findsWidgets);
  });

  testWidgets('Apuntar dice «Vacaciones (medio día)» (012, RF-11)', (
    tester,
  ) async {
    await _open(tester, half: true);
    expect(find.text('Vacaciones (medio día)'), findsOneWidget);
  });

  testWidgets('«Otro día» pinta a medias el medio día (013, RF-12)', (
    tester,
  ) async {
    await _open(tester, half: true);
    await tester.tap(find.text('Otro día'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp(r'^18 nov: Vacaciones, medio día')),
      findsOneWidget,
    );
  });

  testWidgets('un festivo nuevo avisa en Vacaciones sin cambiar de mes '
      '(013, RF-14)', (tester) async {
    calmAnimations(tester);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var data = const HolidayData();
    final holidays = HolidaysController(
      load: () async => data,
      save: (d) async => data = d,
    );
    await holidays.load();
    final vacation = VacationController(
      repository: InMemoryVacationRepository(
        stored: VacationSettings(firstYear: 2025, firstHalfDays: 44),
        days: [VacationDay(DateTime(2026, 11, 18), 2026)],
      ),
      clock: () => _now,
      calendar: () => holidays.calendar,
    );
    await vacation.load();
    await tester.pumpWidget(
      HoursAndVacationApp(
        repository: InMemoryDayEntryRepository(),
        holidays: holidays,
        vacation: vacation,
        clock: () => _now,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vacaciones').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('no es laborable'), findsNothing);
    await holidays.addCustom(
      'Fiesta inventada',
      DateTime(2026, 11, 18),
      yearly: false,
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('El 18 de noviembre no es laborable'),
      findsOneWidget,
    );
  });

  testWidgets('Resumen: «Te quedan» lleva a Vacaciones (RF-18)', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.text('Resumen'));
    await tester.pumpAndSettle();
    expect(find.text('Te quedan 43 días'), findsOneWidget);
    await tester.tap(find.text('Te quedan 43 días'));
    await tester.pumpAndSettle();
    expect(find.text('Por año de vacaciones'), findsOneWidget);
  });

  testWidgets('sin configurar, Resumen no enseña vacaciones', (tester) async {
    await _open(tester, configured: false);
    await tester.tap(find.text('Resumen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Te quedan'), findsNothing);
  });

  for (final width in [360.0, 412.0]) {
    testWidgets('barra y Apuntar sin desbordes a $width px y 130 %', (
      tester,
    ) async {
      await _open(tester, width: width, scale: 1.3);
      expect(tester.takeException(), isNull);
    });
  }
}
