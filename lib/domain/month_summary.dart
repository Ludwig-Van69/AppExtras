import 'day_entry.dart';
import 'day_kind.dart';

/// Horas de un mes, separadas por tipo (RF-21). Cada día suma en un solo
/// tipo, así que el total nunca cuenta una hora dos veces.
class MonthSummary {
  const MonthSummary({
    required this.normalMinutes,
    required this.festiveMinutes,
  });

  factory MonthSummary.of(
    Iterable<DayEntry> entries, {
    required int year,
    required int month,
  }) {
    var normal = 0;
    var festive = 0;
    for (final e in entries) {
      if (e.date.year != year || e.date.month != month) continue;
      if (e.kind == DayKind.festive) {
        festive += e.minutes;
      } else {
        normal += e.minutes;
      }
    }
    return MonthSummary(normalMinutes: normal, festiveMinutes: festive);
  }

  final int normalMinutes;
  final int festiveMinutes;

  int get totalMinutes => normalMinutes + festiveMinutes;
}
