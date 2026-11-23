import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_database.dart';
import 'package:horas_y_vacaciones/data/day_entry_repository.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite real, en memoria, con datos inventados.
void main() {
  late Database db;
  late SqliteDayEntryRepository repo;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = SqliteDayEntryRepository(
      () async => db,
      clock: () => DateTime.utc(2026, 11, 6),
    );
  });
  tearDown(() => db.close());

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

  test('crea la base en la versión 1', () async {
    expect(await db.getVersion(), databaseVersion);
    expect(databaseVersion, 9);
  });

  test('guarda y lee un día con su tipo y motivo (RF-7, RF-13)', () async {
    final e = entry(6, 150, kind: DayKind.festive, reason: 'Taller Norte');
    await repo.save(e);
    expect(await repo.entriesInMonth(2026, 11), [e]);
  });

  test(
    'guardar otra vez el mismo día sustituye, no suma (RF-7, RF-27)',
    () async {
      await repo.save(entry(6, 150));
      await repo.save(entry(6, 60, reason: 'Inventario'));
      final list = await repo.entriesInMonth(2026, 11);
      expect(list, [entry(6, 60, reason: 'Inventario')]);
    },
  );

  test('la base impide dos registros del mismo día (RF-27)', () async {
    final row = {
      'date': '2026-11-06',
      'minutes': 60,
      'kind': 'normal',
      'updated_at': 'x',
    };
    await db.insert('day_entries', row);
    expect(
      () => db.insert('day_entries', row),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('la base rechaza datos imposibles aunque el código fallara', () async {
    Future<void> raw(Map<String, Object?> changes) => db.insert('day_entries', {
      'date': '2026-11-06',
      'minutes': 60,
      'kind': 'normal',
      'updated_at': 'x',
      ...changes,
    });
    final fails = throwsA(isA<DatabaseException>());
    expect(() => raw({'minutes': 0}), fails);
    expect(() => raw({'minutes': 1441}), fails);
    expect(() => raw({'kind': 'otro'}), fails);
    expect(() => raw({'reason': ''}), fails);
    expect(() => raw({'reason': 'a' * 61}), fails);
    expect(() => raw({'date': '6/11/2026'}), fails);
  });

  test('lee solo el mes pedido, ordenado por fecha', () async {
    await repo.save(entry(30, 60));
    await repo.save(entry(1, 90));
    await repo.save(
      DayEntry(date: DateTime(2026, 10, 31), minutes: 30, kind: DayKind.normal),
    );
    await repo.save(
      DayEntry(date: DateTime(2026, 12, 1), minutes: 30, kind: DayKind.normal),
    );
    final list = await repo.entriesInMonth(2026, 11);
    expect(list.map((e) => e.date.day), [1, 30]);
  });

  test(
    'borra el día entero, y borrar uno que no existe no falla (RF-18)',
    () async {
      await repo.save(entry(6, 150, reason: 'Taller'));
      await repo.delete(DateTime(2026, 11, 6));
      await repo.delete(DateTime(2026, 11, 7));
      expect(await repo.entriesInMonth(2026, 11), isEmpty);
    },
  );

  test('cuenta los usos de cada motivo (RF-16)', () async {
    await repo.save(entry(2, 60, reason: 'Taller'));
    await repo.save(entry(3, 60, reason: 'Taller'));
    await repo.save(entry(4, 60, reason: 'Inventario'));
    await repo.save(entry(5, 60));
    expect(await repo.reasonUsage(), {'Taller': 2, 'Inventario': 1});
  });

  test('una fila dañada da error, no un dato inventado (RF-26)', () async {
    await db.execute('PRAGMA ignore_check_constraints = ON');
    await db.insert('day_entries', {
      'date': '2026-11-06',
      'minutes': 60,
      'kind': 'otro',
      'updated_at': 'x',
    });
    expect(() => repo.entriesInMonth(2026, 11), throwsArgumentError);
  });

  test(
    'si no se puede abrir, lo vuelve a intentar en la siguiente llamada',
    () async {
      var attempts = 0;
      final flaky = SqliteDayEntryRepository(() async {
        attempts++;
        if (attempts == 1) throw StateError('no se pudo abrir');
        return db;
      });
      await expectLater(flaky.entriesInMonth(2026, 11), throwsStateError);
      expect(await flaky.entriesInMonth(2026, 11), isEmpty);
      expect(attempts, 2);
    },
  );
}
