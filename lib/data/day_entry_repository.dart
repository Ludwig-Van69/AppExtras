import 'package:sqflite/sqflite.dart';

import '../domain/day_entry.dart';
import '../domain/day_kind.dart';

/// Dónde se guardan los días apuntados.
abstract interface class DayEntryRepository {
  /// Los días con horas de un mes, ordenados por fecha.
  Future<List<DayEntry>> entriesInMonth(int year, int month);

  /// Todos los días con horas, ordenados por fecha (para el dinero).
  Future<List<DayEntry>> allEntries();

  /// Guarda el día, sustituyendo el que hubiera en esa fecha (RF-7).
  Future<void> save(DayEntry entry);

  /// Borra el día entero; si no existía, no hace nada (RF-18).
  Future<void> delete(DateTime date);

  /// Cada motivo usado y cuántos días lo llevan (RF-16).
  Future<Map<String, int>> reasonUsage();
}

/// El repositorio real, sobre SQLite. Abre la base de datos la primera vez
/// que se usa; si falla, lo vuelve a intentar en la siguiente llamada, así
/// «Reintentar» funciona (RF-26).
class SqliteDayEntryRepository implements DayEntryRepository {
  SqliteDayEntryRepository(this._open, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Future<Database> Function() _open;
  final DateTime Function() _clock;
  Future<Database>? _opening;

  Future<Database> get database async {
    final opening = _opening ??= _open();
    try {
      return await opening;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static const _table = 'day_entries';

  @override
  Future<List<DayEntry>> entriesInMonth(int year, int month) async {
    final from = dateKey(DateTime(year, month));
    final to = dateKey(DateTime(year, month + 1, 0));
    final rows = await (await database).query(
      _table,
      where: 'date BETWEEN ? AND ?',
      whereArgs: [from, to],
      orderBy: 'date',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<DayEntry>> allEntries() async {
    final rows = await (await database).query(_table, orderBy: 'date');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> save(DayEntry e) async => (await database).insert(_table, {
    'date': dateKey(e.date),
    'minutes': e.minutes,
    'kind': e.kind.name,
    'reason': e.reason,
    'updated_at': _clock().toUtc().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> delete(DateTime date) async => (await database).delete(
    _table,
    where: 'date = ?',
    whereArgs: [dateKey(date)],
  );

  @override
  Future<Map<String, int>> reasonUsage() async {
    final rows = await (await database).rawQuery(
      'SELECT reason, COUNT(*) AS uses FROM $_table '
      'WHERE reason IS NOT NULL GROUP BY reason',
    );
    return {for (final r in rows) r['reason']! as String: r['uses']! as int};
  }

  /// Una fila que no encaja da error en vez de inventar datos (RF-26).
  static DayEntry _fromRow(Map<String, Object?> r) => DayEntry(
    date: parseDateKey(r['date']! as String),
    minutes: r['minutes']! as int,
    kind: DayKind.values.byName(r['kind']! as String),
    reason: r['reason'] as String?,
  );
}
