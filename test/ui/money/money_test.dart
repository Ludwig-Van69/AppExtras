import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/money.dart';
import 'package:horas_y_vacaciones/domain/saved_hours.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/format.dart';
import 'package:horas_y_vacaciones/ui/money/money_controller.dart';

import '../../fakes/in_memory_day_entry_repository.dart';
import '../../fakes/in_memory_money_repository.dart';
import '../../fakes/in_memory_saved_hours_repository.dart';
import '../test_app.dart';

/// Viernes 6 de noviembre de 2026. Todos los datos son inventados.
final _now = DateTime(2026, 11, 6, 18);

DayEntry _e(int m, int d, int minutes, [DayKind k = DayKind.normal]) =>
    DayEntry(date: DateTime(2026, m, d), minutes: minutes, kind: k);

late InMemoryDayEntryRepository days;
late InMemoryMoneyRepository store;
late MoneyController money;
var hidden = false;

Future<void> _setup([List<DayEntry> entries = const []]) async {
  days = InMemoryDayEntryRepository(entries);
  store = InMemoryMoneyRepository();
  hidden = false;
  money = MoneyController(
    days: days,
    money: store,
    clock: () => _now,
    loadHidden: () async => hidden,
    saveHidden: (v) async => hidden = v,
  );
  await money.load();
}

void _rates({int normal = 1500, int festive = 2000}) {
  store.rateList
    ..clear()
    ..addAll([
      Rate(DayKind.normal, DateTime(2020), normal),
      Rate(DayKind.festive, DateTime(2020), festive),
    ]);
}

Future<void> _open(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
}) async {
  calmAnimations(tester);
  await tester.binding.setSurfaceSize(Size(width, 800));
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.platformDispatcher.clearAllTestValues();
  });
  await tester.pumpWidget(
    HoursAndVacationApp(repository: days, money: money, clock: () => _now),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Resumen'));
  await tester.pumpAndSettle();
}

void main() {
  group('controlador', () {
    test('calcula «A cobrar» con las tarifas y los meses', () async {
      await _setup([
        _e(10, 5, 120),
        _e(11, 3, 60),
        _e(11, 7, 60, DayKind.festive),
      ]);
      _rates();
      await money.load();
      expect(money.overview.toCollectCents, 3000 + 1500 + 2000);
      expect(money.hasRates, isTrue);
    });

    test('Entregado, Cobrado y de vuelta a Abierto', () async {
      await _setup([_e(10, 5, 120)]);
      _rates();
      await money.load();
      const oct = YearMonth(2026, 10);

      await money.setStatus(
        oct,
        MonthStatus.delivered,
        date: DateTime(2026, 11, 2),
      );
      expect(money.overview.months.single.status, MonthStatus.delivered);
      expect(money.overview.toCollectCents, 3000);

      await money.setStatus(
        oct,
        MonthStatus.paid,
        date: DateTime(2026, 11, 30),
      );
      final paid = money.overview.months.single.record!;
      expect(paid.deliveredOn, DateTime(2026, 11, 2)); // se conserva la entrega
      expect(paid.paidOn, DateTime(2026, 11, 30));
      expect(money.overview.toCollectCents, 0);

      await money.setStatus(oct, MonthStatus.delivered); // quitar el cobro
      expect(money.overview.months.single.record!.paidOn, isNull);
      expect(
        money.overview.months.single.record!.deliveredOn,
        DateTime(2026, 11, 2),
      );

      await money.setStatus(oct, MonthStatus.open);
      expect(money.overview.months.single.record, isNull);
    });

    test('cobrar directamente un mes abierto lo da por entregado', () async {
      await _setup([_e(10, 5, 60)]);
      _rates();
      await money.load();
      await money.setStatus(
        const YearMonth(2026, 10),
        MonthStatus.paid,
        date: DateTime(2026, 11, 3),
      );
      final r = money.overview.months.single.record!;
      expect(r.status, MonthStatus.paid);
      expect(r.deliveredOn, DateTime(2026, 11, 3));
    });

    test('cobrar varios meses a la vez (RF-9)', () async {
      await _setup([_e(8, 5, 60), _e(9, 5, 60), _e(10, 5, 60)]);
      _rates();
      await money.load();
      await money.markPaid([
        const YearMonth(2026, 8),
        const YearMonth(2026, 9),
      ], DateTime(2026, 11, 4));
      expect(money.overview.toCollectCents, 1500);
      expect(
        money.overview.months.where((m) => m.status == MonthStatus.paid).length,
        2,
      );
    });

    test('una tarifa nueva no cambia los meses anteriores', () async {
      await _setup([_e(10, 5, 60), _e(11, 3, 60)]);
      _rates();
      await money.load();
      await money.saveRate(DayKind.normal, 1800, DateTime(2026, 11, 1));
      final oct = money.overview.months.firstWhere((m) => m.month.month == 10);
      final nov = money.overview.months.firstWhere((m) => m.month.month == 11);
      expect(oct.amountCents, 1500);
      expect(nov.amountCents, 1800);
    });

    test('borrar una tarifa', () async {
      await _setup([_e(11, 3, 60)]);
      _rates();
      await money.load();
      await money.deleteRate(
        money.rates.firstWhere((r) => r.kind == DayKind.normal),
      );
      expect(money.hasRates, isFalse);
      expect(money.overview.months.single.isComplete, isFalse);
    });

    test(
      'al guardar un día nuevo, refresh actualiza los importes (RF-12)',
      () async {
        await _setup([_e(11, 3, 60)]);
        _rates();
        await money.load();
        days.days['2026-11-04'] = _e(11, 4, 60);
        await money.refresh();
        expect(money.overview.toCollectCents, 3000);
      },
    );

    test('si falla un guardado, se avisa y no se cambia nada', () async {
      await _setup([_e(10, 5, 60)]);
      _rates();
      await money.load();
      store.failWrites = true;
      await money.setStatus(const YearMonth(2026, 10), MonthStatus.delivered);
      expect(money.saveFailed, isTrue);
      expect(money.overview.months.single.status, MonthStatus.open);
    });

    test('si falla la lectura queda en error y se puede reintentar', () async {
      await _setup([_e(10, 5, 60)]);
      days.failReads = true;
      await money.load();
      expect(money.status, MoneyStatus.error);
      days.failReads = false;
      await money.load();
      expect(money.status, MoneyStatus.ready);
    });

    test('ocultar importes se recuerda', () async {
      await _setup();
      await money.toggleHideAmounts();
      expect(money.hideAmounts, isTrue);
      expect(hidden, isTrue);
    });
  });

  group('parseEuros', () {
    test('formatos válidos', () {
      expect(parseEuros('15'), 1500);
      expect(parseEuros('15,5'), 1550);
      expect(parseEuros('15.50'), 1550);
      expect(parseEuros(' 15,05 € '), 1505);
      expect(parseEuros('0,01'), 1);
    });

    test('formatos no válidos', () {
      for (final bad in [
        '',
        'abc',
        '15,555',
        '1.234,50',
        '-5',
        '15,',
        ',5',
        '1e3',
      ]) {
        expect(parseEuros(bad), isNull, reason: bad);
      }
    });
  });

  group('pantalla Dinero', () {
    testWidgets('sin tarifas pide ponerlas; con tarifas enseña los totales', (
      tester,
    ) async {
      await _setup([_e(10, 5, 120), _e(11, 3, 60)]);
      await _open(tester);
      expect(
        find.text('Pon tus tarifas para ver los importes.'),
        findsOneWidget,
      );
      expect(find.text('Poner tarifas'), findsOneWidget);
    });

    testWidgets(
      'A cobrar y lista de meses con estado y aviso de sin entregar',
      (tester) async {
        await _setup([_e(9, 5, 60), _e(10, 5, 120), _e(11, 3, 60)]);
        _rates();
        await money.load();
        await _open(tester);
        expect(find.text('A cobrar'), findsOneWidget);
        // 4 h a 15 €, juntas en la cabecera (018, RF-1).
        expect(find.text('4 h = 60,00 €'), findsOneWidget);
        // Su cuenta, también en el total (018, RF-1).
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('desglose-cobrar')),
            matching: find.text('Normales · 4 h × 15,00 €'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('entregado-sin-cobrar')),
          findsNothing,
        );
        expect(find.text('Noviembre 2026'), findsOneWidget);
        expect(find.text('Llevas 2 meses sin entregar'), findsOneWidget);
      },
    );

    testWidgets('estados con etiqueta, total entregado y aviso (006)', (
      tester,
    ) async {
      await _setup([_e(8, 5, 60), _e(9, 5, 60), _e(10, 5, 120)]);
      _rates();
      store.monthMap[const YearMonth(2026, 8)] = MonthRecord(
        const YearMonth(2026, 8),
        paidOn: DateTime(2026, 9, 30),
      );
      store.monthMap[const YearMonth(2026, 9)] = MonthRecord(
        const YearMonth(2026, 9),
        deliveredOn: DateTime(2026, 10, 2),
      );
      await money.load();
      await _open(tester);
      // Recuadro con la cuenta de lo entregado (018, RF-2).
      final box = find.byKey(const ValueKey('entregado-sin-cobrar'));
      expect(box, findsOneWidget);
      expect(
        find.descendant(of: box, matching: find.text('15,00 €')),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: box,
          matching: find.text('Normales · 1 h × 15,00 €'),
        ),
        findsOneWidget,
      );
      expect(find.text('1 mes entregado sin cobrar.'), findsOneWidget);
      expect(find.text('Llevas 1 mes sin entregar'), findsOneWidget);
      for (final s in ['Abierto', 'Entregado', 'Cobrado']) {
        expect(find.byKey(ValueKey('estado-$s')), findsOneWidget);
      }
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(find.byIcon(Icons.outgoing_mail), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      await tester.tap(find.byTooltip('Ocultar importes'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: box,
          matching: find.text('Normales · 1 h × •••• €'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('15,00'), findsNothing);
    });

    testWidgets('años anteriores plegados con su resumen (018, RF-5)', (
      tester,
    ) async {
      await _setup([
        _e(10, 5, 120),
        DayEntry(date: DateTime(2025, 3, 4), minutes: 60, kind: DayKind.normal),
        DayEntry(
          date: DateTime(2025, 6, 4),
          minutes: 120,
          kind: DayKind.normal,
        ),
        DayEntry(date: DateTime(2024, 6, 4), minutes: 60, kind: DayKind.normal),
      ]);
      _rates();
      store.monthMap[const YearMonth(2025, 3)] = MonthRecord(
        const YearMonth(2025, 3),
        paidOn: DateTime(2025, 4, 30),
      );
      store.monthMap[const YearMonth(2024, 6)] = MonthRecord(
        const YearMonth(2024, 6),
        paidOn: DateTime(2024, 7, 30),
      );
      await money.load();
      await _open(tester);
      // El año en curso, desplegado; los anteriores, plegados.
      expect(find.text('Octubre 2026'), findsOneWidget);
      expect(find.text('Marzo 2025'), findsNothing);
      expect(find.text('3 h · 45,00 €'), findsOneWidget);
      expect(find.byKey(const ValueKey('estado-año-2025')), findsOneWidget);
      expect(find.text('1 mes sin cobrar'), findsOneWidget);
      expect(find.text('Todo cobrado'), findsOneWidget);

      await tester.tap(find.text('2025'));
      await tester.pumpAndSettle();
      expect(find.text('Marzo 2025'), findsOneWidget);
      expect(find.text('Junio 2025'), findsOneWidget);
      expect(find.text('Junio 2024'), findsNothing);

      await tester.tap(find.text('2025'));
      await tester.pumpAndSettle();
      expect(find.text('Marzo 2025'), findsNothing);
    });

    testWidgets('ocultar importes tapa todos los euros (RF-11)', (
      tester,
    ) async {
      await _setup([_e(10, 5, 120)]);
      _rates();
      await money.load();
      await _open(tester);
      expect(find.text('30,00 €'), findsWidgets);
      await tester.tap(find.byTooltip('Ocultar importes'));
      await tester.pumpAndSettle();
      expect(find.text('30,00 €'), findsNothing);
      expect(find.text('•••• €'), findsWidgets);
      expect(find.byTooltip('Mostrar importes'), findsOneWidget);
    });

    testWidgets('Hoja del mes: importes, días y cambio de estado (RF-8)', (
      tester,
    ) async {
      await _setup([_e(10, 5, 120), _e(10, 10, 60, DayKind.festive)]);
      _rates();
      await money.load();
      await _open(tester);
      await tester.tap(find.text('Octubre 2026'));
      await tester.pumpAndSettle();
      expect(find.text('50,00 €'), findsWidgets); // 30 + 20
      expect(find.text('Normales · 2 h'), findsOneWidget);
      expect(find.text('Festivas · 1 h'), findsOneWidget);
      expect(find.textContaining('5 de octubre'), findsOneWidget);

      await tester.tap(find.text('Entregado'));
      await tester.pumpAndSettle();
      expect(money.overview.months.single.status, MonthStatus.delivered);
      expect(find.textContaining('Entregado el 6 nov'), findsOneWidget);
    });

    testWidgets('cobrar varios meses de una vez (RF-9)', (tester) async {
      await _setup([_e(8, 5, 60), _e(9, 5, 60), _e(10, 5, 60)]);
      _rates();
      await money.load();
      await _open(tester);
      await tester.tap(find.text('Cobrar varios meses'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Marcar como cobrados'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Agosto 2026'));
      await tester.tap(find.text('Septiembre 2026'));
      await tester.pumpAndSettle();
      expect(find.text('Total seleccionado: 30,00 €'), findsOneWidget);
      await tester.tap(find.text('Marcar como cobrados'));
      await tester.pumpAndSettle();
      expect(find.text('2 meses marcados como cobrados.'), findsOneWidget);
      expect(money.overview.toCollectCents, 1500);
    });

    testWidgets('sin horas apuntadas lo dice', (tester) async {
      await _setup();
      await _open(tester);
      expect(find.text('Aún no hay horas apuntadas.'), findsOneWidget);
    });

    testWidgets('si no se pueden leer los datos, error con Reintentar', (
      tester,
    ) async {
      await _setup([_e(10, 5, 60)]);
      days.failReads = true;
      await money.load();
      await _open(tester);
      expect(find.text('No se puede calcular el dinero'), findsOneWidget);
      days.failReads = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('A cobrar'), findsOneWidget);
    });

    for (final width in [360.0, 412.0]) {
      testWidgets('cabe a ${width.toInt()} px con letra al 130 %', (
        tester,
      ) async {
        await _setup([for (var m = 1; m <= 10; m++) _e(m, 5, 1290)]);
        _rates(normal: 99999);
        // Meses entregados: el recuadro del desglose con cifras enormes.
        for (var m = 1; m <= 9; m++) {
          store.monthMap[YearMonth(2026, m)] = MonthRecord(
            YearMonth(2026, m),
            deliveredOn: DateTime(2026, 10, 2),
          );
        }
        await money.load();
        await _open(tester, width: width, scale: 1.3);
        expect(
          find.byKey(const ValueKey('entregado-sin-cobrar')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Octubre 2026'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Octubre 2026'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('tarifas (Ajustes)', () {
    Future<void> openRates(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Ajustes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tarifas'));
      await tester.pumpAndSettle();
    }

    testWidgets('poner la primera tarifa: desde 2020, con su fecha a la vista '
        '(RF-1, RF-2; 021, RF-1)', (tester) async {
      await _setup([_e(10, 5, 60)]);
      await _open(tester);
      await openRates(tester);
      expect(find.text('Sin tarifa'), findsNWidgets(2));
      await tester.tap(find.text('Poner tarifa Normal'));
      await tester.pumpAndSettle();
      expect(find.text('Desde el 1 ene 2020'), findsOneWidget);
      // Sin importe válido no se puede guardar.
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '15,5');
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('15,50 € / hora'), findsWidgets);
      expect(store.rateList.single.cents, 1550);
      expect(store.rateList.single.start, DateTime(2020));
    });

    testWidgets('un importe mal escrito da error', (tester) async {
      await _setup();
      await _open(tester);
      await openRates(tester);
      await tester.tap(find.text('Poner tarifa Festiva'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '15,555');
      await tester.pump();
      expect(find.textContaining('Escribe un importe'), findsOneWidget);
    });

    Future<void> withSetAside(DateTime date) async {
      final saved = InMemorySavedHoursRepository([
        SavedMove(
          box: SavedBox.own,
          kind: SavedMoveKind.setAside,
          date: date,
          minutes: 120,
        ),
      ]);
      money = MoneyController(
        days: days,
        money: store,
        saved: saved,
        clock: () => _now,
        loadHidden: () async => hidden,
        saveHidden: (v) async => hidden = v,
      );
      await money.load();
    }

    /// Datos inventados: 15 € desde 2021 y 16,50 € desde julio de 2026.
    void periods() => store.rateList
      ..clear()
      ..addAll([
        Rate(DayKind.normal, DateTime(2021), 1500),
        Rate(DayKind.normal, DateTime(2026, 7), 1650),
        Rate(DayKind.festive, DateTime(2021), 2000),
      ]);

    Future<void> openCard(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(ValueKey('tarifa-$key')));
      await tester.pumpAndSettle();
    }

    Future<void> pickDay(WidgetTester tester, String day) async {
      await tester.tap(find.byKey(const ValueKey('fecha-tarifa')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(day));
      await tester.tap(find.text('ACEPTAR'));
      await tester.pumpAndSettle();
    }

    testWidgets('cada tarifa sale con su periodo (021, RF-1, RF-2)', (
      tester,
    ) async {
      await _setup();
      periods();
      await money.load();
      await _open(tester);
      await openRates(tester);
      expect(find.text('desde el 1 jul 2026 · hasta hoy'), findsOneWidget);
      expect(find.text('del 1 ene 2021 al 30 jun 2026'), findsOneWidget);
      expect(find.text('desde el 1 ene 2021 · hasta hoy'), findsOneWidget);
      expect(find.text('Añadir tarifa nueva'), findsWidgets);
      expect(find.text('Desde siempre'), findsNothing);
    });

    testWidgets('cambiar el importe cambia los meses (021, RF-3)', (
      tester,
    ) async {
      await _setup([_e(10, 5, 60)]);
      periods();
      await money.load();
      await _open(tester);
      await openRates(tester);
      await openCard(tester, 'normal-2026-07-01');
      expect(find.text('Tarifa normal'), findsOneWidget);
      expect(find.text('16,50'), findsOneWidget);
      expect(
        find.text('La de 15,00 €/h terminará el 30 jun 2026.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '17');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(
        store.rateList
            .where((r) => r.kind == DayKind.normal)
            .map((r) => r.cents),
        unorderedEquals([1500, 1700]),
      );
      expect(money.overview.months.single.amountCents, 1700);
    });

    testWidgets('mover el inicio alarga la anterior (021, RF-3, RF-4)', (
      tester,
    ) async {
      await _setup();
      periods();
      await money.load();
      await _open(tester);
      await openRates(tester);
      await openCard(tester, 'normal-2026-07-01');
      await pickDay(tester, '15');
      expect(find.text('Desde el 15 jul 2026'), findsOneWidget);
      expect(
        find.text('La de 15,00 €/h terminará el 14 jul 2026.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('del 1 ene 2021 al 14 jul 2026'), findsOneWidget);
      expect(
        store.rateList
            .where((r) => r.kind == DayKind.normal)
            .map((r) => r.start),
        unorderedEquals([DateTime(2021), DateTime(2026, 7, 15)]),
      );
    });

    testWidgets('una tarifa nueva avisa de cómo acaba la anterior y no deja '
        'repetir el día de inicio (021, RF-4, RF-5)', (tester) async {
      await _setup();
      store.rateList.addAll([
        Rate(DayKind.normal, DateTime(2021), 1500),
        Rate(DayKind.normal, DateTime(2026, 11), 1650),
      ]);
      await money.load();
      await _open(tester);
      await openRates(tester);
      await tester.tap(find.byKey(const ValueKey('añadir-normal')));
      await tester.pumpAndSettle();
      expect(find.text('Tarifa normal nueva'), findsOneWidget);
      expect(
        find.text('La de 16,50 €/h terminará el 5 nov 2026.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '18');
      await pickDay(tester, '1');
      expect(
        find.text('Ya hay una tarifa que empieza ese día'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar'))
            .onPressed,
        isNull,
      );
      expect(store.rateList, hasLength(2));
    });

    testWidgets('no deja mover el inicio si un apartado se queda sin precio '
        '(021, RF-6)', (tester) async {
      await _setup();
      store.rateList.add(Rate(DayKind.normal, DateTime(2026), 1500));
      await withSetAside(DateTime(2026, 1, 5));
      await _open(tester);
      await openRates(tester);
      await openCard(tester, 'normal-2026-01-01');
      await pickDay(tester, '10');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('No se puede guardar'), findsOneWidget);
      expect(find.textContaining('5 de enero de 2026'), findsOneWidget);
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(store.rateList.single.start, DateTime(2026));
    });

    testWidgets('borrar una tarifa desde su ficha pide confirmación', (
      tester,
    ) async {
      await _setup();
      _rates();
      await money.load();
      await _open(tester);
      await openRates(tester);
      await openCard(tester, 'normal-2020-01-01');
      await tester.tap(find.text('Borrar'));
      await tester.pumpAndSettle();
      expect(find.text('Borrar tarifa'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(store.rateList.length, 2);
      await openCard(tester, 'normal-2020-01-01');
      await tester.tap(find.text('Borrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Borrar'));
      await tester.pumpAndSettle();
      expect(store.rateList.length, 1);
    });

    testWidgets('no deja borrar la tarifa que pone precio a un apartado '
        '(013, RF-15)', (tester) async {
      await _setup([_e(10, 5, 300)]);
      _rates();
      await withSetAside(DateTime(2026, 10, 5));
      await _open(tester);
      await openRates(tester);
      await openCard(tester, 'normal-2020-01-01');
      await tester.tap(find.text('Borrar'));
      await tester.pumpAndSettle();
      expect(find.text('No se puede borrar'), findsOneWidget);
      expect(find.textContaining('5 de octubre de 2026'), findsOneWidget);
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(store.rateList.length, 2);
    });

    testWidgets('sin desbordes a 360 px con letra al 130 % (021)', (
      tester,
    ) async {
      await _setup();
      periods();
      await money.load();
      await _open(tester, width: 360, scale: 1.3);
      await openRates(tester);
      expect(tester.takeException(), isNull);
      await openCard(tester, 'normal-2026-07-01');
      expect(tester.takeException(), isNull);
    });
  });
}
