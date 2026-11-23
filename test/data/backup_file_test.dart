import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_database.dart';
import 'package:horas_y_vacaciones/data/backup_file.dart';
import 'package:horas_y_vacaciones/data/day_entry_repository.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite real y archivos reales en una carpeta temporal, con datos inventados.
void main() {
  late Database db;
  late SqliteDayEntryRepository repo;
  late Directory dir;
  final factory = databaseFactoryFfi;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('copias_test_');
    db = await openAppDatabase(factory: factory, path: inMemoryDatabasePath);
    repo = SqliteDayEntryRepository(
      () async => db,
      clock: () => DateTime.utc(2026, 11, 6),
    );
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  String path(String name) => p.join(dir.path, name);

  DayEntry entry(
    int d,
    int minutes, {
    DayKind kind = DayKind.normal,
    String? reason,
  }) => DayEntry(
    date: DateTime(2026, 11, d),
    minutes: minutes,
    kind: kind,
    reason: reason,
  );

  /// Una base «ajena» con el SQL que se quiera, sin las comprobaciones de la app.
  Future<String> foreign(
    String name,
    List<String> sql, {
    int version = 1,
  }) async {
    final file = path(name);
    final f = await factory.openDatabase(file);
    for (final s in sql) {
      await f.execute(s);
    }
    await f.execute('PRAGMA user_version = $version');
    await f.close();
    return file;
  }

  const looseTable =
      'CREATE TABLE day_entries (date TEXT, minutes INTEGER, kind TEXT, '
      'reason TEXT, updated_at TEXT)';
  const goodRow =
      "INSERT INTO day_entries VALUES ('2026-11-03', 60, 'normal', NULL, 'x')";

  Future<void> expectProblem(String file, BackupProblem problem) => expectLater(
    readBackupFile(file, factory: factory),
    throwsA(
      isA<BackupException>().having((e) => e.problem, 'problem', problem),
    ),
  );

  group('createBackupFile', () {
    test('crea un archivo con los mismos días, motivos y marcas', () async {
      await repo.save(entry(3, 150, reason: 'Inventario'));
      await repo.save(entry(1, 60, kind: DayKind.festive));
      final file = path('copia.db');

      await createBackupFile(db, file, factory: factory);

      final days = await readBackupFile(file, factory: factory);
      expect(days.map((d) => d.entry), [
        entry(1, 60, kind: DayKind.festive),
        entry(3, 150, reason: 'Inventario'),
      ]);
      expect(days.first.updatedAt, '2026-11-06T00:00:00.000Z');
    });

    test('una base vacía también se copia', () async {
      final file = path('vacia.db');
      await createBackupFile(db, file, factory: factory);
      expect(await readBackupFile(file, factory: factory), isEmpty);
    });

    test('no pisa ni borra un archivo que ya existe', () async {
      final file = path('copia.db');
      await File(file).writeAsString('algo mío');
      await expectLater(
        createBackupFile(db, file, factory: factory),
        throwsStateError,
      );
      expect(await File(file).readAsString(), 'algo mío');
    });
  });

  group('readBackupFile', () {
    test('no modifica el archivo', () async {
      await repo.save(entry(3, 150));
      final file = path('copia.db');
      await createBackupFile(db, file, factory: factory);
      final before = await File(file).readAsBytes();

      await readBackupFile(file, factory: factory);

      expect(await File(file).readAsBytes(), before);
    });

    test('un archivo que no es una base de datos', () async {
      final file = path('texto.db');
      await File(file).writeAsString('hola, esto no es una copia');
      await expectProblem(file, BackupProblem.notABackup);
    });

    test('un archivo vacío o que no existe', () async {
      final file = path('vacio.db');
      await File(file).writeAsBytes([]);
      await expectProblem(file, BackupProblem.notABackup);
      await expectProblem(path('no-existe.db'), BackupProblem.notABackup);
    });

    test('una copia cortada a la mitad', () async {
      for (var d = 1; d <= 28; d++) {
        await repo.save(entry(d, 60, reason: 'Motivo número $d'));
      }
      final file = path('copia.db');
      await createBackupFile(db, file, factory: factory);
      final bytes = await File(file).readAsBytes();
      final cut = path('cortada.db');
      await File(cut).writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
      await expectProblem(cut, BackupProblem.notABackup);
    });

    test('una base de datos ajena, sin la tabla de días', () async {
      final file = await foreign('ajena.db', ['CREATE TABLE otra (a TEXT)']);
      await expectProblem(file, BackupProblem.notABackup);
    });

    test('una base sin versión (no es de esta app)', () async {
      final file = await foreign('sin.db', [looseTable, goodRow], version: 0);
      await expectProblem(file, BackupProblem.notABackup);
    });

    test('de una versión más nueva', () async {
      final file = await foreign('nueva.db', [
        looseTable,
        goodRow,
      ], version: databaseVersion + 1);
      await expectProblem(file, BackupProblem.tooNew);
    });

    test('minutos imposibles', () async {
      final file = await foreign('m.db', [
        looseTable,
        "INSERT INTO day_entries VALUES ('2026-11-03', 0, 'normal', NULL, 'x')",
      ]);
      await expectProblem(file, BackupProblem.badRows);
    });

    test('fecha imposible', () async {
      final file = await foreign('f.db', [
        looseTable,
        "INSERT INTO day_entries VALUES ('2026-02-30', 60, 'normal', NULL, 'x')",
      ]);
      await expectProblem(file, BackupProblem.badRows);
    });

    test('tipo desconocido', () async {
      final file = await foreign('t.db', [
        looseTable,
        "INSERT INTO day_entries VALUES ('2026-11-03', 60, 'raro', NULL, 'x')",
      ]);
      await expectProblem(file, BackupProblem.badRows);
    });

    test('dos filas con la misma fecha', () async {
      final file = await foreign('d.db', [looseTable, goodRow, goodRow]);
      await expectProblem(file, BackupProblem.badRows);
    });

    test('tipos de columna mezclados', () async {
      final file = await foreign('x.db', [
        looseTable,
        "INSERT INTO day_entries VALUES ('2026-11-03', 'mucho', 'normal', NULL, 'x')",
      ]);
      await expectProblem(file, BackupProblem.badRows);
    });

    test('los mensajes explican qué hacer', () {
      for (final problem in BackupProblem.values) {
        expect(BackupException(problem).message, isNotEmpty);
      }
    });
  });

  group('restoreDays', () {
    test('sustituye todos los días por los de la copia', () async {
      await repo.save(entry(1, 60));
      await repo.save(entry(2, 90));
      final other = await factory.openDatabase(
        path('origen.db'),
        options: OpenDatabaseOptions(
          version: databaseVersion,
          onCreate: (d, _) async {
            await createSchemaV1(d);
            await createSchemaV2(d);
            await createSchemaV3(d);
            await createSchemaV4(d);
            await createSchemaV5(d);
            await createSchemaV6(d);
            await createSchemaV7(d);
            await createSchemaV8(d);
            await createSchemaV9(d);
          },
        ),
      );
      final otherRepo = SqliteDayEntryRepository(
        () async => other,
        clock: () => DateTime.utc(2026, 10, 1),
      );
      await otherRepo.save(entry(2, 30, reason: 'Antiguo'));
      await otherRepo.save(entry(9, 120, kind: DayKind.festive));
      final file = path('antigua.db');
      await createBackupFile(other, file, factory: factory);
      await other.close();

      await restoreDays(db, await readBackupFile(file, factory: factory));

      expect(await repo.entriesInMonth(2026, 11), [
        entry(2, 30, reason: 'Antiguo'),
        entry(9, 120, kind: DayKind.festive),
      ]);
      final rows = await db.query('day_entries', where: "date = '2026-11-02'");
      expect(rows.single['updated_at'], '2026-10-01T00:00:00.000Z');
    });

    test('restaurar una copia sin días vacía los datos', () async {
      await repo.save(entry(1, 60));
      await restoreDays(db, const []);
      expect(await repo.entriesInMonth(2026, 11), isEmpty);
    });

    test('si algo falla a medias, no cambia nada', () async {
      await repo.save(entry(1, 60));
      final repeated = BackupDay(entry(5, 30), 'x');
      await expectLater(
        restoreDays(db, [repeated, repeated]),
        throwsA(isA<Exception>()),
      );
      expect(await repo.entriesInMonth(2026, 11), [entry(1, 60)]);
    });
  });
}
