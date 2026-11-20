import 'package:horas_y_vacaciones/data/vacation_repository.dart';
import 'package:horas_y_vacaciones/domain/vacations.dart';

/// Vacaciones en memoria para los tests, con fallos simulables.
class InMemoryVacationRepository implements VacationRepository {
  InMemoryVacationRepository({
    this.stored,
    Iterable<VacationDay> days = const [],
  }) {
    for (final d in days) {
      byDate[d.date] = d;
    }
  }

  VacationSettings? stored;
  final byDate = <DateTime, VacationDay>{};
  bool failWrites = false;

  @override
  Future<VacationSettings?> settings() async => stored;

  @override
  Future<void> saveSettings(VacationSettings s) async {
    if (failWrites) throw StateError('escritura simulada fallida');
    stored = s;
  }

  @override
  Future<List<VacationDay>> days() async =>
      byDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));

  @override
  Future<void> saveDay(VacationDay day) async {
    if (failWrites) throw StateError('escritura simulada fallida');
    byDate[day.date] = day;
  }

  @override
  Future<void> deleteDay(DateTime date) async {
    if (failWrites) throw StateError('escritura simulada fallida');
    byDate.remove(DateTime(date.year, date.month, date.day));
  }
}
