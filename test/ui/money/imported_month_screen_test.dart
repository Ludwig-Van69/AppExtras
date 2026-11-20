import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/imported_month.dart';
import 'package:horas_y_vacaciones/domain/money.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/components/app_nav_bar.dart';
import 'package:horas_y_vacaciones/ui/log/log_controller.dart';
import 'package:horas_y_vacaciones/ui/money/money_controller.dart';

import '../../fakes/in_memory_day_entry_repository.dart';
import '../../fakes/in_memory_money_repository.dart';
import '../test_app.dart';

/// Miércoles 18 de noviembre de 2026. Todos los datos son inventados.
final _now = DateTime(2026, 11, 18, 10);

late InMemoryDayEntryRepository days;

Future<void> _open(
  WidgetTester tester,
  List<ImportedMonth> imported, {
  List<DayEntry> entries = const [],
}) async {
  calmAnimations(tester);
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  days = InMemoryDayEntryRepository(entries);
  final store = InMemoryMoneyRepository()
    ..rateList.addAll([
      Rate(DayKind.normal, DateTime(2020), 1500),
      Rate(DayKind.festive, DateTime(2020), 2000),
    ])
    ..importedList.addAll(imported);
  final money = MoneyController(days: days, money: store, clock: () => _now);
  await money.load();
  await tester.pumpWidget(
    HoursAndVacationApp(repository: days, money: money, clock: () => _now),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMonth(WidgetTester tester, String title) async {
  await tester.tap(
    find.descendant(of: find.byType(AppNavBar), matching: find.text('Resumen')),
  );
  await tester.pumpAndSettle();
  // Los años anteriores salen plegados (018, RF-5): primero se despliega.
  final year = title.split(' ').last;
  final card = find.byKey(ValueKey('año-$year'));
  if (card.evaluate().isNotEmpty) {
    await tester.tap(find.text(year));
    await tester.pumpAndSettle();
  }
  await tester.scrollUntilVisible(
    find.text(title),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('la Hoja de un mes del Excel dice que es un total (016, RF-5)', (
    tester,
  ) async {
    await _open(tester, [ImportedMonth(const YearMonth(2022, 6), 2550, 1470)]);
    await _openMonth(tester, 'Junio 2022');
    expect(find.byKey(const ValueKey('mes-del-excel')), findsOneWidget);
    expect(find.byKey(const ValueKey('dias-ignorados')), findsNothing);
    expect(find.textContaining('Normales · 42,5 h'), findsOneWidget);
    expect(find.textContaining('Festivas · 24,5 h'), findsOneWidget);
  });

  testWidgets('con días y total del Excel, avisa de que los días no cuentan '
      '(016, RF-3)', (tester) async {
    await _open(
      tester,
      [ImportedMonth(const YearMonth(2026, 10), 600, 0)],
      entries: [
        DayEntry(
          date: DateTime(2026, 10, 5),
          minutes: 120,
          kind: DayKind.normal,
        ),
      ],
    );
    await _openMonth(tester, 'Octubre 2026');
    expect(find.byKey(const ValueKey('dias-ignorados')), findsOneWidget);
    expect(find.textContaining('Normales · 10 h'), findsOneWidget);
    expect(find.text('5 de octubre'), findsNothing);
  });

  testWidgets('apuntar en un mes del Excel no guarda y avisa (016, RF-4)', (
    tester,
  ) async {
    await _open(tester, [ImportedMonth(const YearMonth(2026, 11), 600, 0)]);
    final preset = find.bySemanticsLabel('Apuntar 2 horas');
    await tester.tap(preset);
    await tester.pump();
    await tester.tap(preset);
    await tester.pumpAndSettle();
    expect(find.text(importedMonthBlockedMessage), findsOneWidget);
    expect(days.days, isEmpty);
  });
}
