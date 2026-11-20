import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_database.dart';
import 'package:horas_y_vacaciones/data/backup_file.dart';
import 'package:horas_y_vacaciones/data/extras_repository.dart';
import 'package:horas_y_vacaciones/data/saved_hours_repository.dart';
import 'package:horas_y_vacaciones/data/vacation_repository.dart';
import 'package:horas_y_vacaciones/domain/vacations.dart';
import 'package:horas_y_vacaciones/domain/saved_hours.dart';
import 'package:horas_y_vacaciones/data/money_repository.dart';
import 'package:horas_y_vacaciones/domain/extras.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/money.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite real con datos inventados.
void main() {
  late Directory dir;
  final factory = databaseFactoryFfi;

  setUpAll(sqfliteFfiInit);
  setUp(
    () async => dir = await Directory.systemTemp.createTemp('dinero_test_'),
  );
  tearDown(() => dir.delete(recursive: true));

  Future<Database> open(String name, {int version = databaseVersion}) =>
      openAppDatabase(
        factory: factory,
        path: p.join(dir.path, name),
        version: version,
      );

  Rate rate(DayKind k, int m, int d, int cents) =>
      Rate(k, DateTime(2026, m, d), cents);

  group('tarifas', () {
    test('guardar, leer, sustituir y borrar', () async {
      final db = await open('a.db');
      final repo = SqliteMoneyRepository(() async => db);
      await repo.saveRate(rate(DayKind.normal, 1, 1, 1500));
      await repo.saveRate(rate(DayKind.festive, 1, 1, 2000));
      await repo.saveRate(rate(DayKind.normal, 11, 1, 1600));
      expect((await repo.rates()).length, 3);

      await repo.saveRate(rate(DayKind.normal, 11, 1, 1700)); // misma fecha
      final rates = await repo.rates();
      expect(rates.length, 3);
      expect(rates.where((r) => r.cents == 1700).length, 1);

      await repo.deleteRate(DayKind.normal, DateTime(2026, 11, 1));
      await repo.deleteRate(DayKind.normal, DateTime(2030, 1, 1)); // no existe
      expect((await repo.rates()).length, 2);
      await db.close();
    });

    test('cambiar una tarifa de fecha e importe de una vez (021)', () async {
      final db = await open('b.db');
      final repo = SqliteMoneyRepository(() async => db);
      final old = rate(DayKind.normal, 1, 1, 1500);
      await repo.saveRate(old);
      await repo.saveRate(rate(DayKind.festive, 1, 1, 2000));
      await repo.replaceRate(old, rate(DayKind.normal, 7, 1, 1650));
      final rates = await repo.rates();
      expect(rates, hasLength(2));
      expect(
        rates.firstWhere((r) => r.kind == DayKind.normal),
        rate(DayKind.normal, 7, 1, 1650),
      );
      await db.close();
    });
  });

  group('meses', () {
    test('entregado, cobrado y vuelta a abierto', () async {
      final db = await open('b.db');
      final repo = SqliteMoneyRepository(() async => db);
      const m = YearMonth(2026, 10);
      await repo.saveMonth(MonthRecord(m, deliveredOn: DateTime(2026, 11, 2)));
      var rec = (await repo.months()).single;
      expect(rec.status, MonthStatus.delivered);
      expect(rec.deliveredOn, DateTime(2026, 11, 2));

      await repo.saveMonth(
        MonthRecord(
          m,
          deliveredOn: DateTime(2026, 11, 2),
          paidOn: DateTime(2026, 12, 5),
        ),
      );
      rec = (await repo.months()).single;
      expect(rec.status, MonthStatus.paid);
      expect(rec.paidOn, DateTime(2026, 12, 5));

      await repo.saveMonth(MonthRecord(m)); // Abierto: no se guarda nada
      expect(await repo.months(), isEmpty);
      await db.close();
    });
  });

  group('copias con tarifas y meses', () {
    Future<Database> seeded(String name) async {
      final db = await open(name);
      final repo = SqliteMoneyRepository(() async => db);
      await repo.saveRate(rate(DayKind.normal, 1, 1, 1500));
      await repo.saveMonth(
        MonthRecord(const YearMonth(2026, 9), paidOn: DateTime(2026, 10, 9)),
      );
      return db;
    }

    test('la copia lleva tarifas y meses, y restaurar los sustituye', () async {
      final source = await seeded('origen.db');
      final file = p.join(dir.path, 'copia.db');
      await createBackupFile(source, file, factory: factory);
      await source.close();

      final data = await readBackupData(file, factory: factory);
      expect(data.extras!.rates.single.cents, 1500);
      expect(data.extras!.months.single.status, MonthStatus.paid);

      final target = await open('destino.db');
      final repo = SqliteMoneyRepository(() async => target);
      await repo.saveRate(rate(DayKind.festive, 3, 3, 9900));
      await restoreDays(target, data.days, extras: data.extras);
      expect((await repo.rates()).map((r) => r.cents), [1500]);
      expect((await repo.months()).single.month, const YearMonth(2026, 9));
      await target.close();
    });

    test(
      'una copia v1 no trae tarifas ni meses y no toca los de ahora',
      () async {
        final old = await open('v1.db', version: 1);
        final file = p.join(dir.path, 'copia-v1.db');
        await createBackupFile(old, file, factory: factory);
        await old.close();

        final data = await readBackupData(file, factory: factory);
        expect(data.extras, isNull);

        final target = await seeded('destino.db');
        await restoreDays(target, data.days, extras: data.extras);
        final repo = SqliteMoneyRepository(() async => target);
        expect((await repo.rates()).single.cents, 1500);
        expect(await repo.months(), hasLength(1));
        await target.close();
      },
    );

    test('una copia v3 lleva multas y extras y restaurar los sustituye '
        '(007, RF-14)', () async {
      final source = await seeded('origen.db');
      final fine = await SqliteExtrasRepository(() async => source).save(
        ExtraItem(
          type: ExtraType.fine,
          date: DateTime(2026, 11, 2),
          cents: 10000,
          concept: 'Multa velocidad',
        ),
      );
      final file = p.join(dir.path, 'copia-v3.db');
      await createBackupFile(source, file, factory: factory);
      await source.close();

      final data = await readBackupData(file, factory: factory);
      expect(data.extras!.items, [fine]);

      final target = await open('destino.db');
      final extras = SqliteExtrasRepository(() async => target);
      await extras.save(
        ExtraItem(
          type: ExtraType.bonus,
          date: DateTime(2026, 11, 5),
          cents: 2000,
          concept: 'Plus',
        ),
      );
      await restoreDays(target, data.days, extras: data.extras);
      expect(await extras.all(), [fine]);
      await target.close();
    });

    test(
      'una copia v2 no trae multas ni extras y no toca los de ahora',
      () async {
        final old = await open('v2.db', version: 2);
        final file = p.join(dir.path, 'copia-v2.db');
        await createBackupFile(old, file, factory: factory);
        await old.close();

        final data = await readBackupData(file, factory: factory);
        expect(data.extras, isNotNull);
        expect(data.extras!.items, isNull);

        final target = await open('destino.db');
        final extras = SqliteExtrasRepository(() async => target);
        final mine = await extras.save(
          ExtraItem(
            type: ExtraType.bonus,
            date: DateTime(2026, 11, 5),
            cents: 2000,
            concept: 'Plus',
          ),
        );
        await restoreDays(target, data.days, extras: data.extras);
        expect(await extras.all(), [mine]);
        await target.close();
      },
    );

    test('una copia v4 lleva horas guardadas y restaurar las sustituye; '
        'una v3 no las toca (008, RF-21)', () async {
      final source = await seeded('origen4.db');
      final mine = await SqliteSavedHoursRepository(() async => source).save(
        SavedMove(
          box: SavedBox.own,
          kind: SavedMoveKind.before,
          date: DateTime(2025, 1, 1),
          minutes: 39 * 60,
        ),
      );
      final file4 = p.join(dir.path, 'copia-v4.db');
      await createBackupFile(source, file4, factory: factory);
      await source.close();

      final v3 = await open('v3.db', version: 3);
      final file3 = p.join(dir.path, 'copia-v3b.db');
      await createBackupFile(v3, file3, factory: factory);
      await v3.close();

      final target = await open('destino4.db');
      final saved = SqliteSavedHoursRepository(() async => target);
      final current = await saved.save(
        SavedMove(
          box: SavedBox.company,
          kind: SavedMoveKind.before,
          date: DateTime(2025, 1, 1),
          minutes: 16 * 60,
        ),
      );
      final data3 = await readBackupData(file3, factory: factory);
      expect(data3.extras!.savedMoves, isNull);
      await restoreDays(target, data3.days, extras: data3.extras);
      expect(await saved.all(), [current]);

      final data4 = await readBackupData(file4, factory: factory);
      expect(data4.extras!.savedMoves, [mine]);
      await restoreDays(target, data4.days, extras: data4.extras);
      expect(await saved.all(), [mine]);
      await target.close();
    });

    test('una copia v5 lleva las vacaciones y restaurar las sustituye; '
        'una v4 no las toca (010, RF-20)', () async {
      final source = await seeded('origen5.db');
      final sourceRepo = SqliteVacationRepository(() async => source);
      final settings = VacationSettings(firstYear: 2021, firstHalfDays: 23);
      await sourceRepo.saveSettings(settings);
      await sourceRepo.saveDay(VacationDay(DateTime(2026, 1, 2), 2025));
      final file5 = p.join(dir.path, 'copia-v5.db');
      await createBackupFile(source, file5, factory: factory);
      await source.close();

      final v4 = await open('v4.db', version: 4);
      final file4 = p.join(dir.path, 'copia-v4.db');
      await createBackupFile(v4, file4, factory: factory);
      await v4.close();

      final target = await open('destino5.db');
      final repo = SqliteVacationRepository(() async => target);
      final mine = VacationSettings(firstYear: 2023, firstHalfDays: 10);
      await repo.saveSettings(mine);
      await repo.saveDay(VacationDay(DateTime(2026, 6, 1), 2026));

      final data4 = await readBackupData(file4, factory: factory);
      expect(data4.extras!.vacation, isNull);
      await restoreDays(target, data4.days, extras: data4.extras);
      expect(await repo.settings(), mine);
      expect(await repo.days(), hasLength(1));

      final data5 = await readBackupData(file5, factory: factory);
      await restoreDays(target, data5.days, extras: data5.extras);
      expect(await repo.settings(), settings);
      expect(await repo.days(), [VacationDay(DateTime(2026, 1, 2), 2025)]);
      await target.close();
    });

    test('una copia v5 da días enteros y una v6 conserva los medios días '
        '(012, RF-14)', () async {
      final v5 = await open('origen-v5.db', version: 5);
      await v5.insert('vacation_days', {'date': '2026-06-01', 'year': 2026});
      final file5 = p.join(dir.path, 'copia-solo-v5.db');
      await createBackupFile(v5, file5, factory: factory);
      await v5.close();

      final v6 = await open('origen-v6.db');
      final half = VacationDay(DateTime(2026, 6, 2), 2026, half: true);
      await SqliteVacationRepository(() async => v6).saveDay(half);
      final file6 = p.join(dir.path, 'copia-v6.db');
      await createBackupFile(v6, file6, factory: factory);
      await v6.close();

      final target = await open('destino6.db');
      final repo = SqliteVacationRepository(() async => target);

      final data5 = await readBackupData(file5, factory: factory);
      await restoreDays(target, data5.days, extras: data5.extras);
      expect(await repo.days(), [VacationDay(DateTime(2026, 6, 1), 2026)]);

      final data6 = await readBackupData(file6, factory: factory);
      expect(data6.extras!.vacation!.days, [half]);
      await restoreDays(target, data6.days, extras: data6.extras);
      expect(await repo.days(), [half]);
      await target.close();
    });

    test('una copia v4 con un cajón en negativo se rechaza', () async {
      final raw = await open('negativo2.db');
      await raw.insert('saved_moves', {
        'box': 'own',
        'kind': 'timeOff',
        'date': '2026-11-02',
        'minutes': 60,
      });
      await raw.close();
      await expectLater(
        readBackupData(p.join(dir.path, 'negativo2.db'), factory: factory),
        throwsA(
          isA<BackupException>().having(
            (e) => e.problem,
            'problem',
            BackupProblem.badRows,
          ),
        ),
      );
    });

    test('una copia v3 con una multa imposible se rechaza', () async {
      final file = p.join(dir.path, 'rara3.db');
      final raw = await factory.openDatabase(file);
      await raw.execute(
        'CREATE TABLE day_entries (date TEXT, minutes INTEGER, kind TEXT, '
        'reason TEXT, updated_at TEXT)',
      );
      await raw.execute(
        'CREATE TABLE rates (kind TEXT, start_date TEXT, cents INTEGER)',
      );
      await raw.execute(
        'CREATE TABLE months (month TEXT, delivered_on TEXT, paid_on TEXT)',
      );
      await raw.execute(
        'CREATE TABLE extras (id INTEGER, kind TEXT, date TEXT, cents INTEGER, '
        'concept TEXT, status TEXT, closed_on TEXT)',
      );
      await raw.execute(
        "INSERT INTO extras VALUES (1, 'fine', '2026-11-02', 'mucho', "
        "'Multa', 'pending', NULL)",
      );
      await raw.execute('PRAGMA user_version = 3');
      await raw.close();
      await expectLater(
        readBackupData(file, factory: factory),
        throwsA(
          isA<BackupException>().having(
            (e) => e.problem,
            'problem',
            BackupProblem.badRows,
          ),
        ),
      );
    });

    test('una copia v2 con filas imposibles se rechaza', () async {
      final file = p.join(dir.path, 'rara.db');
      final raw = await factory.openDatabase(file);
      await raw.execute(
        'CREATE TABLE day_entries (date TEXT, minutes INTEGER, kind TEXT, '
        'reason TEXT, updated_at TEXT)',
      );
      await raw.execute(
        'CREATE TABLE rates (kind TEXT, start_date TEXT, cents INTEGER)',
      );
      await raw.execute(
        'CREATE TABLE months (month TEXT, delivered_on TEXT, paid_on TEXT)',
      );
      await raw.execute("INSERT INTO rates VALUES ('normal', '2026-01-01', 0)");
      await raw.execute('PRAGMA user_version = 2');
      await raw.close();
      await expectLater(
        readBackupData(file, factory: factory),
        throwsA(
          isA<BackupException>().having(
            (e) => e.problem,
            'problem',
            BackupProblem.badRows,
          ),
        ),
      );
    });

    test('un cobro sin entrega en una copia ajena se rechaza', () async {
      final file = p.join(dir.path, 'rara2.db');
      final raw = await factory.openDatabase(file);
      await raw.execute(
        'CREATE TABLE day_entries (date TEXT, minutes INTEGER, kind TEXT, '
        'reason TEXT, updated_at TEXT)',
      );
      await raw.execute(
        'CREATE TABLE rates (kind TEXT, start_date TEXT, cents INTEGER)',
      );
      await raw.execute(
        'CREATE TABLE months (month TEXT, delivered_on TEXT, paid_on TEXT)',
      );
      await raw.execute(
        "INSERT INTO months VALUES ('2026-09', NULL, '2026-10-01')",
      );
      await raw.execute('PRAGMA user_version = 2');
      await raw.close();
      await expectLater(
        readBackupData(file, factory: factory),
        throwsA(isA<BackupException>()),
      );
    });
  });
}
