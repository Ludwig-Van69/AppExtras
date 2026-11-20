import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_database.dart';
import 'package:horas_y_vacaciones/data/extras_repository.dart';
import 'package:horas_y_vacaciones/domain/extras.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite real con datos inventados.
void main() {
  late Directory dir;
  late Database db;
  late SqliteExtrasRepository repo;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('extras_test_');
    db = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(dir.path, 'horas.db'),
    );
    repo = SqliteExtrasRepository(() async => db);
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('crear, leer, cambiar, borrar y volver a crear con su id', () async {
    final fine = await repo.save(
      ExtraItem(
        type: ExtraType.fine,
        date: DateTime(2026, 11, 2),
        cents: 10000,
        concept: 'Multa velocidad',
      ),
    );
    final bonus = await repo.save(
      ExtraItem(
        type: ExtraType.bonus,
        date: DateTime(2026, 11, 5),
        cents: 5000,
        concept: 'Dieta viaje',
      ),
    );
    expect(fine.id, isNotNull);
    expect(bonus.id, isNot(fine.id));
    expect(await repo.all(), [fine, bonus]);

    final closed = await repo.save(
      fine.withStatus(ExtraStatus.closed, on: DateTime(2026, 11, 30)),
    );
    expect(closed.id, fine.id);
    expect(await repo.all(), [closed, bonus]);

    await repo.delete(bonus.id!);
    expect(await repo.all(), [closed]);
    await repo.save(bonus); // Deshacer
    expect(await repo.all(), [closed, bonus]);
  });
}
