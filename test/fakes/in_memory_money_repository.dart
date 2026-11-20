import 'package:horas_y_vacaciones/data/money_repository.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/imported_month.dart';
import 'package:horas_y_vacaciones/domain/money.dart';

/// Tarifas y meses en memoria para los tests, con fallos simulables.
class InMemoryMoneyRepository implements MoneyRepository {
  final rateList = <Rate>[];
  final monthMap = <YearMonth, MonthRecord>{};
  final importedList = <ImportedMonth>[];
  bool failWrites = false;

  @override
  Future<List<Rate>> rates() async => [...rateList];

  @override
  Future<void> saveRate(Rate rate) async {
    if (failWrites) throw StateError('escritura simulada fallida');
    rateList.removeWhere((r) => r.kind == rate.kind && r.start == rate.start);
    rateList.add(rate);
  }

  @override
  Future<void> deleteRate(DayKind kind, DateTime start) async {
    if (failWrites) throw StateError('escritura simulada fallida');
    rateList.removeWhere((r) => r.kind == kind && r.start == start);
  }

  @override
  Future<void> replaceRate(Rate old, Rate updated) async {
    if (failWrites) throw StateError('escritura simulada fallida');
    rateList
      ..removeWhere((r) => r.kind == old.kind && r.start == old.start)
      ..removeWhere((r) => r.kind == updated.kind && r.start == updated.start)
      ..add(updated);
  }

  @override
  Future<List<MonthRecord>> months() async => monthMap.values.toList();

  @override
  Future<List<ImportedMonth>> importedMonths() async => [...importedList];

  @override
  Future<void> saveMonth(MonthRecord record) async {
    if (failWrites) throw StateError('escritura simulada fallida');
    if (record.status == MonthStatus.open) {
      monthMap.remove(record.month);
    } else {
      monthMap[record.month] = record;
    }
  }
}
