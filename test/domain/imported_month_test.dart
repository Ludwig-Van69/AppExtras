import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/imported_month.dart';
import 'package:horas_y_vacaciones/domain/metrics.dart';
import 'package:horas_y_vacaciones/domain/money.dart';

/// Datos inventados.
final _rates = [
  Rate(DayKind.normal, DateTime(2022), 1200),
  Rate(DayKind.festive, DateTime(2022), 1600),
  Rate(DayKind.normal, DateTime(2022, 6, 15), 1500),
];

ImportedMonth _i(int y, int m, double normal, [double festive = 0]) =>
    ImportedMonth(
      YearMonth(y, m),
      (normal * 60).round(),
      (festive * 60).round(),
    );

DayEntry _e(int y, int m, int d, int minutes) =>
    DayEntry(date: DateTime(y, m, d), minutes: minutes, kind: DayKind.normal);

MoneyOverview _o(
  List<ImportedMonth> imported, {
  List<DayEntry> entries = const [],
  List<MonthRecord> records = const [],
}) => MoneyOverview.compute(
  entries: entries,
  rates: _rates,
  records: records,
  imported: imported,
);

void main() {
  group('mes del Excel (016, RF-1)', () {
    test('valida sus horas', () {
      expect(() => _i(2022, 6, 0), throwsArgumentError);
      expect(
        () => ImportedMonth(const YearMonth(2022, 6), -1, 60),
        throwsArgumentError,
      );
      expect(
        () =>
            ImportedMonth(const YearMonth(2022, 6), maxImportedMinutes + 1, 0),
        throwsArgumentError,
      );
      expect(_i(2022, 6, 42.5, 24.5).totalMinutes, 4020);
    });
  });

  group('en Resumen (016, RF-2)', () {
    test('cuenta como un mes con horas, a la tarifa del día 1', () {
      // Junio de 2022: el día 1 rige 12 € (la de 15 € empieza el 15).
      final o = _o([_i(2022, 6, 10, 2)]);
      final june = o.months.single;
      expect(june.imported, isNotNull);
      expect(june.minutes, 720);
      expect(june.minutesOf(DayKind.festive), 120);
      expect(june.amountCents, 12000 + 3200);
      expect(june.amountOf(DayKind.normal), 12000);
      expect(june.isComplete, isTrue);
      expect(o.toCollectMinutes, 720);
      expect(o.toCollectCents, 15200);
    });

    test('sin tarifa ese día 1, falta tarifa', () {
      final june = _o([_i(2021, 6, 7)]).months.single;
      expect(june.unpricedMinutes, 420);
      expect(june.isComplete, isFalse);
    });

    test('cobrado no suma a «A cobrar»', () {
      final o = _o(
        [_i(2022, 6, 10)],
        records: [
          MonthRecord(
            const YearMonth(2022, 6),
            deliveredOn: DateTime(2022, 6, 30),
            paidOn: DateTime(2022, 6, 30),
          ),
        ],
      );
      expect(o.toCollectCents, 0);
      expect(o.months.single.status, MonthStatus.paid);
    });

    test('con días y total del Excel, cuenta solo el total (RF-3)', () {
      final o = _o([_i(2022, 6, 10)], entries: [_e(2022, 6, 3, 120)]);
      final june = o.months.single;
      expect(june.minutes, 600);
      expect(june.hasIgnoredDays, isTrue);
      expect(june.countedDays, isEmpty);
      expect(june.days, hasLength(1));
    });

    test('los meses van ordenados del más reciente al más antiguo', () {
      final o = _o(
        [_i(2021, 7, 1), _i(2022, 6, 1)],
        entries: [_e(2026, 3, 2, 60)],
      );
      expect(o.months.map((m) => m.month), const [
        YearMonth(2026, 3),
        YearMonth(2022, 6),
        YearMonth(2021, 7),
      ]);
    });
  });

  group('en Métricas (016, RF-2, RF-6)', () {
    final today = DateTime(2026, 11, 18);

    test('suman en el año, las barras, la línea y los récords; no en la '
        'semana ni en los días con horas', () {
      final lines = _o(
        [_i(2025, 3, 40, 5), _i(2024, 2, 10)],
        entries: [_e(2026, 2, 2, 120)],
      ).months;
      final y = computeYearMetrics(
        months: lines,
        rates: _rates,
        year: 2025,
        today: today,
      );
      expect(y.total.minutes, 2700);
      expect(y.bars[2].figure.minutes, 2700);
      expect(y.weekdayMinutes.every((m) => m == 0), isTrue);
      expect(y.workdaysWithHours, 0);
      final g = computeGlobalMetrics(
        months: lines,
        rates: _rates,
        today: today,
      );
      expect(g.series.first.month, const YearMonth(2024, 2));
      expect(g.total.minutes, 2700 + 600 + 120);
      expect(g.bestMonth!.month, const YearMonth(2025, 3));
      expect(firstMetricsYear(lines), 2024);
    });

    test('la comparación se corta al final del mes anterior si el mes del '
        'año anterior es del Excel (RF-6)', () {
      final lines = _o(
        [_i(2025, 10, 10), _i(2025, 11, 30)],
        entries: [_e(2026, 10, 5, 300), _e(2026, 11, 2, 60)],
      ).months;
      final c = computeYearMetrics(
        months: lines,
        rates: _rates,
        year: 2026,
        today: today,
      ).comparison!;
      expect(c.until, DateTime(2026, 10, 31));
      expect(c.current.minutes, 300);
      expect(c.previous.minutes, 600);
    });

    test('con días en el año anterior, la comparación sigue cortando el día '
        'de hoy', () {
      final lines = _o(
        const [],
        entries: [_e(2025, 11, 10, 60), _e(2026, 11, 2, 60)],
      ).months;
      final c = computeYearMetrics(
        months: lines,
        rates: _rates,
        year: 2026,
        today: today,
      ).comparison!;
      expect(c.until, DateTime(2026, 11, 18));
    });
  });
}
