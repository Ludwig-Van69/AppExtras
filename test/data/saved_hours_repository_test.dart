import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_database.dart';
import 'package:horas_y_vacaciones/data/saved_hours_repository.dart';
import 'package:horas_y_vacaciones/domain/saved_hours.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite real con datos inventados.
void main() {
  late Directory dir;
  late Database db;
  late SqliteSavedHoursRepository repo;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('saved_test_');
    db = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(dir.path, 'horas.db'),
    );
    repo = SqliteSavedHoursRepository(() async => db);
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('crear, leer, cambiar, borrar y volver a crear con su id', () async {
    final before = await repo.save(
      SavedMove(
        box: SavedBox.company,
        kind: SavedMoveKind.before,
        date: DateTime(2025, 1, 1),
        minutes: 16 * 60,
        note: 'De otros años',
      ),
    );
    final paid = await repo.save(
      SavedMove(
        box: SavedBox.company,
        kind: SavedMoveKind.paid,
        date: DateTime(2026, 11, 5),
        minutes: 120,
        cents: 3000,
      ),
    );
    expect(before.id, isNotNull);
    expect(paid.id, isNot(before.id));
    expect(await repo.all(), [before, paid]);

    final changed = await repo.save(
      SavedMove(
        id: before.id,
        box: SavedBox.own,
        kind: SavedMoveKind.before,
        date: DateTime(2025, 1, 1),
        minutes: 39 * 60,
      ),
    );
    expect(changed.id, before.id);
    expect(await repo.all(), [changed, paid]);

    await repo.delete(paid.id!);
    expect(await repo.all(), [changed]);
    await repo.save(paid); // Deshacer
    expect(await repo.all(), [changed, paid]);
  });
}
