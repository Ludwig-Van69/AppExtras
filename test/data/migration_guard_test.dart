import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Aún no hay formato v2: se simula pidiendo abrir con versión 2 un archivo v1.
void main() {
  late Directory dir;
  late String file;
  final factory = databaseFactoryFfi;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('migracion_test_');
    file = p.join(dir.path, 'horas.db');
  });
  tearDown(() => dir.delete(recursive: true));

  Future<void> createV1() async {
    final db = await openAppDatabase(factory: factory, path: file, version: 1);
    await db.close();
  }

  test('storedVersion: nulo si no existe, y la versión si existe', () async {
    expect(await storedVersion(file, factory: factory), isNull);
    await createV1();
    expect(await storedVersion(file, factory: factory), 1);
  });

  test('una base nueva no pide copia previa', () async {
    var calls = 0;
    final db = await openAppDatabase(
      factory: factory,
      path: file,
      backupBeforeUpgrade: (_) async => calls++,
    );
    await db.close();
    expect(calls, 0);
  });

  test('misma versión: no pide copia previa', () async {
    await (await openAppDatabase(factory: factory, path: file)).close();
    var calls = 0;
    final db = await openAppDatabase(
      factory: factory,
      path: file,
      backupBeforeUpgrade: (_) async => calls++,
    );
    await db.close();
    expect(calls, 0);
  });

  test('cambio de formato: primero la copia y luego se actualiza', () async {
    await createV1();
    final paths = <String>[];
    final db = await openAppDatabase(
      factory: factory,
      path: file,
      version: 2,
      backupBeforeUpgrade: (path) async => paths.add(path),
    );
    expect(await db.getVersion(), 2);
    await db.close();
    expect(paths, [file]);
  });

  test('si la copia previa falla, el formato no cambia', () async {
    await createV1();
    await expectLater(
      openAppDatabase(
        factory: factory,
        path: file,
        version: 2,
        backupBeforeUpgrade: (_) async => throw const FileSystemException(),
      ),
      throwsA(isA<MigrationBlockedException>()),
    );
    expect(await storedVersion(file, factory: factory), 1);
  });

  test('v1 → v2 conserva todos los días y crea las tablas nuevas', () async {
    final v1 = await openAppDatabase(factory: factory, path: file, version: 1);
    await v1.insert('day_entries', {
      'date': '2026-11-03',
      'minutes': 150,
      'kind': 'normal',
      'reason': 'Inventario',
      'updated_at': '2026-11-03T10:00:00Z',
    });
    await v1.close();

    final db = await openAppDatabase(factory: factory, path: file, version: 2);
    expect(await db.getVersion(), 2);
    final days = await db.query('day_entries');
    expect(days.single['minutes'], 150);
    expect(days.single['reason'], 'Inventario');
    expect(await db.query('rates'), isEmpty);
    expect(await db.query('months'), isEmpty);
    await db.close();
  });

  test('el formato v2 rechaza datos imposibles', () async {
    final db = await openAppDatabase(factory: factory, path: file);
    for (final bad in [
      {'kind': 'normal', 'start_date': '2026-01-01', 'cents': 0},
      {'kind': 'raro', 'start_date': '2026-01-01', 'cents': 1500},
      {'kind': 'normal', 'start_date': 'ayer', 'cents': 1500},
    ]) {
      await expectLater(db.insert('rates', bad), throwsA(anything));
    }
    await expectLater(
      db.insert('months', {'month': '2026-11', 'paid_on': '2026-12-01'}),
      throwsA(anything), // cobrado sin entregar
    );
    await db.close();
  });

  test(
    'v2 → v3 conserva días, tarifas y meses y crea la tabla nueva',
    () async {
      final v2 = await openAppDatabase(
        factory: factory,
        path: file,
        version: 2,
      );
      await v2.insert('day_entries', {
        'date': '2026-10-03',
        'minutes': 90,
        'kind': 'festive',
        'reason': null,
        'updated_at': '2026-10-03T10:00:00Z',
      });
      await v2.insert('rates', {
        'kind': 'normal',
        'start_date': '2020-01-01',
        'cents': 1500,
      });
      await v2.insert('months', {
        'month': '2026-10',
        'delivered_on': '2026-11-02',
      });
      await v2.close();

      var copied = false;
      final db = await openAppDatabase(
        factory: factory,
        path: file,
        version: 3,
        backupBeforeUpgrade: (_) async => copied = true,
      );
      expect(copied, isTrue);
      expect(await db.getVersion(), 3);
      expect((await db.query('day_entries')).single['minutes'], 90);
      expect((await db.query('rates')).single['cents'], 1500);
      expect((await db.query('months')).single['delivered_on'], '2026-11-02');
      expect(await db.query('extras'), isEmpty);
      await db.close();
    },
  );

  test('el formato v3 rechaza multas y extras imposibles', () async {
    final db = await openAppDatabase(factory: factory, path: file);
    Map<String, Object?> ok() => {
      'kind': 'fine',
      'date': '2026-11-02',
      'cents': 5000,
      'concept': 'Multa aparcamiento',
      'status': 'pending',
      'closed_on': null,
    };
    await db.insert('extras', ok());
    for (final change in <Map<String, Object?>>[
      {'kind': 'raro'},
      {'cents': 0},
      {'cents': 1000001},
      {'concept': ''},
      {'concept': 'x' * 61},
      {'status': 'raro'},
      {'date': 'ayer'},
      {'status': 'closed'}, // cerrada sin fecha
      {'closed_on': '2026-11-03'}, // pendiente con fecha
    ]) {
      await expectLater(
        db.insert('extras', {...ok(), ...change}),
        throwsA(anything),
        reason: '$change',
      );
    }
    await db.close();
  });

  test('MigrationBlockedException explica qué hacer', () {
    expect(const MigrationBlockedException(1, 2).message, contains('copia'));
  });

  test('v3 → v4 conserva todo y crea la tabla de horas guardadas', () async {
    final v3 = await openAppDatabase(factory: factory, path: file, version: 3);
    await v3.insert('day_entries', {
      'date': '2026-10-03',
      'minutes': 90,
      'kind': 'normal',
      'reason': null,
      'updated_at': '2026-10-03T10:00:00Z',
    });
    await v3.insert('rates', {
      'kind': 'normal',
      'start_date': '2020-01-01',
      'cents': 1500,
    });
    await v3.insert('months', {
      'month': '2026-10',
      'delivered_on': '2026-11-02',
    });
    await v3.insert('extras', {
      'kind': 'bonus',
      'date': '2026-11-02',
      'cents': 5000,
      'concept': 'Dieta viaje',
      'status': 'pending',
      'closed_on': null,
    });
    await v3.close();

    var copied = false;
    final db = await openAppDatabase(
      factory: factory,
      path: file,
      version: 4,
      backupBeforeUpgrade: (_) async => copied = true,
    );
    expect(copied, isTrue);
    expect(await db.getVersion(), 4);
    expect((await db.query('day_entries')).single['minutes'], 90);
    expect((await db.query('rates')).single['cents'], 1500);
    expect((await db.query('months')).single['delivered_on'], '2026-11-02');
    expect((await db.query('extras')).single['cents'], 5000);
    expect(await db.query('saved_moves'), isEmpty);
    await db.close();
  });

  test('el formato v4 rechaza movimientos imposibles', () async {
    final db = await openAppDatabase(factory: factory, path: file);
    Map<String, Object?> ok() => {
      'box': 'own',
      'kind': 'paid',
      'date': '2026-11-02',
      'minutes': 180,
      'note': null,
      'cents': 4500,
    };
    await db.insert('saved_moves', ok());
    await db.insert('saved_moves', {...ok(), 'kind': 'before', 'cents': null});
    for (final change in <Map<String, Object?>>[
      {'box': 'raro'},
      {'kind': 'raro'},
      {'date': 'ayer'},
      {'minutes': 0},
      {'minutes': 45},
      {'minutes': 59970},
      {'note': ''},
      {'note': 'x' * 61},
      {'cents': null}, // cobro sin importe
      {'kind': 'timeOff'}, // salida con importe
      {'cents': -1},
    ]) {
      await expectLater(
        db.insert('saved_moves', {...ok(), ...change}),
        throwsA(anything),
        reason: '$change',
      );
    }
    await db.close();
  });

  test('v4 → v5 conserva todo y crea las tablas de vacaciones', () async {
    final v4 = await openAppDatabase(factory: factory, path: file, version: 4);
    await v4.insert('day_entries', {
      'date': '2026-10-03',
      'minutes': 90,
      'kind': 'normal',
      'reason': null,
      'updated_at': '2026-10-03T10:00:00Z',
    });
    await v4.insert('saved_moves', {
      'box': 'own',
      'kind': 'before',
      'date': '2025-01-01',
      'minutes': 600,
    });
    await v4.close();

    var copied = false;
    final db = await openAppDatabase(
      factory: factory,
      path: file,
      version: 5,
      backupBeforeUpgrade: (_) async => copied = true,
    );
    expect(copied, isTrue);
    expect(await db.getVersion(), 5);
    expect((await db.query('day_entries')).single['minutes'], 90);
    expect((await db.query('saved_moves')).single['minutes'], 600);
    expect(await db.query('vacation_days'), isEmpty);
    expect(await db.query('vacation_settings'), isEmpty);
    expect(await db.query('vacation_years'), isEmpty);
    await db.close();
  });

  test(
    'v5 → v6 hace copia y deja los días como enteros (012, RF-13)',
    () async {
      final v5 = await openAppDatabase(
        factory: factory,
        path: file,
        version: 5,
      );
      await v5.insert('vacation_days', {'date': '2026-01-02', 'year': 2025});
      await v5.insert('vacation_days', {'date': '2026-06-01', 'year': 2026});
      await v5.insert('vacation_settings', {
        'id': 1,
        'first_year': 2021,
        'first_half_days': 23,
        'yearly_half_days': 44,
      });
      await v5.close();

      var copied = false;
      final db = await openAppDatabase(
        factory: factory,
        path: file,
        version: 6,
        backupBeforeUpgrade: (_) async => copied = true,
      );
      expect(copied, isTrue);
      expect(await db.getVersion(), 6);
      final rows = await db.query('vacation_days', orderBy: 'date');
      expect([for (final r in rows) r['half']], [0, 0]);
      expect((await db.query('vacation_settings')).single['first_year'], 2021);
      await db.close();
    },
  );

  test('el formato v6 solo admite medio día 0 o 1', () async {
    final db = await openAppDatabase(factory: factory, path: file);
    await db.insert('vacation_days', {
      'date': '2026-06-01',
      'year': 2026,
      'half': 1,
    });
    for (final half in [2, -1, null]) {
      await expectLater(
        db.insert('vacation_days', {
          'date': '2026-06-02',
          'year': 2026,
          'half': half,
        }),
        throwsA(anything),
        reason: '$half',
      );
    }
    await db.close();
  });

  test('el formato v5 rechaza vacaciones imposibles', () async {
    final db = await openAppDatabase(factory: factory, path: file);
    await db.insert('vacation_days', {'date': '2026-01-02', 'year': 2025});
    await db.insert('vacation_days', {'date': '2026-06-01', 'year': 2026});
    for (final row in <Map<String, Object?>>[
      {'date': '2026-06-02', 'year': 2024},
      {'date': '2026-06-02', 'year': 2027},
      {'date': 'ayer', 'year': 2026},
      {'date': '2026-01-02', 'year': 2026}, // repetido
    ]) {
      await expectLater(
        db.insert('vacation_days', row),
        throwsA(anything),
        reason: '$row',
      );
    }
    Map<String, Object?> ok() => {
      'id': 1,
      'first_year': 2021,
      'first_half_days': 23,
      'yearly_half_days': 44,
    };
    for (final change in <Map<String, Object?>>[
      {'id': 2},
      {'first_year': 2019},
      {'first_half_days': 121},
      {'yearly_half_days': -1},
    ]) {
      await expectLater(
        db.insert('vacation_settings', {...ok(), ...change}),
        throwsA(anything),
        reason: '$change',
      );
    }
    await db.insert('vacation_settings', ok());
    await expectLater(
      db.insert('vacation_years', {'year': 2024, 'half_days': 121}),
      throwsA(anything),
    );
    await db.close();
  });
}
