import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../domain/company.dart';
import '../domain/day_entry.dart';
import '../domain/day_kind.dart';
import '../domain/extras.dart';
import '../domain/imported_month.dart';
import '../domain/money.dart';
import '../domain/saved_hours.dart';
import '../domain/vacations.dart';
import 'app_database.dart';
import 'company_repository.dart';
import 'extras_repository.dart';
import 'money_repository.dart';
import 'saved_hours_repository.dart';
import 'vacation_repository.dart';

/// Por qué un archivo no vale como copia (RF-16).
enum BackupProblem {
  /// No es una base de datos, está dañado o no tiene los días de esta app.
  notABackup,

  /// Es de una versión de la app más nueva que esta.
  tooNew,

  /// Es una copia de la app, pero con días imposibles.
  badRows,
}

class BackupException implements Exception {
  const BackupException(this.problem);
  final BackupProblem problem;

  /// Qué le pasa al archivo y qué hacer, en palabras sencillas.
  String get message => switch (problem) {
    BackupProblem.notABackup =>
      'Este archivo no es una copia de esta app o está dañado. '
          'Elige otra copia.',
    BackupProblem.tooNew =>
      'Esta copia es de una versión más nueva de la app. '
          'Actualiza la app y vuelve a probar.',
    BackupProblem.badRows =>
      'Esta copia tiene datos que no son válidos, así que no se ha usado. '
          'Elige otra copia.',
  };

  @override
  String toString() => 'BackupException(${problem.name})';
}

/// Un día tal como está guardado, con su marca de última modificación.
class BackupDay {
  const BackupDay(this.entry, this.updatedAt);
  final DayEntry entry;
  final String updatedAt;
}

/// Lo que no son días: tarifas y estados de los meses (formato v2, 005),
/// multas y extras (formato v3, 007) y horas guardadas (formato v4, 008).
class BackupExtras {
  const BackupExtras(
    this.rates,
    this.months, [
    this.items,
    this.savedMoves,
    this.vacation,
    this.importedMonths,
    this.company,
  ]);
  final List<Rate> rates;
  final List<MonthRecord> months;

  /// Multas y extras; nulo en las copias v2, que no los tienen (RF-14).
  final List<ExtraItem>? items;

  /// Movimientos de las horas guardadas; nulo en las copias v1-v3 (008,
  /// RF-21).
  final List<SavedMove>? savedMoves;

  /// Vacaciones; nulo en las copias v1-v4 (010, RF-20).
  final BackupVacation? vacation;

  /// Meses del Excel; nulo en las copias v1-v6, que no los tienen. Al
  /// restaurar una de esas, se conservan los actuales (016, RF-8).
  final List<ImportedMonth>? importedMonths;

  /// La empresa; nulo en las copias v1-v9, que no la tienen. Al restaurar
  /// una de esas, se conserva la actual (026, RF-9).
  final Company? company;
}

/// Las vacaciones de una copia v5 o posterior (en la v6, con medios días): ajustes (nulos si no se configuraron) y
/// días marcados.
class BackupVacation {
  const BackupVacation(this.settings, this.days);
  final VacationSettings? settings;
  final List<VacationDay> days;
}

/// Todo lo que contiene una copia. [extras] es nulo en las copias de formato
/// v1, que no tienen tarifas ni meses (RF-15).
class BackupData {
  const BackupData(this.days, this.extras);
  final List<BackupDay> days;
  final BackupExtras? extras;
}

/// Saca una «foto» exacta de la base de datos a [destPath] (el archivo no
/// debe existir) y no la da por buena hasta abrirla y comprobar que tiene los
/// mismos días que la base (RF-7). Si algo falla, borra el archivo a medias.
Future<void> createBackupFile(
  Database db,
  String destPath, {
  DatabaseFactory? factory,
}) async {
  // Nunca se pisa (ni se borra) un archivo que ya existe.
  if (await File(destPath).exists()) {
    throw StateError('El archivo de destino ya existe');
  }
  try {
    await db.execute('VACUUM INTO ?', [destPath]);
    final copied = await readBackupData(destPath, factory: factory);
    final original = await readAllDays(db);
    final version = await db.getVersion();
    final originalExtras = version >= 2
        ? await readExtras(
            db,
            withItems: version >= 3,
            withSaved: version >= 4,
            withVacation: version >= 5,
            withImported: version >= 7,
            withCompany: version >= 10,
          )
        : null;
    if (!_sameDays(copied.days, original) ||
        !_sameExtras(copied.extras, originalExtras)) {
      throw StateError('La copia no coincide con los datos');
    }
  } catch (_) {
    await _deleteQuietly(destPath);
    rethrow;
  }
}

/// Abre el archivo [path] solo para leer y devuelve sus días ya validados con
/// las reglas de siempre. No lo modifica. Lanza [BackupException] si no vale
/// (RF-16).
Future<List<BackupDay>> readBackupFile(
  String path, {
  DatabaseFactory? factory,
}) async => (await readBackupData(path, factory: factory)).days;

/// Como [readBackupFile], pero con tarifas y meses si la copia es v2.
Future<BackupData> readBackupData(
  String path, {
  DatabaseFactory? factory,
}) async {
  if (!await _hasSqliteHeader(path)) {
    throw const BackupException(BackupProblem.notABackup);
  }
  final f = factory ?? databaseFactory;
  Database? db;
  try {
    db = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    final version = await db.getVersion();
    if (version > databaseVersion) {
      throw const BackupException(BackupProblem.tooNew);
    }
    if (version < 1) throw const BackupException(BackupProblem.notABackup);
    final days = await readAllDays(db);
    return BackupData(
      days,
      version >= 2
          ? await readExtras(
              db,
              withItems: version >= 3,
              withSaved: version >= 4,
              withVacation: version >= 5,
              withImported: version >= 7,
              withCompany: version >= 10,
            )
          : null,
    );
  } on BackupException {
    rethrow;
  } on TypeError {
    throw const BackupException(BackupProblem.badRows);
  } on FormatException {
    throw const BackupException(BackupProblem.badRows);
  } on ArgumentError {
    throw const BackupException(BackupProblem.badRows);
  } catch (_) {
    // SQLite no puede abrirlo o le falta la tabla: dañado o ajeno.
    throw const BackupException(BackupProblem.notABackup);
  } finally {
    await db?.close();
  }
}

/// Sustituye todos los días de [db] por [days] en una sola transacción: o se
/// hace entera o no cambia nada (RF-14).
Future<void> restoreDays(
  Database db,
  List<BackupDay> days, {
  BackupExtras? extras,
}) => db.transaction((txn) async {
  if (extras != null) {
    await txn.delete('rates');
    await txn.delete('months');
    for (final r in extras.rates) {
      await txn.insert('rates', {
        'kind': r.kind.name,
        'start_date': dateKey(r.start),
        'cents': r.cents,
      });
    }
    for (final m in extras.months) {
      if (m.status == MonthStatus.open) continue;
      await txn.insert('months', {
        'month': m.month.key,
        'delivered_on': dateKey(m.deliveredOn!),
        'paid_on': m.paidOn == null ? null : dateKey(m.paidOn!),
      });
    }
    final items = extras.items;
    if (items != null) {
      await txn.delete('extras');
      for (final e in items) {
        await txn.insert('extras', extraToRow(e));
      }
    }
    final saved = extras.savedMoves;
    if (saved != null) {
      await txn.delete('saved_moves');
      for (final m in saved) {
        await txn.insert('saved_moves', savedMoveToRow(m));
      }
    }
    final imported = extras.importedMonths;
    if (imported != null) {
      await txn.delete('imported_months');
      for (final m in imported) {
        await txn.insert('imported_months', importedMonthToRow(m));
      }
    }
    final company = extras.company;
    if (company != null) await writeCompany(txn, company);
    final vacation = extras.vacation;
    if (vacation != null) {
      await writeVacationSettings(txn, vacation.settings);
      await txn.delete('vacation_days');
      for (final d in vacation.days) {
        await txn.insert('vacation_days', vacationDayToRow(d));
      }
    }
  }
  await txn.delete('day_entries');
  final batch = txn.batch();
  for (final d in days) {
    batch.insert('day_entries', {
      'date': dateKey(d.entry.date),
      'minutes': d.entry.minutes,
      'kind': d.entry.kind.name,
      'reason': d.entry.reason,
      'updated_at': d.updatedAt,
    });
  }
  await batch.commit(noResult: true);
});

/// Todos los días de la base, ordenados por fecha. Una fila imposible da
/// [FormatException], [ArgumentError] o [BackupException].
Future<List<BackupDay>> readAllDays(DatabaseExecutor db) async {
  final rows = await db.query('day_entries', orderBy: 'date');
  final seen = <String>{};
  return [
    for (final r in rows)
      () {
        final key = r['date'];
        final minutes = r['minutes'];
        final kind = r['kind'];
        final reason = r['reason'];
        final updated = r['updated_at'];
        if (key is! String ||
            minutes is! int ||
            kind is! String ||
            reason is! String? ||
            updated is! String ||
            updated.isEmpty ||
            !seen.add(key)) {
          throw const BackupException(BackupProblem.badRows);
        }
        final k = DayKind.values.asNameMap()[kind];
        if (k == null) throw const BackupException(BackupProblem.badRows);
        return BackupDay(
          DayEntry(
            date: parseDateKey(key),
            minutes: minutes,
            kind: k,
            reason: reason,
          ),
          updated,
        );
      }(),
  ];
}

/// Tarifas y meses de la base (y multas y extras si [withItems], y horas
/// guardadas si [withSaved], y vacaciones si [withVacation]), validados con las reglas del dominio. Una fila
/// imposible, o unas horas guardadas que dejan un cajón en negativo, dan
/// [FormatException], [ArgumentError], [TypeError] o [BackupException].
Future<BackupExtras> readExtras(
  DatabaseExecutor db, {
  bool withItems = false,
  bool withSaved = false,
  bool withVacation = false,
  bool withImported = false,
  bool withCompany = false,
}) async {
  final rates = <Rate>[];
  for (final r in await db.query('rates', orderBy: 'kind, start_date')) {
    final kind = DayKind.values.asNameMap()[r['kind']];
    final start = r['start_date'];
    final cents = r['cents'];
    if (kind == null || start is! String || cents is! int) {
      throw const BackupException(BackupProblem.badRows);
    }
    rates.add(Rate(kind, parseDateKey(start), cents));
  }
  final months = <MonthRecord>[];
  for (final r in await db.query('months', orderBy: 'month')) {
    final month = r['month'];
    final delivered = r['delivered_on'];
    final paid = r['paid_on'];
    if (month is! String ||
        delivered is! String? ||
        paid is! String? ||
        (paid != null && delivered == null)) {
      throw const BackupException(BackupProblem.badRows);
    }
    months.add(
      MonthRecord(
        YearMonth.parse(month),
        deliveredOn: delivered == null ? null : parseDateKey(delivered),
        paidOn: paid == null ? null : parseDateKey(paid),
      ),
    );
  }
  final items = withItems
      ? [
          for (final r in await db.query('extras', orderBy: 'id'))
            extraFromRow(r),
        ]
      : null;
  final saved = withSaved
      ? [
          for (final r in await db.query('saved_moves', orderBy: 'id'))
            savedMoveFromRow(r),
        ]
      : null;
  if (saved != null && findSavedShortfall(saved) != null) {
    throw const BackupException(BackupProblem.badRows);
  }
  final vacation = withVacation
      ? BackupVacation(
          await readVacationSettings(db),
          await readVacationDays(db),
        )
      : null;
  final imported = withImported ? await readImportedMonths(db) : null;
  final company = withCompany ? await readCompany(db) : null;
  return BackupExtras(rates, months, items, saved, vacation, imported, company);
}

bool _sameExtras(BackupExtras? a, BackupExtras? b) {
  if (a == null || b == null) return a == b;
  if (a.rates.length != b.rates.length || a.months.length != b.months.length) {
    return false;
  }
  for (var i = 0; i < a.rates.length; i++) {
    if (a.rates[i] != b.rates[i]) return false;
  }
  if (a.company != b.company) return false;
  if (!_sameList(a.items, b.items) ||
      !_sameList(a.savedMoves, b.savedMoves) ||
      !_sameList(a.importedMonths, b.importedMonths)) {
    return false;
  }
  final v = a.vacation;
  final w = b.vacation;
  if ((v == null) != (w == null)) return false;
  if (v != null &&
      w != null &&
      (v.settings != w.settings || !_sameList(v.days, w.days))) {
    return false;
  }
  for (var i = 0; i < a.months.length; i++) {
    final x = a.months[i];
    final y = b.months[i];
    if (x.month != y.month ||
        x.deliveredOn != y.deliveredOn ||
        x.paidOn != y.paidOn) {
      return false;
    }
  }
  return true;
}

bool _sameList<T>(List<T>? x, List<T>? y) {
  if (x == null || y == null) return x == y;
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

bool _sameDays(List<BackupDay> a, List<BackupDay> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].entry != b[i].entry || a[i].updatedAt != b[i].updatedAt) {
      return false;
    }
  }
  return true;
}

Future<bool> _hasSqliteHeader(String path) async {
  try {
    final raf = await File(path).open();
    try {
      final head = await raf.read(16);
      return String.fromCharCodes(head) == 'SQLite format 3\u0000';
    } finally {
      await raf.close();
    }
  } on FileSystemException {
    return false;
  }
}

Future<void> _deleteQuietly(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } on FileSystemException {
    // Si no se puede borrar, no empeora nada: el nombre es temporal.
  }
}
