import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Versión del formato de los datos. Si cambia, hace falta una migración
/// probada y una copia previa (constitución, principio 3).
const databaseVersion = 8;

/// Nombre del archivo, dentro de la carpeta privada de la app.
const databaseFileName = 'horas.db';

/// El cambio de formato no se hizo porque la copia previa falló (RF-9).
class MigrationBlockedException implements Exception {
  const MigrationBlockedException(this.from, this.to);
  final int from;
  final int to;

  String get message =>
      'No se ha podido guardar una copia antes de actualizar tus datos, así '
      'que no se han tocado. Elige una carpeta de copias que funcione y '
      'vuelve a abrir la app.';

  @override
  String toString() => 'MigrationBlockedException($from -> $to)';
}

/// Abre (o crea) la base de datos de la app. [factory], [path] y [version]
/// solo se cambian en los tests.
///
/// Si el archivo existe con un formato anterior, antes de cambiarlo se llama a
/// [backupBeforeUpgrade] con la ruta del archivo; si esa copia falla, no se
/// cambia nada y se lanza [MigrationBlockedException] (RF-9).
Future<Database> openAppDatabase({
  DatabaseFactory? factory,
  String? path,
  int version = databaseVersion,
  Future<void> Function(String dbPath)? backupBeforeUpgrade,
}) async {
  final f = factory ?? databaseFactory;
  final file = path ?? p.join(await f.getDatabasesPath(), databaseFileName);
  final current = await storedVersion(file, factory: f);
  if (current != null && current < version) {
    try {
      await backupBeforeUpgrade?.call(file);
    } catch (_) {
      throw MigrationBlockedException(current, version);
    }
  }
  return f.openDatabase(
    file,
    options: OpenDatabaseOptions(
      version: version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await createSchemaV1(db);
        if (version >= 2) await createSchemaV2(db);
        if (version >= 3) await createSchemaV3(db);
        if (version >= 4) await createSchemaV4(db);
        if (version >= 5) await createSchemaV5(db);
        if (version >= 6) await createSchemaV6(db);
        if (version >= 7) await createSchemaV7(db);
        if (version >= 8) await createSchemaV8(db);
      },
      // Cada salto de versión va aquí, con su test.
      onUpgrade: (db, from, to) async {
        if (from < 2 && to >= 2) await createSchemaV2(db);
        if (from < 3 && to >= 3) await createSchemaV3(db);
        if (from < 4 && to >= 4) await createSchemaV4(db);
        if (from < 5 && to >= 5) await createSchemaV5(db);
        if (from < 6 && to >= 6) await createSchemaV6(db);
        if (from < 7 && to >= 7) await createSchemaV7(db);
        if (from < 8 && to >= 8) await createSchemaV8(db);
      },
      onDowngrade: (db, from, to) => throw StateError(
        'Los datos son de una versión más nueva de la app ($from) que '
        'esta ($to). Instala la versión más reciente.',
      ),
    ),
  );
}

/// La versión de formato del archivo [file], leyéndolo sin modificarlo; nulo
/// si el archivo no existe (o es una base en memoria).
Future<int?> storedVersion(String file, {DatabaseFactory? factory}) async {
  if (file == inMemoryDatabasePath || !await File(file).exists()) return null;
  final db = await (factory ?? databaseFactory).openDatabase(
    file,
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  try {
    return await db.getVersion();
  } finally {
    await db.close();
  }
}

/// Formato v1: un registro por día como máximo; la fecha es la clave
/// (RF-27). Las comprobaciones repiten las reglas del dominio para que ni
/// un fallo del código pueda guardar algo imposible.
Future<void> createSchemaV1(DatabaseExecutor db) => db.execute('''
CREATE TABLE day_entries (
  date TEXT NOT NULL PRIMARY KEY
    CHECK (date GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]'),
  minutes INTEGER NOT NULL CHECK (minutes BETWEEN 1 AND 1440),
  kind TEXT NOT NULL CHECK (kind IN ('normal', 'festive')),
  reason TEXT CHECK (reason IS NULL OR length(reason) BETWEEN 1 AND 60),
  updated_at TEXT NOT NULL
)''');

/// Formato v2 (005): tarifas con fecha de inicio y estado de cada mes. Se
/// añade a la v1 sin tocar sus datos.
Future<void> createSchemaV2(DatabaseExecutor db) async {
  await db.execute('''
CREATE TABLE rates (
  kind TEXT NOT NULL CHECK (kind IN ('normal', 'festive')),
  start_date TEXT NOT NULL
    CHECK (start_date GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]'),
  cents INTEGER NOT NULL CHECK (cents BETWEEN 1 AND 100000),
  PRIMARY KEY (kind, start_date)
)''');
  await db.execute('''
CREATE TABLE months (
  month TEXT NOT NULL PRIMARY KEY
    CHECK (month GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]'),
  delivered_on TEXT,
  paid_on TEXT,
  CHECK (paid_on IS NULL OR delivered_on IS NOT NULL)
)''');
}

/// Formato v3 (007): multas y extras. Se añade a la v2 sin tocar sus datos.
/// Solo una cerrada (descontada o cobrada) lleva fecha de cierre.
Future<void> createSchemaV3(DatabaseExecutor db) => db.execute('''
CREATE TABLE extras (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL CHECK (kind IN ('fine', 'bonus')),
  date TEXT NOT NULL
    CHECK (date GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]'),
  cents INTEGER NOT NULL CHECK (cents BETWEEN 1 AND 1000000),
  concept TEXT NOT NULL CHECK (length(concept) BETWEEN 1 AND 60),
  status TEXT NOT NULL CHECK (status IN ('pending', 'closed', 'cancelled')),
  closed_on TEXT
    CHECK (closed_on IS NULL
      OR closed_on GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]'),
  CHECK ((status = 'closed') = (closed_on IS NOT NULL))
)''');

/// Formato v4 (008): movimientos de las horas guardadas. Se añade a la v3 sin
/// tocar sus datos. Medias horas entre 0,5 y 999 h; solo un cobro lleva
/// importe.
Future<void> createSchemaV4(DatabaseExecutor db) => db.execute('''
CREATE TABLE saved_moves (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  box TEXT NOT NULL CHECK (box IN ('company', 'own')),
  kind TEXT NOT NULL CHECK (kind IN ('before', 'setAside', 'timeOff', 'paid')),
  date TEXT NOT NULL
    CHECK (date GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]'),
  minutes INTEGER NOT NULL
    CHECK (minutes BETWEEN 30 AND 59940 AND minutes % 30 = 0),
  note TEXT CHECK (note IS NULL OR length(note) BETWEEN 1 AND 60),
  cents INTEGER CHECK (cents IS NULL OR cents BETWEEN 0 AND 100000000),
  CHECK ((kind = 'paid') = (cents IS NOT NULL))
)''');

/// Formato v5 (010): vacaciones. Se añade a la v4 sin tocar sus datos. Cada
/// día marcado pertenece al año de su fecha o al anterior; los ajustes son
/// una sola fila y lo generado va en medios días.
Future<void> createSchemaV5(DatabaseExecutor db) async {
  await db.execute('''
CREATE TABLE vacation_days (
  date TEXT NOT NULL PRIMARY KEY
    CHECK (date GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]'),
  year INTEGER NOT NULL
    CHECK (year = CAST(substr(date, 1, 4) AS INTEGER)
      OR year = CAST(substr(date, 1, 4) AS INTEGER) - 1)
)''');
  await db.execute('''
CREATE TABLE vacation_settings (
  id INTEGER NOT NULL PRIMARY KEY CHECK (id = 1),
  first_year INTEGER NOT NULL CHECK (first_year BETWEEN 2020 AND 2200),
  first_half_days INTEGER NOT NULL CHECK (first_half_days BETWEEN 0 AND 120),
  yearly_half_days INTEGER NOT NULL CHECK (yearly_half_days BETWEEN 0 AND 120)
)''');
  await db.execute('''
CREATE TABLE vacation_years (
  year INTEGER NOT NULL PRIMARY KEY CHECK (year BETWEEN 2020 AND 2200),
  half_days INTEGER NOT NULL CHECK (half_days BETWEEN 0 AND 120)
)''');
}

/// Formato v6 (012): medio día de vacaciones. Los días que ya había quedan
/// como días enteros (RF-13).
Future<void> createSchemaV6(DatabaseExecutor db) => db.execute(
  'ALTER TABLE vacation_days ADD COLUMN half INTEGER NOT NULL DEFAULT 0 '
  'CHECK (half IN (0, 1))',
);

/// Formato v7 (016): meses del Excel, solo con su total (sin días). Se añade
/// a la v6 sin tocar sus datos. Hasta 31 días de 24 horas por tipo.
Future<void> createSchemaV7(DatabaseExecutor db) => db.execute('''
CREATE TABLE imported_months (
  month TEXT NOT NULL PRIMARY KEY
    CHECK (month GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]'),
  normal_minutes INTEGER NOT NULL CHECK (normal_minutes BETWEEN 0 AND 44640),
  festive_minutes INTEGER NOT NULL CHECK (festive_minutes BETWEEN 0 AND 44640),
  CHECK (normal_minutes + festive_minutes > 0)
)''');

/// Formato v8 (019): pronto pago y «la paga la empresa» en las multas. Las
/// que ya había quedan con los dos apagados.
Future<void> createSchemaV8(DatabaseExecutor db) async {
  await db.execute(
    'ALTER TABLE extras ADD COLUMN early_payment INTEGER NOT NULL DEFAULT 0 '
    'CHECK (early_payment IN (0, 1))',
  );
  await db.execute(
    'ALTER TABLE extras ADD COLUMN company_pays INTEGER NOT NULL DEFAULT 0 '
    'CHECK (company_pays IN (0, 1))',
  );
}
