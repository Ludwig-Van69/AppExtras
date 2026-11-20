import 'dart:async';

import 'package:horas_y_vacaciones/data/day_entry_repository.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';

/// Repositorio en memoria para los tests de pantalla y del controlador. Puede
/// simular fallos al leer y al guardar, y guardados lentos.
class InMemoryDayEntryRepository implements DayEntryRepository {
  InMemoryDayEntryRepository([Iterable<DayEntry> initial = const []]) {
    for (final e in initial) {
      days[dateKey(e.date)] = e;
    }
  }

  final days = <String, DayEntry>{};
  bool failReads = false;
  bool failWrites = false;

  /// Cuántas de las próximas escrituras fallan.
  int failNextWrites = 0;

  /// Si no es nulo, cada escritura espera a que se complete.
  Completer<void>? writeGate;

  int writes = 0;

  @override
  Future<List<DayEntry>> allEntries() async {
    if (failReads) throw StateError('lectura simulada fallida');
    return days.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  @override
  Future<List<DayEntry>> entriesInMonth(int year, int month) async {
    if (failReads) throw StateError('lectura simulada fallida');
    return (days.values
        .where((e) => e.date.year == year && e.date.month == month)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date)));
  }

  Future<void> _write(void Function() change) async {
    writes++;
    final gate = writeGate;
    if (gate != null) await gate.future;
    if (failNextWrites > 0) {
      failNextWrites--;
      throw StateError('escritura simulada fallida');
    }
    if (failWrites) throw StateError('escritura simulada fallida');
    change();
  }

  @override
  Future<void> save(DayEntry e) => _write(() => days[dateKey(e.date)] = e);

  @override
  Future<void> delete(DateTime date) =>
      _write(() => days.remove(dateKey(date)));

  @override
  Future<Map<String, int>> reasonUsage() async {
    if (failReads) throw StateError('lectura simulada fallida');
    final usage = <String, int>{};
    for (final e in days.values) {
      if (e.reason != null) usage[e.reason!] = (usage[e.reason!] ?? 0) + 1;
    }
    return usage;
  }
}
