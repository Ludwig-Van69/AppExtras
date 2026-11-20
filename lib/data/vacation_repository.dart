import 'package:sqflite/sqflite.dart';

import '../domain/day_entry.dart';
import '../domain/vacations.dart';

/// Dónde se guardan las vacaciones (010).
abstract interface class VacationRepository {
  /// Los ajustes; nulo si aún no se han configurado (RF-4).
  Future<VacationSettings?> settings();

  /// Guarda los ajustes con sus correcciones, sustituyendo los anteriores.
  Future<void> saveSettings(VacationSettings settings);

  /// Todos los días marcados, por fecha.
  Future<List<VacationDay>> days();

  /// Marca un día o cambia su año (RF-5, RF-9).
  Future<void> saveDay(VacationDay day);

  /// Desmarca un día; si no estaba, no hace nada.
  Future<void> deleteDay(DateTime date);
}

/// La versión real, sobre SQLite.
class SqliteVacationRepository implements VacationRepository {
  SqliteVacationRepository(this._db);

  final Future<Database> Function() _db;

  @override
  Future<VacationSettings?> settings() async =>
      readVacationSettings(await _db());

  @override
  Future<void> saveSettings(VacationSettings s) async =>
      (await _db()).transaction((txn) => writeVacationSettings(txn, s));

  @override
  Future<List<VacationDay>> days() async => readVacationDays(await _db());

  @override
  Future<void> saveDay(VacationDay day) async => (await _db()).insert(
    'vacation_days',
    vacationDayToRow(day),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  @override
  Future<void> deleteDay(DateTime date) async => (await _db()).delete(
    'vacation_days',
    where: 'date = ?',
    whereArgs: [dateKey(date)],
  );
}

/// Fila de `vacation_days` (también la usan las copias).
Map<String, Object?> vacationDayToRow(VacationDay d) => {
  'date': dateKey(d.date),
  'year': d.year,
  'half': d.half ? 1 : 0,
};

/// Todos los días marcados, validados. Una fila imposible da error. Las
/// copias v5 no tienen la columna `half`: sus días son enteros (012, RF-14).
Future<List<VacationDay>> readVacationDays(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(vacation_days)');
  final withHalf = columns.any((c) => c['name'] == 'half');
  return [
    for (final r in await db.query('vacation_days', orderBy: 'date'))
      VacationDay(
        parseDateKey(r['date']! as String),
        r['year']! as int,
        half: withHalf && r['half'] == 1,
      ),
  ];
}

/// Los ajustes con sus correcciones; nulo si no hay.
Future<VacationSettings?> readVacationSettings(DatabaseExecutor db) async {
  final rows = await db.query('vacation_settings');
  if (rows.isEmpty) return null;
  final r = rows.single;
  return VacationSettings(
    firstYear: r['first_year']! as int,
    firstHalfDays: r['first_half_days']! as int,
    yearlyHalfDays: r['yearly_half_days']! as int,
    overrides: {
      for (final y in await db.query('vacation_years'))
        y['year']! as int: y['half_days']! as int,
    },
  );
}

/// Sustituye ajustes y correcciones por [s]; nulo los borra. Debe ir dentro
/// de una transacción.
Future<void> writeVacationSettings(
  DatabaseExecutor db,
  VacationSettings? s,
) async {
  await db.delete('vacation_settings');
  await db.delete('vacation_years');
  if (s == null) return;
  await db.insert('vacation_settings', {
    'id': 1,
    'first_year': s.firstYear,
    'first_half_days': s.firstHalfDays,
    'yearly_half_days': s.yearlyHalfDays,
  });
  for (final e in s.overrides.entries) {
    await db.insert('vacation_years', {'year': e.key, 'half_days': e.value});
  }
}
