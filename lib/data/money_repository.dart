import 'package:sqflite/sqflite.dart';

import '../domain/day_entry.dart';
import '../domain/day_kind.dart';
import '../domain/imported_month.dart';
import '../domain/money.dart';

/// Dónde se guardan las tarifas y el estado de los meses (005).
abstract interface class MoneyRepository {
  /// Todas las tarifas, de cualquier tipo y fecha.
  Future<List<Rate>> rates();

  /// Guarda la tarifa, sustituyendo la que hubiera para ese tipo y fecha.
  Future<void> saveRate(Rate rate);

  /// Borra la tarifa de ese tipo que empieza en [start]; si no existe, no
  /// hace nada.
  Future<void> deleteRate(DayKind kind, DateTime start);

  /// Cambia [old] por [updated] de una vez: o se hacen las dos cosas o
  /// ninguna (021, RF-3).
  Future<void> replaceRate(Rate old, Rate updated);

  /// Los meses con algún estado guardado (entregado o cobrado).
  Future<List<MonthRecord>> months();

  /// Guarda el estado del mes; si está Abierto, no guarda nada y quita lo que
  /// hubiera.
  Future<void> saveMonth(MonthRecord record);

  /// Los meses del Excel, del más antiguo al más reciente (016, RF-1).
  Future<List<ImportedMonth>> importedMonths();
}

/// Un mes del Excel como fila de `imported_months`.
Map<String, Object?> importedMonthToRow(ImportedMonth m) => {
  'month': m.month.key,
  'normal_minutes': m.normalMinutes,
  'festive_minutes': m.festiveMinutes,
};

/// Lo contrario de [importedMonthToRow]; una fila imposible da
/// [ArgumentError], [FormatException] o [TypeError].
ImportedMonth importedMonthFromRow(Map<String, Object?> r) => ImportedMonth(
  YearMonth.parse(r['month']! as String),
  r['normal_minutes']! as int,
  r['festive_minutes']! as int,
);

/// Todos los meses del Excel de [db], ordenados.
Future<List<ImportedMonth>> readImportedMonths(DatabaseExecutor db) async => [
  for (final r in await db.query('imported_months', orderBy: 'month'))
    importedMonthFromRow(r),
];

/// La versión real, sobre SQLite.
class SqliteMoneyRepository implements MoneyRepository {
  SqliteMoneyRepository(this._db);

  final Future<Database> Function() _db;

  @override
  Future<List<Rate>> rates() async {
    final rows = await (await _db()).query('rates', orderBy: 'start_date');
    return [
      for (final r in rows)
        Rate(
          DayKind.values.byName(r['kind']! as String),
          parseDateKey(r['start_date']! as String),
          r['cents']! as int,
        ),
    ];
  }

  @override
  Future<void> saveRate(Rate rate) async => (await _db()).insert('rates', {
    'kind': rate.kind.name,
    'start_date': dateKey(rate.start),
    'cents': rate.cents,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> deleteRate(DayKind kind, DateTime start) async =>
      (await _db()).delete(
        'rates',
        where: 'kind = ? AND start_date = ?',
        whereArgs: [kind.name, dateKey(start)],
      );

  @override
  Future<void> replaceRate(Rate old, Rate updated) async =>
      (await _db()).transaction((txn) async {
        await txn.delete(
          'rates',
          where: 'kind = ? AND start_date = ?',
          whereArgs: [old.kind.name, dateKey(old.start)],
        );
        await txn.insert('rates', {
          'kind': updated.kind.name,
          'start_date': dateKey(updated.start),
          'cents': updated.cents,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });

  @override
  Future<List<ImportedMonth>> importedMonths() async =>
      readImportedMonths(await _db());

  @override
  Future<List<MonthRecord>> months() async {
    final rows = await (await _db()).query('months', orderBy: 'month');
    return [
      for (final r in rows)
        MonthRecord(
          YearMonth.parse(r['month']! as String),
          deliveredOn: _date(r['delivered_on']),
          paidOn: _date(r['paid_on']),
        ),
    ];
  }

  @override
  Future<void> saveMonth(MonthRecord record) async {
    final db = await _db();
    if (record.status == MonthStatus.open) {
      await db.delete(
        'months',
        where: 'month = ?',
        whereArgs: [record.month.key],
      );
      return;
    }
    await db.insert('months', {
      'month': record.month.key,
      'delivered_on': dateKey(record.deliveredOn!),
      'paid_on': record.paidOn == null ? null : dateKey(record.paidOn!),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static DateTime? _date(Object? v) =>
      v == null ? null : parseDateKey(v as String);
}
