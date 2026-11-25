import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_database.dart';
import 'package:horas_y_vacaciones/data/backup_file.dart';
import 'package:horas_y_vacaciones/data/company_repository.dart';
import 'package:horas_y_vacaciones/data/vacation_repository.dart';
import 'package:horas_y_vacaciones/domain/company.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite real con datos inventados (026).
void main() {
  late Directory dir;
  final factory = databaseFactoryFfi;

  setUpAll(sqfliteFfiInit);
  setUp(
    () async => dir = await Directory.systemTemp.createTemp('company_test_'),
  );
  tearDown(() => dir.delete(recursive: true));

  test('v9 → v10 hace copia, conserva todo y la empresa queda vacía '
      '(RF-10)', () async {
    final file = p.join(dir.path, 'v9.db');
    final v9 = await openAppDatabase(factory: factory, path: file, version: 9);
    await v9.insert('day_entries', {
      'date': '2026-03-04',
      'minutes': 90,
      'kind': 'normal',
      'reason': 'Inventario',
      'updated_at': '2026-03-04T10:00:00Z',
    });
    await v9.insert('vacation_settings', {
      'id': 1,
      'first_year': 2024,
      'first_half_days': 20,
      'yearly_half_days': 44,
    });
    await v9.close();

    var copied = false;
    final db = await openAppDatabase(
      factory: factory,
      path: file,
      backupBeforeUpgrade: (_) async => copied = true,
    );
    expect(copied, isTrue);
    expect(await db.getVersion(), 10);
    expect(await db.query('day_entries'), hasLength(1));
    expect((await readVacationSettings(db))!.yearlyHalfDays, 44);
    expect(
      await SqliteCompanyRepository(() async => db).company(),
      Company.empty,
    );
    await db.close();
  });

  test('guarda, cambia y borra la empresa (RF-1, RF-6)', () async {
    final db = await openAppDatabase(
      factory: factory,
      path: p.join(dir.path, 'a.db'),
    );
    final repo = SqliteCompanyRepository(() async => db);
    final c = Company(name: 'Talleres Ejemplo', start: DateTime(2020, 3, 2));
    await repo.save(c);
    expect(await repo.company(), c);
    await repo.save(c.withName(null));
    expect(await repo.company(), Company(start: DateTime(2020, 3, 2)));
    await repo.save(Company(name: 'Otra'));
    expect(await repo.company(), Company(name: 'Otra'));
    await repo.save(Company.empty);
    expect(await repo.company(), Company.empty);
    expect(await db.query('company'), isEmpty);
    await db.close();
  });

  test('la base no admite una fila imposible', () async {
    final db = await openAppDatabase(
      factory: factory,
      path: p.join(dir.path, 'b.db'),
    );
    expect(
      () => db.insert('company', {'id': 1, 'name': 'a' * 61}),
      throwsA(isA<DatabaseException>()),
    );
    expect(
      () => db.insert('company', {'id': 1}),
      throwsA(isA<DatabaseException>()),
    );
    await db.close();
  });

  test('va en las copias y se restaura (RF-9)', () async {
    final db = await openAppDatabase(
      factory: factory,
      path: p.join(dir.path, 'c.db'),
    );
    final repo = SqliteCompanyRepository(() async => db);
    final c = Company(name: 'Talleres Ejemplo', start: DateTime(2020, 3, 2));
    await repo.save(c);
    final copy = p.join(dir.path, 'copia.db');
    await createBackupFile(db, copy, factory: factory);
    final data = await readBackupData(copy, factory: factory);
    expect(data.extras!.company, c);

    await repo.save(Company(name: 'Otra'));
    await restoreDays(db, data.days, extras: data.extras);
    expect(await repo.company(), c);
    await db.close();
  });

  test('una copia v9 no trae empresa: al restaurar se conserva la actual '
      '(RF-9, RF-10)', () async {
    final old = p.join(dir.path, 'v9.db');
    (await openAppDatabase(factory: factory, path: old, version: 9)).close();
    final data = await readBackupData(old, factory: factory);
    expect(data.extras!.company, isNull);

    final db = await openAppDatabase(
      factory: factory,
      path: p.join(dir.path, 'd.db'),
    );
    final repo = SqliteCompanyRepository(() async => db);
    final c = Company(name: 'Talleres Ejemplo', start: DateTime(2020, 3, 2));
    await repo.save(c);
    await restoreDays(db, data.days, extras: data.extras);
    expect(await repo.company(), c);
    await db.close();
  });
}
