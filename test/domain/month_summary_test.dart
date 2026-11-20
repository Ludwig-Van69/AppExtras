import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/month_summary.dart';

DayEntry _e(int y, int m, int d, int minutes, DayKind kind) =>
    DayEntry(date: DateTime(y, m, d), minutes: minutes, kind: kind);

void main() {
  test('suma solo los días del mes pedido, separando tipos (RF-21)', () {
    final entries = [
      _e(2026, 11, 1, 300, DayKind.festive),
      _e(2026, 11, 3, 150, DayKind.normal),
      _e(2026, 11, 30, 90, DayKind.normal),
      _e(2026, 10, 31, 600, DayKind.normal), // otro mes
      _e(2025, 11, 3, 60, DayKind.normal), // otro año
    ];
    final s = MonthSummary.of(entries, year: 2026, month: 11);
    expect(s.normalMinutes, 240);
    expect(s.festiveMinutes, 300);
    expect(s.totalMinutes, 540);
  });

  test('sin días, todo a cero', () {
    final s = MonthSummary.of(const [], year: 2026, month: 2);
    expect(s.totalMinutes, 0);
    expect(s.normalMinutes, 0);
    expect(s.festiveMinutes, 0);
  });

  test('el total es siempre normales más festivas (no cuenta dos veces)', () {
    final entries = [
      for (var d = 1; d <= 28; d++)
        _e(2026, 2, d, 30 * d, d.isEven ? DayKind.festive : DayKind.normal),
    ];
    final s = MonthSummary.of(entries, year: 2026, month: 2);
    expect(s.totalMinutes, s.normalMinutes + s.festiveMinutes);
    expect(s.totalMinutes, 30 * (28 * 29 ~/ 2));
  });
}
