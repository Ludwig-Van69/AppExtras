import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_database.dart';
import 'package:horas_y_vacaciones/data/backup_file.dart';
import 'package:horas_y_vacaciones/data/extras_repository.dart';
import 'package:horas_y_vacaciones/domain/extras.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite real con datos inventados (019).
void main() {
  late Directory dir;
  final factory = databaseFactoryFfi;

  setUpAll(sqfliteFfiInit);
  setUp(() async => dir = await Directory.systemTemp.createTemp('fines_test_'));
  tearDown(() => dir.delete(recursive: true));

  Map<String, Object?> oldFine() => {
    'kind': 'fine',
    'date': '2026-03-04',
    'cents': 15000,
    'concept': 'Aparcamiento',
    'status': 'pending',
  };

  test('v7 → v8 hace copia y deja las multas con los dos apagados '
      '(019, RF-6)', () async {
    final file = p.join(dir.path, 'v7.db');
    final v7 = await openAppDatabase(factory: factory, path: file, version: 7);
    await v7.insert('extras', oldFine());
    await v7.close();

    var copied = false;
    final db = await openAppDatabase(
      factory: factory,
      path: file,
      version: 8,
      backupBeforeUpgrade: (_) async => copied = true,
    );
    expect(copied, isTrue);
    expect(await db.getVersion(), 8);
    final fine = (await SqliteExtrasRepository(() async => db).all()).single;
    expect(fine.cents, 15000);
    expect(fine.earlyPayment, isFalse);
    expect(fine.companyPays, isFalse);
    await db.close();
  });

  test('se guardan y se leen los dos interruptores', () async {
    final db = await openAppDatabase(
      factory: factory,
      path: p.join(dir.path, 'v8.db'),
    );
    final repo = SqliteExtrasRepository(() async => db);
    final saved = await repo.save(
      ExtraItem(
        type: ExtraType.fine,
        date: DateTime(2026, 3, 4),
        cents: 15000,
        concept: 'Aparcamiento',
        earlyPayment: true,
        companyPays: true,
      ),
    );
    final read = (await repo.all()).single;
    expect(read, saved);
    expect(read.earlyPayment, isTrue);
    expect(read.companyPays, isTrue);
    await db.close();
  });

  test('una copia v7 se lee con los dos apagados (019, RF-6)', () async {
    final file = p.join(dir.path, 'copia-v7.db');
    final v7 = await openAppDatabase(factory: factory, path: file, version: 7);
    await v7.insert('extras', oldFine());
    await v7.close();
    final data = await readBackupData(file, factory: factory);
    final fine = data.extras!.items!.single;
    expect(fine.earlyPayment, isFalse);
    expect(fine.companyPays, isFalse);
  });

  test('la base rechaza valores que no son 0 o 1', () async {
    final db = await openAppDatabase(
      factory: factory,
      path: p.join(dir.path, 'malo.db'),
    );
    await expectLater(
      db.insert('extras', {...oldFine(), 'early_payment': 2}),
      throwsA(isA<DatabaseException>()),
    );
    await db.close();
  });
}
