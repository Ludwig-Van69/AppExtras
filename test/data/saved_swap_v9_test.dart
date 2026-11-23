import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_database.dart';
import 'package:horas_y_vacaciones/data/backup_file.dart';
import 'package:horas_y_vacaciones/data/saved_hours_repository.dart';
import 'package:horas_y_vacaciones/domain/saved_hours.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite real con datos inventados (022).
void main() {
  late Directory dir;
  final factory = databaseFactoryFfi;

  setUpAll(sqfliteFfiInit);
  setUp(() async => dir = await Directory.systemTemp.createTemp('swap_test_'));
  tearDown(() => dir.delete(recursive: true));

  final swap = SavedMove(
    kind: SavedMoveKind.swap,
    date: DateTime(2026, 11, 10),
    minutes: 180,
    note: 'Puente',
    dayOff: DateTime(2026, 12, 7),
  );

  test('v8 → v9 hace copia y conserva los movimientos tal cual '
      '(RF-13)', () async {
    final file = p.join(dir.path, 'v8.db');
    final v8 = await openAppDatabase(factory: factory, path: file, version: 8);
    await v8.insert('saved_moves', {
      'box': 'own',
      'kind': 'paid',
      'date': '2026-03-04',
      'minutes': 600,
      'note': 'Cobro',
      'cents': 15000,
    });
    await v8.insert('saved_moves', {
      'box': 'company',
      'kind': 'setAside',
      'date': '2026-03-05',
      'minutes': 90,
    });
    await v8.close();

    var copied = false;
    final db = await openAppDatabase(
      factory: factory,
      path: file,
      backupBeforeUpgrade: (_) async => copied = true,
    );
    expect(copied, isTrue);
    expect(await db.getVersion(), 9);
    final moves = await SqliteSavedHoursRepository(() async => db).all();
    expect(moves, [
      SavedMove(
        id: 1,
        box: SavedBox.own,
        kind: SavedMoveKind.paid,
        date: DateTime(2026, 3, 4),
        minutes: 600,
        note: 'Cobro',
        cents: 15000,
      ),
      SavedMove(
        id: 2,
        box: SavedBox.company,
        kind: SavedMoveKind.setAside,
        date: DateTime(2026, 3, 5),
        minutes: 90,
      ),
    ]);
    // Los nuevos siguen numerándose después de los que había.
    final added = await SqliteSavedHoursRepository(() async => db).save(swap);
    expect(added.id, 3);
    await db.close();
  });

  test('un cambio por libre se guarda y se lee, también en una copia '
      '(RF-1, RF-14)', () async {
    final file = p.join(dir.path, 'v9.db');
    final db = await openAppDatabase(factory: factory, path: file);
    final repo = SqliteSavedHoursRepository(() async => db);
    final saved = await repo.save(swap);
    expect((await repo.all()).single, saved);
    expect(saved.box, isNull);
    expect(saved.dayOff, DateTime(2026, 12, 7));

    final copy = p.join(dir.path, 'copia.db');
    await createBackupFile(db, copy, factory: factory);
    await db.close();
    final data = await readBackupData(copy, factory: factory);
    expect(data.extras!.savedMoves!.single, saved);
  });

  test(
    'la base rechaza un cambio con cajón o un día libre en otro tipo',
    () async {
      final db = await openAppDatabase(
        factory: factory,
        path: p.join(dir.path, 'malo.db'),
      );
      Map<String, Object?> row(Map<String, Object?> extra) => {
        'kind': 'swap',
        'date': '2026-11-10',
        'minutes': 60,
        ...extra,
      };
      await expectLater(
        db.insert('saved_moves', row({'box': 'own'})),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.insert(
          'saved_moves',
          row({'kind': 'timeOff', 'box': 'own', 'day_off': '2026-11-20'}),
        ),
        throwsA(isA<DatabaseException>()),
      );
      await db.close();
    },
  );
}
