import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/imported_month.dart';
import 'package:horas_y_vacaciones/domain/money.dart';
import 'package:horas_y_vacaciones/domain/saved_hours.dart';

DayEntry _day(int m, int d, int minutes, [DayKind k = DayKind.normal]) =>
    DayEntry(date: DateTime(2026, m, d), minutes: minutes, kind: k);

Rate _rate(DayKind k, int m, int d, int cents) =>
    Rate(k, DateTime(2026, m, d), cents);

MonthRecord _delivered(int m) =>
    MonthRecord(YearMonth(2026, m), deliveredOn: DateTime(2026, m + 1, 2));

/// Datos inventados: 15 € normal y 16,50 € festiva desde enero.
final _rates = [
  _rate(DayKind.normal, 1, 1, 1500),
  _rate(DayKind.festive, 1, 1, 1650),
];

HoursBreakdown _breakdown({
  required List<DayEntry> entries,
  List<Rate>? rates,
  List<MonthRecord>? records,
  List<SavedMove> moves = const [],
  List<ImportedMonth> imported = const [],
}) => HoursBreakdown.of(
  MoneyOverview.compute(
    entries: entries,
    rates: rates ?? _rates,
    records: records ?? [_delivered(10)],
    savedMoves: moves,
    imported: imported,
  ).deliveredUnpaid,
);

void main() {
  test('40 h normales y 10 festivas: 600 + 165 = 765 € (RF-2)', () {
    final b = _breakdown(
      entries: [
        for (var d = 1; d <= 5; d++) _day(10, d, 480),
        _day(10, 12, 600, DayKind.festive),
      ],
    );
    expect(b.lines, hasLength(2));
    expect(b.lines[0].kind, DayKind.normal);
    expect(b.lines[0].minutes, 2400);
    expect(b.lines[0].rateCents, 1500);
    expect(b.lines[0].cents, 60000);
    expect(b.lines[1].kind, DayKind.festive);
    expect(b.lines[1].cents, 16500);
    expect(b.totalCents, 76500);
    expect(b.roundingCents, 0);
    expect(b.unpricedMinutes, 0);
  });

  test('solo cuentan los meses entregados sin cobrar', () {
    final b = _breakdown(
      entries: [_day(9, 1, 60), _day(10, 1, 120), _day(11, 1, 180)],
      records: [
        MonthRecord(const YearMonth(2026, 9), paidOn: DateTime(2026, 10, 5)),
        _delivered(10),
      ],
    );
    expect(b.lines.single.minutes, 120);
    expect(b.totalCents, 3000);
  });

  test('del total: todos los meses sin cobrar, entregados o no (RF-1)', () {
    final o = MoneyOverview.compute(
      entries: [_day(9, 1, 60), _day(10, 1, 120), _day(11, 1, 180)],
      rates: _rates,
      records: [
        MonthRecord(const YearMonth(2026, 9), paidOn: DateTime(2026, 10, 5)),
        _delivered(10),
      ],
    );
    final b = HoursBreakdown.of(
      o.months.where((m) => m.status != MonthStatus.paid),
    );
    expect(b.lines.single.minutes, 300);
    expect(b.totalCents, o.toCollectCents);
  });

  test('sin meses entregados, vacío', () {
    final b = _breakdown(entries: [_day(10, 1, 60)], records: const []);
    expect(b.isEmpty, isTrue);
  });

  test('tarifa cambiada a mitad de mes: dos líneas de normales', () {
    final b = _breakdown(
      entries: [_day(10, 1, 120), _day(10, 20, 60)],
      rates: [..._rates, _rate(DayKind.normal, 10, 15, 1600)],
    );
    final normal = b.lines.where((l) => l.kind == DayKind.normal).toList();
    expect(normal.map((l) => (l.minutes, l.rateCents)), [
      (120, 1500),
      (60, 1600),
    ]);
    expect(b.totalCents, 3000 + 1600);
  });

  test('lo apartado se resta de las normales a su tarifa', () {
    final b = _breakdown(
      entries: [_day(10, 1, 600)],
      moves: [
        SavedMove(
          box: SavedBox.own,
          kind: SavedMoveKind.setAside,
          date: DateTime(2026, 10, 1),
          minutes: 180,
        ),
      ],
    );
    expect(b.lines.single.minutes, 420);
    expect(b.totalCents, 10500);
  });

  test('un mes del Excel cuenta con su tarifa del día 1', () {
    final b = _breakdown(
      entries: const [],
      imported: [ImportedMonth(const YearMonth(2026, 10), 600, 120)],
    );
    expect(b.lines.map((l) => (l.kind, l.minutes)), [
      (DayKind.normal, 600),
      (DayKind.festive, 120),
    ]);
    expect(b.totalCents, 15000 + 3300);
  });

  test(
    'el redondeo de cada mes sale en su línea y la cuenta cuadra (RF-3)',
    () {
      // 1 minuto a 1 € = 1,67 céntimos → 2 en cada mes; juntos, 3,33 → 3.
      final rates = [_rate(DayKind.normal, 1, 1, 100)];
      final b = _breakdown(
        entries: [_day(9, 1, 1), _day(10, 1, 1)],
        rates: rates,
        records: [_delivered(9), _delivered(10)],
      );
      expect(b.lines.single.cents, 3);
      expect(b.totalCents, 4);
      expect(b.roundingCents, 1);
      expect(
        b.lines.fold(0, (s, l) => s + l.cents) + b.roundingCents,
        b.totalCents,
      );
    },
  );

  test('horas sin tarifa: aparte y sin importe (RF-4)', () {
    final b = _breakdown(
      entries: [_day(10, 1, 120), _day(10, 2, 60, DayKind.festive)],
      rates: [_rate(DayKind.normal, 1, 1, 1500)],
    );
    expect(b.lines.single.kind, DayKind.normal);
    expect(b.unpricedMinutes, 60);
    expect(b.totalCents, 3000);
  });
}
