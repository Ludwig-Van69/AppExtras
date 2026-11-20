import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/extras.dart';
import 'package:horas_y_vacaciones/domain/money.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/components/app_nav_bar.dart';
import 'package:horas_y_vacaciones/ui/extras/extras_controller.dart';
import 'package:horas_y_vacaciones/ui/money/money_controller.dart';

import '../../fakes/in_memory_day_entry_repository.dart';
import '../../fakes/in_memory_extras_repository.dart';
import '../../fakes/in_memory_money_repository.dart';
import '../test_app.dart';

/// Lunes 16 de noviembre de 2026. Todos los datos son inventados.
final _now = DateTime(2026, 11, 16, 10);

late InMemoryExtrasRepository extrasRepo;
late ExtrasController extras;
late MoneyController money;

/// 38 h normales a 15 €/h = 570 €; un extra de 50 € y una multa de 100 €,
/// pendientes.
Future<void> _open(WidgetTester tester, {double width = 390}) async {
  calmAnimations(tester);
  await tester.binding.setSurfaceSize(Size(width, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final days = InMemoryDayEntryRepository([
    for (var d = 2; d <= 20; d++)
      DayEntry(date: DateTime(2026, 10, d), minutes: 120, kind: DayKind.normal),
  ]);
  final store = InMemoryMoneyRepository()
    ..rateList.addAll([
      Rate(DayKind.normal, DateTime(2020), 1500),
      Rate(DayKind.festive, DateTime(2020), 2000),
    ]);
  money = MoneyController(days: days, money: store, clock: () => _now);
  await money.load();
  extrasRepo = InMemoryExtrasRepository([
    ExtraItem(
      id: 1,
      type: ExtraType.bonus,
      date: DateTime(2026, 11, 2),
      cents: 5000,
      concept: 'Dieta viaje',
    ),
    ExtraItem(
      id: 2,
      type: ExtraType.fine,
      date: DateTime(2026, 11, 3),
      cents: 10000,
      concept: 'Multa velocidad',
    ),
  ]);
  extras = ExtrasController(repository: extrasRepo, clock: () => _now);
  await extras.load();
  await tester.pumpWidget(
    HoursAndVacationApp(
      repository: days,
      money: money,
      extras: extras,
      clock: () => _now,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Resumen'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('barra: Apuntar, Resumen y Extra; Ajustes no es una sección '
      '(RF-1, RF-12, RF-16)', (tester) async {
    await _open(tester);
    final bar = find.byType(AppNavBar);
    for (final s in ['Apuntar', 'Resumen', 'Extra']) {
      expect(find.descendant(of: bar, matching: find.text(s)), findsOneWidget);
    }
    expect(
      find.descendant(of: bar, matching: find.text('Ajustes')),
      findsNothing,
    );
    expect(find.text('Dinero'), findsNothing);
  });

  testWidgets('«Con multas y extras» va aparte: 570 + 50 − 100 = 520 (RF-9, '
      'RF-10)', (tester) async {
    await _open(tester);
    expect(find.text('A cobrar'), findsOneWidget);
    expect(find.text('570,00 €'), findsWidgets);
    expect(find.text('Con multas y extras'), findsOneWidget);
    expect(find.text('520,00 €'), findsOneWidget);
    expect(find.textContaining('Posible'), findsNothing); // 009, RF-5

    // Anular la multa sube el total aparte; las horas no cambian.
    await extras.save(extrasRepo.byId[2]!.withStatus(ExtraStatus.cancelled));
    await tester.pumpAndSettle();
    expect(find.text('620,00 €'), findsOneWidget);
    expect(money.overview.toCollectCents, 57000);

    await tester.tap(find.byTooltip('Más información: Con multas y extras'));
    await tester.pumpAndSettle();
    expect(find.textContaining('más los extras pendientes'), findsOneWidget);
  });

  testWidgets('puede salir negativo y se oculta con el ojo', (tester) async {
    await _open(tester);
    await extras.save(
      ExtraItem(
        type: ExtraType.fine,
        date: DateTime(2026, 11, 4),
        cents: 100000,
        concept: 'Multa grave',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('-480,00 €'), findsOneWidget); // 570 + 50 − 100 − 1000
    await tester.tap(find.byTooltip('Ocultar importes').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('480'), findsNothing);
  });

  testWidgets('tocar el total aparte abre Extra (RF-11)', (tester) async {
    await _open(tester);
    await tester.tap(find.text('520,00 €'));
    await tester.pumpAndSettle();
    expect(find.text('Multas y extras'), findsOneWidget);
    expect(find.text('Multa velocidad'), findsOneWidget);
  });

  testWidgets('el engranaje abre Ajustes desde Resumen y desde Extra '
      '(RF-16)', (tester) async {
    await _open(tester);
    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('Tarifas'), findsOneWidget);
    await tester.tap(find.byTooltip('Atrás'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Extra'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('Tarifas'), findsOneWidget);
  });

  for (final width in [360.0, 412.0]) {
    testWidgets('Resumen cabe a ${width.toInt()} px con letra al 130 %', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await _open(tester, width: width);
      expect(tester.takeException(), isNull);
    });
  }
}
