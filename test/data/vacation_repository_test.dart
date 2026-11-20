import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_database.dart';
import 'package:horas_y_vacaciones/data/vacation_repository.dart';
import 'package:horas_y_vacaciones/domain/vacations.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite real con datos inventados.
void main() {
  late Directory dir;
  late Database db;
  late SqliteVacationRepository repo;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vacation_test_');
    db = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(dir.path, 'horas.db'),
    );
    repo = SqliteVacationRepository(() async => db);
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('ajustes: sin configurar, guardar y sustituir', () async {
    expect(await repo.settings(), isNull);
    final s = VacationSettings(
      firstYear: 2021,
      firstHalfDays: 23,
      overrides: {2024: 40, 2025: 42},
    );
    await repo.saveSettings(s);
    expect(await repo.settings(), s);
    final other = s.copyWith(yearlyHalfDays: 46, overrides: {2023: 44});
    await repo.saveSettings(other);
    expect(await repo.settings(), other);
  });

  test('marcar, cambiar de año y desmarcar', () async {
    final d = VacationDay(DateTime(2026, 1, 2), 2025);
    await repo.saveDay(d);
    await repo.saveDay(VacationDay(DateTime(2025, 8, 4), 2025));
    expect(await repo.days(), [VacationDay(DateTime(2025, 8, 4), 2025), d]);
    await repo.saveDay(VacationDay(DateTime(2026, 1, 2), 2026));
    expect((await repo.days()).last.year, 2026);
    await repo.deleteDay(DateTime(2026, 1, 2));
    await repo.deleteDay(DateTime(2026, 1, 3)); // no estaba
    expect(await repo.days(), hasLength(1));
  });
}
