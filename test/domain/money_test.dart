import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/money.dart';
import 'package:horas_y_vacaciones/domain/saved_hours.dart';

DayEntry day(int y, int m, int d, int minutes, [DayKind k = DayKind.normal]) =>
    DayEntry(date: DateTime(y, m, d), minutes: minutes, kind: k);

Rate rate(DayKind k, int y, int m, int d, int cents) =>
    Rate(k, DateTime(y, m, d), cents);

void main() {
  group('tarifa de un día', () {
    final rates = [
      rate(DayKind.normal, 2020, 1, 1, 1500),
      rate(DayKind.normal, 2026, 11, 1, 1600),
      rate(DayKind.festive, 2020, 1, 1, 2000),
    ];

    test('la más reciente que ya había empezado', () {
      expect(
        rateFor(DayKind.normal, DateTime(2026, 10, 31), rates)!.cents,
        1500,
      );
      expect(
        rateFor(DayKind.normal, DateTime(2026, 11, 1), rates)!.cents,
        1600,
      );
      expect(rateFor(DayKind.normal, DateTime(2030, 1, 1), rates)!.cents, 1600);
    });

    test('cada tipo con la suya', () {
      expect(
        rateFor(DayKind.festive, DateTime(2026, 11, 1), rates)!.cents,
        2000,
      );
    });

    test('antes de la primera no hay tarifa', () {
      expect(rateFor(DayKind.normal, DateTime(2019, 12, 31), rates), isNull);
      expect(rateFor(DayKind.festive, DateTime(2026, 1, 1), const []), isNull);
    });

    test('una tarifa fuera de rango da error', () {
      expect(() => rate(DayKind.normal, 2026, 1, 1, 0), throwsArgumentError);
      expect(
        () => rate(DayKind.normal, 2026, 1, 1, maxRateCents + 1),
        throwsArgumentError,
      );
    });
  });

  group('importes', () {
    test('mitades hacia arriba', () {
      expect(amountCents(150, 1500), 3750); // 2,5 h × 15 €
      expect(amountCents(1, 100), 2); // 1,67 céntimos → 2
      expect(amountCents(30, 1), 1); // 0,5 céntimos → 1
      expect(amountCents(29, 1), 0);
    });

    test('un mes se redondea una sola vez', () {
      // Tres días de 20 min a 0,10 €/h: cada uno 0,33 → 0; juntos 1 h = 10 c.
      final month = MoneyOverview.compute(
        entries: [
          day(2026, 11, 2, 20),
          day(2026, 11, 3, 20),
          day(2026, 11, 4, 20),
        ],
        rates: [rate(DayKind.normal, 2020, 1, 1, 10)],
        records: const [],
      ).months.single;
      expect(month.amountCents, 10);
    });

    test('38 horas a 15 €/h son 570 €', () {
      final o = MoneyOverview.compute(
        entries: [for (var d = 1; d <= 19; d++) day(2026, 10, d, 120)],
        rates: [rate(DayKind.normal, 2020, 1, 1, 1500)],
        records: const [],
      );
      expect(o.toCollectCents, 57000);
      expect(o.toCollectMinutes, 38 * 60);
    });

    test('dos tarifas en el mismo mes, cada día con la suya', () {
      final month = MoneyOverview.compute(
        entries: [
          day(2026, 11, 2, 60), // 15 €
          day(2026, 11, 20, 60), // 16 €
          day(2026, 11, 21, 60, DayKind.festive), // 20 €
        ],
        rates: [
          rate(DayKind.normal, 2020, 1, 1, 1500),
          rate(DayKind.normal, 2026, 11, 10, 1600),
          rate(DayKind.festive, 2020, 1, 1, 2000),
        ],
        records: const [],
      ).months.single;
      expect(month.amountCents, 5100);
      expect(month.amountOf(DayKind.normal), 3100);
      expect(month.amountOf(DayKind.festive), 2000);
      expect(month.minutesOf(DayKind.normal), 120);
      expect(month.minutes, 180);
    });

    test('un día sin tarifa no se cuenta y se avisa', () {
      final o = MoneyOverview.compute(
        entries: [day(2026, 11, 2, 60), day(2026, 11, 3, 120, DayKind.festive)],
        rates: [rate(DayKind.normal, 2020, 1, 1, 1500)],
        records: const [],
      );
      final m = o.months.single;
      expect(m.amountCents, 1500);
      expect(m.unpricedMinutes, 120);
      expect(m.isComplete, isFalse);
      expect(o.hasUnpriced, isTrue);
    });

    test('cambiar una tarifa no cambia el pasado', () {
      final entries = [day(2026, 10, 5, 60)];
      final before = MoneyOverview.compute(
        entries: entries,
        rates: [rate(DayKind.normal, 2020, 1, 1, 1500)],
        records: const [],
      );
      final after = MoneyOverview.compute(
        entries: entries,
        rates: [
          rate(DayKind.normal, 2020, 1, 1, 1500),
          rate(DayKind.normal, 2026, 11, 1, 1800),
        ],
        records: const [],
      );
      expect(after.toCollectCents, before.toCollectCents);
    });
  });

  group('meses', () {
    final entries = [
      day(2026, 9, 5, 60),
      day(2026, 10, 5, 120),
      day(2026, 11, 5, 180),
    ];
    final rates = [rate(DayKind.normal, 2020, 1, 1, 1000)];

    test('del más reciente al más antiguo, sin meses vacíos', () {
      final o = MoneyOverview.compute(
        entries: entries,
        rates: rates,
        records: const [],
      );
      expect(o.months.map((m) => m.month.key), [
        '2026-11',
        '2026-10',
        '2026-09',
      ]);
    });

    test('«A cobrar» deja fuera los meses cobrados', () {
      final o = MoneyOverview.compute(
        entries: entries,
        rates: rates,
        records: [
          MonthRecord(const YearMonth(2026, 9), paidOn: DateTime(2026, 10, 20)),
          MonthRecord(
            const YearMonth(2026, 10),
            deliveredOn: DateTime(2026, 11, 2),
          ),
        ],
      );
      expect(o.toCollectCents, 2000 + 3000); // octubre (entregado) + noviembre
      expect(o.toCollectMinutes, 300);
    });

    test(
      'entregado: parte de «A cobrar» y meses entregados sin cobrar (006)',
      () {
        final o = MoneyOverview.compute(
          entries: entries,
          rates: rates,
          records: [
            MonthRecord(
              const YearMonth(2026, 9),
              paidOn: DateTime(2026, 10, 20),
            ),
            MonthRecord(
              const YearMonth(2026, 10),
              deliveredOn: DateTime(2026, 11, 2),
            ),
          ],
        );
        expect(o.deliveredCents, 2000); // solo octubre
        expect(o.deliveredMinutes, 120);
        expect(o.deliveredUnpaid.map((m) => m.month.key), ['2026-10']);
        // Lo entregado es parte del total, no se suma aparte.
        expect(o.toCollectCents - o.deliveredCents, 3000); // noviembre, abierto
      },
    );

    test('cobrado implica entregado', () {
      final r = MonthRecord(
        const YearMonth(2026, 9),
        paidOn: DateTime(2026, 10, 20, 15),
      );
      expect(r.status, MonthStatus.paid);
      expect(r.deliveredOn, DateTime(2026, 10, 20));
      expect(MonthRecord(const YearMonth(2026, 9)).status, MonthStatus.open);
    });

    test('meses terminados sin entregar', () {
      final o = MoneyOverview.compute(
        entries: entries,
        rates: rates,
        records: [
          MonthRecord(
            const YearMonth(2026, 9),
            deliveredOn: DateTime(2026, 10, 3),
          ),
        ],
      );
      final late = o.unsubmittedBefore(DateTime(2026, 11, 12));
      expect(late.map((m) => m.month.key), [
        '2026-10',
      ]); // noviembre aún es el actual
    });
  });

  group('YearMonth', () {
    test('clave y lectura', () {
      expect(const YearMonth(2026, 3).key, '2026-03');
      expect(YearMonth.parse('2026-03'), const YearMonth(2026, 3));
      expect(() => YearMonth.parse('2026-13'), throwsFormatException);
      expect(() => YearMonth.parse('26-1'), throwsFormatException);
    });

    test('orden', () {
      expect(
        const YearMonth(2025, 12).compareTo(const YearMonth(2026, 1)),
        lessThan(0),
      );
    });
  });

  group('horas apartadas (008)', () {
    final rates = [
      rate(DayKind.normal, 2020, 1, 1, 1500),
      rate(DayKind.festive, 2020, 1, 1, 2000),
    ];
    SavedMove apart(int d, int hours, [int m = 11]) => SavedMove(
      box: SavedBox.own,
      kind: SavedMoveKind.setAside,
      date: DateTime(2026, m, d),
      minutes: hours * 60,
    );
    final nov = [day(2026, 11, 3, 300), day(2026, 11, 4, 300)];

    test('10 h a 15 € menos 3 apartadas: 7 h y 105 € (RF-5)', () {
      final o = MoneyOverview.compute(
        entries: nov,
        rates: rates,
        records: const [],
        savedMoves: [apart(10, 3)],
      );
      final line = o.months.single;
      expect(line.minutes, 420);
      expect(line.amountCents, 10500);
      expect(line.setAsideMinutes, 180);
      expect(line.setAsideCents, 4500);
      expect(line.minutesOf(DayKind.normal), 600);
      expect(o.toCollectMinutes, 420);
      expect(o.toCollectCents, 10500);
    });

    test('se resta a la tarifa de su fecha y se redondea una vez (RF-6)', () {
      final two = [...rates, rate(DayKind.normal, 2026, 11, 15, 1525)];
      final o = MoneyOverview.compute(
        entries: [day(2026, 11, 3, 300), day(2026, 11, 20, 90)],
        rates: two,
        records: const [],
        savedMoves: [
          SavedMove(
            box: SavedBox.company,
            kind: SavedMoveKind.setAside,
            date: DateTime(2026, 11, 20),
            minutes: 30,
          ),
        ],
      );
      // 5 h × 15 + 1,5 h × 15,25 − 0,5 h × 15,25 = 75 + 15,25 = 90,25 €.
      expect(o.months.single.amountCents, 9025);
    });

    test('las cuentas de otros movimientos no tocan los meses', () {
      final o = MoneyOverview.compute(
        entries: nov,
        rates: rates,
        records: const [],
        savedMoves: [
          SavedMove(
            box: SavedBox.own,
            kind: SavedMoveKind.before,
            date: DateTime(2026, 11, 2),
            minutes: 600,
          ),
        ],
      );
      expect(o.toCollectCents, 15000);
    });

    test('un mes cobrado con apartados no suma a «A cobrar»', () {
      final o = MoneyOverview.compute(
        entries: nov,
        rates: rates,
        records: [
          MonthRecord(const YearMonth(2026, 11), paidOn: DateTime(2026, 12, 1)),
        ],
        savedMoves: [apart(10, 3)],
      );
      expect(o.toCollectCents, 0);
    });

    group('se puede apartar (RF-6, RF-7)', () {
      MonthLine line({
        List<DayEntry>? entries,
        List<SavedMove> moves = const [],
        MonthRecord? record,
      }) => MoneyOverview.compute(
        entries: entries ?? nov,
        rates: rates,
        records: [?record],
        savedMoves: moves,
      ).months.single;

      test('hasta las horas normales sin apartar', () {
        expect(checkSetAside(apart(10, 10), line(), rates), isNull);
        expect(
          checkSetAside(apart(10, 8), line(moves: [apart(5, 3)]), rates),
          SetAsideProblem.tooMany,
        );
        expect(
          checkSetAside(apart(10, 7), line(moves: [apart(5, 3)]), rates),
          isNull,
        );
      });

      test('las festivas no se pueden apartar', () {
        final l = line(
          entries: [
            day(2026, 11, 3, 120),
            day(2026, 11, 7, 600, DayKind.festive),
          ],
        );
        expect(checkSetAside(apart(10, 3), l, rates), SetAsideProblem.tooMany);
      });

      test('un mes sin horas no tiene nada que apartar', () {
        expect(
          checkSetAside(apart(10, 1), null, rates),
          SetAsideProblem.tooMany,
        );
      });

      test('solo de meses abiertos', () {
        final l = line(
          record: MonthRecord(
            const YearMonth(2026, 11),
            deliveredOn: DateTime(2026, 12, 1),
          ),
        );
        expect(checkSetAside(apart(10, 1), l, rates), SetAsideProblem.notOpen);
      });

      test('sin tarifa normal en la fecha, no', () {
        final festiveOnly = [rate(DayKind.festive, 2020, 1, 1, 2000)];
        expect(
          checkSetAside(apart(10, 1), line(), festiveOnly),
          SetAsideProblem.noRate,
        );
      });
    });

    test('apartadas de un mes (RF-8)', () {
      final moves = [apart(10, 3), apart(12, 2), apart(1, 4, 10)];
      expect(setAsideMinutesIn(moves, const YearMonth(2026, 11)), 300);
      expect(setAsideMinutesIn(moves, const YearMonth(2026, 10)), 240);
      expect(setAsideMinutesIn(moves, const YearMonth(2026, 9)), 0);
    });
  });

  group('periodos de tarifa (021)', () {
    test('una sola tarifa: hasta hoy', () {
      final p = ratePeriods([
        rate(DayKind.normal, 2021, 1, 1, 1500),
      ], DayKind.normal);
      expect(p.single.rate.cents, 1500);
      expect(p.single.end, isNull);
    });

    test('dos tarifas: la antigua acaba el día antes de la nueva', () {
      final p = ratePeriods([
        rate(DayKind.normal, 2026, 1, 1, 1650),
        rate(DayKind.festive, 2021, 1, 1, 2000),
        rate(DayKind.normal, 2021, 1, 1, 1500),
      ], DayKind.normal);
      expect(p.map((x) => (x.rate.cents, x.end)), [
        (1650, null),
        (1500, DateTime(2025, 12, 31)),
      ]);
    });

    test('tres tarifas, con un 1 de marzo de año bisiesto', () {
      final p = ratePeriods([
        rate(DayKind.festive, 2024, 3, 1, 2100),
        rate(DayKind.festive, 2021, 1, 1, 2000),
        rate(DayKind.festive, 2026, 1, 1, 2200),
      ], DayKind.festive);
      expect(p.map((x) => x.end), [
        null,
        DateTime(2025, 12, 31),
        DateTime(2024, 2, 29),
      ]);
    });

    test('sin tarifas de ese tipo, vacío', () {
      expect(ratePeriods(const [], DayKind.normal), isEmpty);
    });

    test('un cambio que deja un apartado sin precio se detecta', () {
      final before = [rate(DayKind.normal, 2026, 1, 1, 1500)];
      final after = [rate(DayKind.normal, 2026, 7, 1, 1500)];
      final moves = [
        SavedMove(
          box: SavedBox.own,
          kind: SavedMoveKind.setAside,
          date: DateTime(2026, 3, 2),
          minutes: 60,
        ),
      ];
      expect(setAsidesUnpricedBy(before, after, moves), hasLength(1));
      expect(setAsidesUnpricedBy(before, before, moves), isEmpty);
    });
  });
}
