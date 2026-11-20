import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_database.dart';
import 'package:horas_y_vacaciones/data/backup_file.dart';
import 'package:horas_y_vacaciones/data/day_entry_repository.dart';
import 'package:horas_y_vacaciones/data/money_repository.dart';
import 'package:horas_y_vacaciones/domain/csv_export.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/imported_month.dart';
import 'package:horas_y_vacaciones/domain/money.dart';
import 'package:horas_y_vacaciones/ui/money/money_controller.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../fakes/in_memory_day_entry_repository.dart';
import '../fakes/in_memory_money_repository.dart';

/// SQLite real con datos inventados (016).
void main() {
  late Directory dir;
  final factory = databaseFactoryFfi;

  setUpAll(sqfliteFfiInit);
  setUp(() async => dir = await Directory.systemTemp.createTemp('excel_test_'));
  tearDown(() => dir.delete(recursive: true));

  Future<Database> open(String name, {int version = databaseVersion}) =>
      openAppDatabase(
        factory: factory,
        path: p.join(dir.path, name),
        version: version,
      );

  final june22 = ImportedMonth(const YearMonth(2022, 6), 2550, 1470);
  final july22 = ImportedMonth(const YearMonth(2022, 7), 1350, 0);

  Future<void> insert(Database db, ImportedMonth m) =>
      db.insert('imported_months', importedMonthToRow(m));

  test('v6 → v7 hace copia, conserva los datos y crea la tabla vacía '
      '(016, RF-7)', () async {
    final file = p.join(dir.path, 'v6.db');
    final v6 = await openAppDatabase(factory: factory, path: file, version: 6);
    await v6.insert('day_entries', {
      'date': '2026-11-02',
      'minutes': 90,
      'kind': 'normal',
      'updated_at': '2026-11-02T10:00:00.000Z',
    });
    await v6.close();

    var copied = false;
    final db = await openAppDatabase(
      factory: factory,
      path: file,
      version: 7,
      backupBeforeUpgrade: (_) async => copied = true,
    );
    expect(copied, isTrue);
    expect(await db.getVersion(), 7);
    expect((await db.query('day_entries')).single['minutes'], 90);
    expect(await db.query('imported_months'), isEmpty);
    await db.close();
  });

  test('el formato v7 rechaza meses imposibles', () async {
    final db = await open('reglas.db');
    for (final row in [
      {'month': '2022-6', 'normal_minutes': 60, 'festive_minutes': 0},
      {'month': '2022-06', 'normal_minutes': 0, 'festive_minutes': 0},
      {'month': '2022-06', 'normal_minutes': -1, 'festive_minutes': 60},
      {'month': '2022-06', 'normal_minutes': 44641, 'festive_minutes': 0},
    ]) {
      await expectLater(
        db.insert('imported_months', row),
        throwsA(anything),
        reason: '$row',
      );
    }
    await db.close();
  });

  test('el repositorio los lee ordenados', () async {
    final db = await open('repo.db');
    await insert(db, july22);
    await insert(db, june22);
    expect(await SqliteMoneyRepository(() async => db).importedMonths(), [
      june22,
      july22,
    ]);
    await db.close();
  });

  test('una copia v7 los trae y los sustituye; una v6 conserva los de ahora '
      '(016, RF-8)', () async {
    final v6 = await open('origen-v6.db', version: 6);
    final file6 = p.join(dir.path, 'copia-v6.db');
    await createBackupFile(v6, file6, factory: factory);
    await v6.close();

    final v7 = await open('origen-v7.db');
    await insert(v7, june22);
    final file7 = p.join(dir.path, 'copia-v7.db');
    await createBackupFile(v7, file7, factory: factory);
    await v7.close();

    final target = await open('destino.db');
    await insert(target, july22);
    final repo = SqliteMoneyRepository(() async => target);

    final data6 = await readBackupData(file6, factory: factory);
    expect(data6.extras!.importedMonths, isNull);
    await restoreDays(target, data6.days, extras: data6.extras);
    expect(await repo.importedMonths(), [july22]);

    final data7 = await readBackupData(file7, factory: factory);
    expect(data7.extras!.importedMonths, [june22]);
    await restoreDays(target, data7.days, extras: data7.extras);
    expect(await repo.importedMonths(), [june22]);
    await target.close();
  });

  test('el CSV los lleva en su sección (016, RF-9)', () {
    final csv = buildCsv(
      [
        DayEntry(
          date: DateTime(2026, 11, 2),
          minutes: 60,
          kind: DayKind.normal,
        ),
      ],
      imported: [july22, june22],
      months: [
        MonthRecord(
          const YearMonth(2022, 6),
          deliveredOn: DateTime(2022, 6, 30),
          paidOn: DateTime(2022, 6, 30),
        ),
      ],
    );
    final rows = csv.split('\r\n');
    final header = rows.indexOf(
      'Mes del Excel;Horas normales;Horas festivas;Estado',
    );
    expect(header, greaterThan(0));
    expect(rows[header + 1], '06/2022;42,5;24,5;Cobrado');
    expect(rows[header + 2], '07/2022;22,5;0;Abierto');
  });

  test(
    'Resumen los recibe y sabe qué meses vienen del Excel (016, RF-4)',
    () async {
      final store = InMemoryMoneyRepository()..importedList.add(june22);
      final money = MoneyController(
        days: InMemoryDayEntryRepository(),
        money: store,
        clock: () => DateTime(2026, 11, 18),
      );
      await money.load();
      expect(money.overview.months.single.imported!.month, june22);
      expect(money.isImportedMonth(DateTime(2022, 6, 15)), isTrue);
      expect(money.isImportedMonth(DateTime(2022, 7, 1)), isFalse);
      money.dispose();
    },
  );

  test('un día se guarda en la v7 como siempre', () async {
    final db = await open('dias.db');
    final repo = SqliteDayEntryRepository(() async => db);
    final e = DayEntry(
      date: DateTime(2026, 11, 2),
      minutes: 60,
      kind: DayKind.festive,
    );
    await repo.save(e);
    expect(await repo.entriesInMonth(2026, 11), [e]);
    await db.close();
  });
}
