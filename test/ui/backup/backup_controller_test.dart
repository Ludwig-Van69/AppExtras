import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/saved_hours.dart';
import 'package:horas_y_vacaciones/data/saved_hours_repository.dart';
import 'package:horas_y_vacaciones/data/app_database.dart';
import 'package:horas_y_vacaciones/data/app_settings.dart';
import 'package:horas_y_vacaciones/data/backup_file.dart';
import 'package:horas_y_vacaciones/data/day_entry_repository.dart';
import 'package:horas_y_vacaciones/data/folder_storage.dart';
import 'package:horas_y_vacaciones/domain/backup_names.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/ui/backup/backup_controller.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fakes/fake_folder_storage.dart';

/// Carpeta falsa que permite hacer algo (o esperar) justo al escribir.
class HookStorage extends FakeFolderStorage {
  Future<void> Function()? onWrite;

  @override
  Future<void> writeFile(String folder, String name, Uint8List bytes) async {
    await onWrite?.call();
    return super.writeFile(folder, name, bytes);
  }
}

const folder = 'content://carpeta/inventada';

void main() {
  late Directory dir;
  late Database db;
  late SqliteDayEntryRepository repo;
  late SettingsStore store;
  late HookStorage storage;
  late BackupController c;
  late DateTime now;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('controlador_test_');
    db = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(dir.path, 'horas.db'),
    );
    repo = SqliteDayEntryRepository(
      () async => db,
      clock: () => DateTime.utc(2026, 11, 6),
    );
    store = SettingsStore(File(p.join(dir.path, settingsFileName)));
    storage = HookStorage();
    now = DateTime(2026, 11, 10, 18, 0, 0);
    c = BackupController(
      openDatabase: () async => db,
      settingsStore: store,
      storage: storage,
      factory: databaseFactoryFfi,
      clock: () => now,
    );
    await c.load();
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  DayEntry entry(int d, int minutes, {String? reason}) => DayEntry(
    date: DateTime(2026, 11, d),
    minutes: minutes,
    kind: DayKind.normal,
    reason: reason,
  );

  Future<void> withFolder() async {
    await c.chooseFolder();
  }

  List<String> backupNames() =>
      storage
          .files(folder)
          .keys
          .where((n) => parseBackupName(n) != null)
          .toList()
        ..sort();

  Future<List<DayEntry>> days() async =>
      (await readAllDays(db)).map((d) => d.entry).toList();

  group('elegir carpeta', () {
    test('se guarda y se recuerda al reabrir', () async {
      expect(await c.chooseFolder(), isTrue);
      expect(c.settings.folder, folder);
      expect((await store.load()).folder, folder);
    });

    test('cancelar el selector no cambia nada', () async {
      await withFolder();
      storage.folderToPick = null;
      expect(await c.chooseFolder(), isFalse);
      expect(c.settings.folder, folder);
    });

    test('cambiar de carpeta limpia el último fallo', () async {
      await withFolder();
      storage.broken.add(folder);
      await c.backupNow();
      expect(c.settings.lastError, isNotNull);
      storage.folderToPick = 'content://otra';
      await c.chooseFolder();
      expect(c.settings.folder, 'content://otra');
      expect(c.settings.lastError, isNull);
    });

    test('load recupera lo guardado', () async {
      await withFolder();
      final other = BackupController(
        openDatabase: () async => db,
        settingsStore: store,
        storage: storage,
      );
      await other.load();
      expect(other.settings.folder, folder);
    });
  });

  group('copia al salir (RF-4)', () {
    test('sin carpeta no hace nada', () async {
      await c.markChanged();
      expect(await c.onLeavingApp(), isNull);
    });

    test('con carpeta y cambios, hace la copia y la da por buena', () async {
      await withFolder();
      await repo.save(entry(3, 150, reason: 'Inventario'));
      await c.markChanged();

      final result = await c.onLeavingApp();

      expect(result!.ok, isTrue);
      expect(backupNames(), ['horas-copia-2026-11-10_18-00-00.db']);
      expect(c.settings.lastSuccess, now);
      expect(c.settings.lastError, isNull);
      expect(c.settings.dirty, isFalse);
      expect((await store.load()).dirty, isFalse);
      // Y la copia contiene los días.
      final tmp = File(p.join(dir.path, 'leida.db'))
        ..writeAsBytesSync(storage.files(folder).values.single);
      final read = await readBackupFile(tmp.path, factory: databaseFactoryFfi);
      expect(read.single.entry, entry(3, 150, reason: 'Inventario'));
    });

    test('sin cambios desde la última copia buena, no copia', () async {
      await withFolder();
      await c.markChanged();
      await c.onLeavingApp();
      now = now.add(const Duration(minutes: 5));
      expect(await c.onLeavingApp(), isNull);
      expect(backupNames(), hasLength(1));
    });

    test('un cambio nuevo vuelve a copiar', () async {
      await withFolder();
      await c.markChanged();
      await c.onLeavingApp();
      now = now.add(const Duration(minutes: 5));
      await repo.save(entry(4, 60));
      await c.markChanged();
      await c.onLeavingApp();
      expect(backupNames(), hasLength(2));
    });

    test('lo que cambia mientras se copia sigue pendiente', () async {
      await withFolder();
      await c.markChanged();
      storage.onWrite = () => c.markChanged();
      await c.backupNow();
      expect(c.settings.dirty, isTrue);
    });
  });

  group('hacer copia ahora (RF-11)', () {
    test('copia aunque no haya cambios y dice cómo se llama', () async {
      await withFolder();
      await c.markChanged();
      await c.backupNow();
      now = now.add(const Duration(minutes: 1));
      final r = await c.backupNow();
      expect(r.ok, isTrue);
      expect(backupNames(), hasLength(2));
    });

    test('sin carpeta pide elegirla', () async {
      final r = await c.backupNow();
      expect(r.ok, isFalse);
      expect(r.message, contains('carpeta'));
    });

    test('dos copias en el mismo segundo no se pisan', () async {
      await withFolder();
      await c.backupNow();
      await c.backupNow();
      expect(backupNames(), [
        'horas-copia-2026-11-10_18-00-00-2.db',
        'horas-copia-2026-11-10_18-00-00.db',
      ]);
    });

    test('deja 10 copias y no toca archivos ajenos ni la previa', () async {
      await withFolder();
      storage.files(folder)['foto.jpg'] = Uint8List.fromList([1]);
      storage.files(folder)['horas-antes-de-restaurar-2026-01-01_10-00-00.db'] =
          Uint8List.fromList([2]);
      for (var i = 0; i < 12; i++) {
        now = now.add(const Duration(minutes: 1));
        await c.backupNow();
      }
      final automatic = backupNames().where((n) => n.startsWith('horas-copia'));
      expect(automatic, hasLength(10));
      expect(automatic.first, 'horas-copia-2026-11-10_18-03-00.db');
      expect(storage.files(folder), contains('foto.jpg'));
      expect(
        storage.files(folder),
        contains('horas-antes-de-restaurar-2026-01-01_10-00-00.db'),
      );
    });

    test(
      'si no se puede borrar una copia vieja, la nueva vale igual',
      () async {
        await withFolder();
        for (var i = 0; i < 10; i++) {
          now = now.add(const Duration(minutes: 1));
          await c.backupNow();
        }
        storage.failDeletes = StorageProblem.other;
        now = now.add(const Duration(minutes: 1));
        final r = await c.backupNow();
        expect(r.ok, isTrue);
        expect(c.settings.lastError, isNull);
      },
    );

    test('una sola operación a la vez', () async {
      await withFolder();
      final gate = Completer<void>();
      storage.onWrite = () => gate.future;
      final first = c.backupNow();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.busy, isTrue);
      final second = await c.backupNow();
      expect(second.ok, isFalse);
      gate.complete();
      expect((await first).ok, isTrue);
      expect(c.busy, isFalse);
    });
  });

  group('fallos (RF-8)', () {
    test('carpeta que ya no existe: avisa y no toca nada', () async {
      await withFolder();
      await repo.save(entry(3, 150));
      await c.markChanged();
      await c.backupNow();
      final before = Map.of(storage.files(folder));
      storage.broken.add(folder);
      await repo.save(entry(4, 60));
      await c.markChanged();

      final r = await c.onLeavingApp();

      expect(r!.ok, isFalse);
      expect(c.settings.lastError, isNotNull);
      expect(c.settings.dirty, isTrue);
      expect(c.settings.lastSuccess, now);
      expect(storage.files(folder), before);
      expect(await days(), [entry(3, 150), entry(4, 60)]);
    });

    test(
      'sin espacio al escribir: no deja copia a medias ni borra nada',
      () async {
        await withFolder();
        await c.backupNow();
        final before = Map.of(storage.files(folder));
        storage.failWrites = StorageProblem.other;
        now = now.add(const Duration(minutes: 1));

        final r = await c.backupNow();

        expect(r.ok, isFalse);
        expect(c.settings.lastError, r.message);
        expect(storage.files(folder), before);
      },
    );

    test(
      'el fallo se recuerda y se limpia con la siguiente copia buena',
      () async {
        await withFolder();
        storage.failWrites = StorageProblem.other;
        await c.backupNow();
        expect((await store.load()).lastError, isNotNull);
        storage.failWrites = null;
        await c.backupNow();
        expect(c.settings.lastError, isNull);
        expect((await store.load()).lastError, isNull);
      },
    );
  });

  group('restaurar', () {
    Future<void> makeOldBackup() async {
      await repo.save(entry(2, 30, reason: 'Antiguo'));
      await c.backupNow(); // copia de las 18:00 con 1 día
      await repo.save(entry(9, 120));
      await repo.save(entry(10, 60));
    }

    test(
      'lista las copias de la más reciente a la más antigua con sus días',
      () async {
        await withFolder();
        await makeOldBackup();
        now = now.add(const Duration(hours: 1));
        await c.backupNow();
        storage.files(folder)['horas-copia-2026-01-01_10-00-00.db'] =
            Uint8List.fromList([1, 2, 3]);
        storage.files(folder)['otra-cosa.txt'] = Uint8List(0);

        final list = await c.listBackups();

        expect(list.map((b) => b.info.name), [
          'horas-copia-2026-11-10_19-00-00.db',
          'horas-copia-2026-11-10_18-00-00.db',
          'horas-copia-2026-01-01_10-00-00.db',
        ]);
        expect(list.map((b) => b.dayCount), [3, 1, null]);
      },
    );

    test(
      'sustituye los datos, guarda antes una copia y avisa a la pantalla',
      () async {
        await withFolder();
        await makeOldBackup();
        now = now.add(const Duration(hours: 1));
        final restoredBefore = c.restoredCount;

        final r = await c.restoreFromFolder(
          'horas-copia-2026-11-10_18-00-00.db',
        );

        expect(r.ok, isTrue);
        expect(await days(), [entry(2, 30, reason: 'Antiguo')]);
        expect(c.restoredCount, restoredBefore + 1);
        final previous = storage.files(
          folder,
        )['horas-antes-de-restaurar-2026-11-10_19-00-00.db']!;
        final file = File(p.join(dir.path, 'previa.db'))
          ..writeAsBytesSync(previous);
        final kept = await readBackupFile(
          file.path,
          factory: databaseFactoryFfi,
        );
        expect(kept.map((d) => d.entry.date.day), [2, 9, 10]);
        expect(c.settings.dirty, isTrue);
      },
    );

    test('la copia previa no cuenta entre las 10 ni se borra', () async {
      await withFolder();
      await makeOldBackup();
      now = now.add(const Duration(hours: 1));
      await c.restoreFromFolder('horas-copia-2026-11-10_18-00-00.db');
      for (var i = 0; i < 12; i++) {
        now = now.add(const Duration(minutes: 1));
        await c.backupNow();
      }
      expect(
        storage
            .files(folder)
            .keys
            .where((n) => n.contains('antes-de-restaurar')),
        hasLength(1),
      );
    });

    test('un archivo dañado no cambia nada (RF-16)', () async {
      await withFolder();
      await repo.save(entry(5, 60));
      storage.files(folder)['horas-copia-2026-01-01_10-00-00.db'] =
          Uint8List.fromList(utf8.encode('no soy una base de datos'));
      final filesBefore = Map.of(storage.files(folder));

      final r = await c.restoreFromFolder('horas-copia-2026-01-01_10-00-00.db');

      expect(r.ok, isFalse);
      expect(r.message, isNotEmpty);
      expect(await days(), [entry(5, 60)]);
      expect(storage.files(folder), filesBefore); // ni copia previa
      expect(c.restoredCount, 0);
    });

    test('si falla la copia previa, no se restaura (RF-15)', () async {
      await withFolder();
      await makeOldBackup();
      storage.failWrites = StorageProblem.other;

      final r = await c.restoreFromFolder('horas-copia-2026-11-10_18-00-00.db');

      expect(r.ok, isFalse);
      expect(r.message, contains('no se ha restaurado nada'));
      expect(await days(), [
        entry(2, 30, reason: 'Antiguo'),
        entry(9, 120),
        entry(10, 60),
      ]);
      expect(c.restoredCount, 0);
    });

    test('una copia que ya no está en la carpeta da un aviso claro', () async {
      await withFolder();
      final r = await c.restoreFromFolder('horas-copia-2030-01-01_00-00-00.db');
      expect(r.ok, isFalse);
      expect(r.message, isNotEmpty);
    });

    Future<String> pickedFileWithOneDay() async {
      // Una copia hecha con otra base de datos, como la de un móvil anterior.
      final other = await databaseFactoryFfi.openDatabase(
        p.join(dir.path, 'otra.db'),
        options: OpenDatabaseOptions(
          version: databaseVersion,
          onCreate: (d, _) async {
            await createSchemaV1(d);
            await createSchemaV2(d);
            await createSchemaV3(d);
            await createSchemaV4(d);
            await createSchemaV5(d);
            await createSchemaV6(d);
            await createSchemaV7(d);
            await createSchemaV8(d);
          },
        ),
      );
      await SqliteDayEntryRepository(
        () async => other,
        clock: () => DateTime.utc(2026, 1, 1),
      ).save(entry(7, 90));
      final file = p.join(dir.path, 'elegida-fuera.db');
      await createBackupFile(other, file, factory: databaseFactoryFfi);
      await other.close();
      return file;
    }

    test(
      'un archivo suelto se restaura aunque no esté en la carpeta (RF-17)',
      () async {
        await withFolder();
        await repo.save(entry(5, 60));
        final file = await pickedFileWithOneDay();

        final r = await c.restoreFromFile(file);

        expect(r.ok, isTrue);
        expect(await days(), [entry(7, 90)]);
        expect(
          storage
              .files(folder)
              .keys
              .where((n) => n.contains('antes-de-restaurar')),
          hasLength(1),
        );
      },
    );

    test(
      'tras reinstalar (sin carpeta, sin datos) se puede restaurar',
      () async {
        final file = await pickedFileWithOneDay();
        final r = await c.restoreFromFile(file);
        expect(r.ok, isTrue);
        expect(await days(), [entry(7, 90)]);
      },
    );

    test('una copia antigua avisa de los apartados que no cuadran '
        '(013, RF-16)', () async {
      await withFolder();
      await repo.save(entry(5, 300));
      await SqliteSavedHoursRepository(() async => db).save(
        SavedMove(
          box: SavedBox.own,
          kind: SavedMoveKind.setAside,
          date: DateTime(2026, 11, 5),
          minutes: 180,
        ),
      );
      // Copia en formato v3 (sin horas guardadas) con 1,5 h en noviembre.
      final other = await databaseFactoryFfi.openDatabase(
        p.join(dir.path, 'v3.db'),
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (d, _) async {
            await createSchemaV1(d);
            await createSchemaV2(d);
            await createSchemaV3(d);
          },
        ),
      );
      await other.insert('day_entries', {
        'date': '2026-11-07',
        'minutes': 90,
        'kind': 'normal',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      final file = p.join(dir.path, 'antigua.db');
      await createBackupFile(other, file, factory: databaseFactoryFfi);
      await other.close();

      final r = await c.restoreFromFile(file);

      expect(r.ok, isTrue);
      expect(r.message, contains('Revisa los apartados de: noviembre 2026'));
      // No se borra nada: el apartado sigue ahí.
      expect(
        await SqliteSavedHoursRepository(() async => db).all(),
        hasLength(1),
      );
    });

    test('sin carpeta y con datos, pide elegir carpeta antes', () async {
      await repo.save(entry(5, 60));
      final file = await pickedFileWithOneDay();
      final r = await c.restoreFromFile(file);
      expect(r.ok, isFalse);
      expect(r.message, contains('carpeta'));
      expect(await days(), [entry(5, 60)]);
    });
  });

  group('exportar a Excel', () {
    test('sin horas no exporta (RF-21)', () async {
      await withFolder();
      final r = await c.exportCsv();
      expect(r.ok, isFalse);
      expect(r.message, 'Aún no hay horas que exportar.');
      expect(storage.shared, isEmpty);
      expect(storage.files(folder), isEmpty);
    });

    test('guarda el CSV en la carpeta y abre Compartir (RF-18)', () async {
      await withFolder();
      await repo.save(entry(3, 150, reason: 'Inventario'));

      final r = await c.exportCsv();

      expect(r.ok, isTrue);
      expect(r.message, 'horas-2026-11-10.csv');
      final text = utf8.decode(storage.files(folder)['horas-2026-11-10.csv']!);
      expect(text, contains('03/11/2026;2,5;150;Normal;Inventario'));
      expect(storage.shared.single.name, 'horas-2026-11-10.csv');
      expect(storage.shared.single.mime, 'text/csv');
      expect(storage.shared.single.bytes.take(3), [0xEF, 0xBB, 0xBF]);
    });

    test('exportar dos veces el mismo día no pisa el primero', () async {
      await withFolder();
      await repo.save(entry(3, 60));
      await c.exportCsv();
      await c.exportCsv();
      expect(
        storage.files(folder).keys,
        containsAll(['horas-2026-11-10.csv', 'horas-2026-11-10-2.csv']),
      );
    });

    test('sin carpeta comparte igualmente (RF-20)', () async {
      await repo.save(entry(3, 60));
      final r = await c.exportCsv();
      expect(r.ok, isTrue);
      expect(storage.shared, hasLength(1));
      expect(storage.folders, isEmpty);
    });

    test('con la carpeta rota comparte y lo avisa', () async {
      await withFolder();
      await repo.save(entry(3, 60));
      storage.broken.add(folder);
      final r = await c.exportCsv();
      expect(r.ok, isTrue);
      expect(r.message, contains('no se ha podido guardar'));
      expect(storage.shared, hasLength(1));
    });

    test('las copias no se confunden con el CSV al limpiar', () async {
      await withFolder();
      await repo.save(entry(3, 60));
      await c.exportCsv();
      for (var i = 0; i < 12; i++) {
        now = now.add(const Duration(minutes: 1));
        await c.backupNow();
      }
      expect(storage.files(folder), contains('horas-2026-11-10.csv'));
    });
  });
}
