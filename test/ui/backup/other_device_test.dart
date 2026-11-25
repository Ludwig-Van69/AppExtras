import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_database.dart';
import 'package:horas_y_vacaciones/data/app_settings.dart';
import 'package:horas_y_vacaciones/data/backup_file.dart';
import 'package:horas_y_vacaciones/data/company_repository.dart';
import 'package:horas_y_vacaciones/data/device_store.dart';
import 'package:horas_y_vacaciones/domain/backup_names.dart';
import 'package:horas_y_vacaciones/domain/company.dart';
import 'package:horas_y_vacaciones/ui/backup/backup_controller.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fakes/fake_folder_storage.dart';

const folder = 'content://carpeta/inventada';

/// Un móvil de prueba: su base de datos, sus ajustes y su controlador. Todos
/// comparten la misma carpeta, como con Syncthing.
class Phone {
  Phone._(this.db, this.c, this.devices);

  final Database db;
  final BackupController c;
  final DeviceStore devices;

  static Future<Phone> create(
    Directory dir,
    String id,
    String name,
    FakeFolderStorage storage,
    DateTime Function() clock,
  ) async {
    final db = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: p.join(dir.path, '$id.db'),
    );
    final deviceFile = File(p.join(dir.path, '$id.json'));
    await deviceFile.writeAsString('{"id":"$id","name":"$name"}');
    final devices = DeviceStore(deviceFile);
    final c = BackupController(
      openDatabase: () async => db,
      settingsStore: SettingsStore(File(p.join(dir.path, '$id-ajustes.json'))),
      storage: storage,
      deviceStore: devices,
      factory: databaseFactoryFfi,
      clock: clock,
    );
    await c.load();
    await c.chooseFolder();
    return Phone._(db, c, devices);
  }

  /// Apunta [minutes] el día [d] de noviembre de 2026.
  Future<void> log(int d, int minutes) async {
    await db.insert('day_entries', {
      'date': '2026-11-${d.toString().padLeft(2, '0')}',
      'minutes': minutes,
      'kind': 'normal',
      'reason': null,
      'updated_at': '2026-11-24T10:00:00.000Z',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await c.markChanged();
  }

  Future<Map<String, int>> days() async => {
    for (final d in await readAllDays(db))
      d.entry.date.toIso8601String().substring(0, 10): d.entry.minutes,
  };
}

void main() {
  late Directory dir;
  late FakeFolderStorage storage;
  late DateTime now;
  late Phone a;
  late Phone b;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('otro_movil_test_');
    storage = FakeFolderStorage()..folderToPick = folder;
    now = DateTime(2026, 11, 24, 18, 0, 0);
    a = await Phone.create(dir, 'aaaaaa', 'Casa', storage, () => now);
    b = await Phone.create(dir, 'bbbbbb', 'Trabajo', storage, () => now);
  });
  tearDown(() async {
    await a.db.close();
    await b.db.close();
    await dir.delete(recursive: true);
  });

  void later() => now = now.add(const Duration(minutes: 10));

  test(
    'sin copias de otro móvil no hay aviso; las propias no cuentan',
    () async {
      await a.log(3, 60);
      await a.c.backupNow();
      await a.c.checkOtherDevices();
      expect(a.c.offer, isNull);
    },
  );

  test('las copias antiguas sin móvil no se ofrecen (RF-7)', () async {
    await b.log(3, 60);
    await b.c.backupNow();
    final name = storage.files(folder).keys.single;
    storage.files(folder)['horas-copia-2026-11-24_19-00-00.db'] = storage
        .files(folder)
        .remove(name)!;
    await a.c.checkOtherDevices();
    expect(a.c.offer, isNull);
  });

  test('al abrir la app se busca sola (RF-9)', () async {
    await b.log(3, 60);
    await b.c.backupNow();
    final reopened = BackupController(
      openDatabase: () async => a.db,
      settingsStore: SettingsStore(
        File(p.join(dir.path, 'aaaaaa-ajustes.json')),
      ),
      storage: storage,
      deviceStore: a.devices,
      factory: databaseFactoryFfi,
      clock: () => now,
    );
    final found = Completer<void>();
    reopened.addListener(() {
      if (reopened.offer != null && !found.isCompleted) found.complete();
    });
    await reopened.load();
    await found.future.timeout(const Duration(seconds: 5));
    expect(reopened.offer!.deviceName, 'Trabajo');
  });

  test('sin carpeta no se busca nada (RF-9)', () async {
    final s = await Phone.create(dir, 'cccccc', 'Sin', storage, () => now);
    await s.c.load();
    await b.log(3, 60);
    await b.c.backupNow();
    // Este no ha elegido carpeta: se le quita.
    final noFolder = BackupController(
      openDatabase: () async => s.db,
      settingsStore: SettingsStore(File(p.join(dir.path, 'vacio.json'))),
      storage: storage,
      deviceStore: s.devices,
      factory: databaseFactoryFfi,
    );
    await noFolder.load();
    await noFolder.checkOtherDevices();
    expect(noFolder.offer, isNull);
    await s.db.close();
  });

  test('copia más nueva y distinta del otro móvil: aviso con resumen '
      '(RF-9, RF-11, RF-12)', () async {
    await b.log(3, 60);
    await b.log(4, 30);
    await b.c.backupNow();
    await a.log(3, 90);
    await a.c.checkOtherDevices();
    final o = a.c.offer!;
    expect(o.deviceName, 'Trabajo');
    expect(o.tooNew, isFalse);
    expect(o.diff!.hours, 2);
    expect(o.diff!.vacation, 0);
    // Este móvil tiene cambios sin copia (RF-13).
    expect(o.localChanges, isTrue);
  });

  test(
    'sin cambios propios pendientes, no se avisa de ellos (RF-13)',
    () async {
      await a.log(3, 90);
      await a.c.backupNow();
      later();
      await b.log(3, 60);
      await b.c.backupNow();
      await a.c.checkOtherDevices();
      expect(a.c.offer!.localChanges, isFalse);
    },
  );

  test('solo cambia la empresa: también avisa (026, RF-9)', () async {
    await a.log(3, 60);
    await b.log(3, 60);
    await SqliteCompanyRepository(() async => b.db)
        .save(Company(name: 'Talleres Ejemplo', start: DateTime(2020, 3, 2)));
    await b.c.backupNow();
    await a.c.checkOtherDevices();
    final d = a.c.offer!.diff!;
    expect(d.hours, 0);
    expect(d.companyChanges, 2);
  });

  test('si trae lo mismo, no avisa y la da por vista (RF-10)', () async {
    await a.log(3, 60);
    await b.log(3, 60);
    await b.c.backupNow();
    await a.c.checkOtherDevices();
    expect(a.c.offer, isNull);
    final seen = (await a.devices.loadOrCreate(() async => null)).seen;
    expect(seen.keys, ['bbbbbb']);
  });

  test('cargar: sustituye los datos, guarda antes una copia y no vuelve a '
      'ofrecerla (RF-14)', () async {
    await b.log(3, 60);
    await b.log(4, 30);
    await b.c.backupNow();
    later();
    await a.log(9, 15);
    await a.c.checkOtherDevices();
    final r = await a.c.loadOffer();
    expect(r.ok, isTrue);
    expect(await a.days(), {'2026-11-03': 60, '2026-11-04': 30});
    expect(a.c.offer, isNull);
    final before = storage
        .files(folder)
        .keys
        .map(parseBackupName)
        .whereType<BackupInfo>()
        .where((i) => i.kind == BackupKind.beforeRestore)
        .single;
    expect(before.deviceId, 'aaaaaa');
    await a.c.checkOtherDevices();
    expect(a.c.offer, isNull);
  });

  test('ida y vuelta: tras cargar, la copia del que cargó no avisa al otro '
      '(caso límite)', () async {
    await b.log(3, 60);
    await b.c.backupNow();
    later();
    await a.c.checkOtherDevices();
    await a.c.loadOffer();
    await a.c.onLeavingApp(); // A hace su copia al salir.
    expect(
      storage.files(folder).keys.where((n) => n.contains('_aaaaaa_')),
      isNotEmpty,
    );
    await b.c.checkOtherDevices();
    expect(b.c.offer, isNull);
  });

  test('«Ahora no»: no se vuelve a ofrecer hasta que haya otra más nueva '
      '(RF-15)', () async {
    await b.log(3, 60);
    await b.c.backupNow();
    await a.c.checkOtherDevices();
    await a.c.dismissOffer();
    expect(a.c.offer, isNull);
    await a.c.checkOtherDevices();
    expect(a.c.offer, isNull);
    expect(await a.days(), isEmpty);
    later();
    await b.log(5, 45);
    await b.c.backupNow();
    await a.c.checkOtherDevices();
    expect(a.c.offer, isNotNull);
    expect(a.c.offer!.diff!.hours, 2);
  });

  test('varios móviles: solo la más reciente y las anteriores quedan vistas '
      '(RF-16)', () async {
    final c = await Phone.create(dir, 'cccccc', 'Tablet', storage, () => now);
    await b.log(3, 60);
    await b.c.backupNow();
    later();
    await c.log(4, 30);
    await c.c.backupNow();
    await a.c.checkOtherDevices();
    expect(a.c.offer!.deviceName, 'Tablet');
    await a.c.dismissOffer();
    await a.c.checkOtherDevices();
    expect(a.c.offer, isNull); // la de Trabajo, más antigua, también vista
    await c.db.close();
  });

  test('copia dañada: no se ofrece, no cambia nada (RF-17)', () async {
    await a.log(3, 60);
    storage.files(folder)['horas-copia-2026-11-24_19-00-00_bbbbbb_Trabajo.db'] =
        Uint8List.fromList(List.filled(100, 7));
    await a.c.checkOtherDevices();
    expect(a.c.offer, isNull);
    expect(await a.days(), {'2026-11-03': 60});
  });

  test('copia de una versión más nueva: aviso para actualizar, sin cargar '
      '(RF-17)', () async {
    await b.log(3, 60);
    await b.c.backupNow();
    final name = storage.files(folder).keys.single;
    final tmp = File(p.join(dir.path, 'nueva.db'))
      ..writeAsBytesSync(storage.files(folder)[name]!);
    final db = await databaseFactoryFfi.openDatabase(tmp.path);
    await db.setVersion(databaseVersion + 1);
    await db.close();
    storage.files(folder)[name] = tmp.readAsBytesSync();

    await a.c.checkOtherDevices();
    expect(a.c.offer!.tooNew, isTrue);
    expect((await a.c.loadOffer()).ok, isFalse);
    expect(await a.days(), isEmpty);
    // No se da por vista: se volverá a mirar al actualizar.
    await a.c.checkOtherDevices();
    expect(a.c.offer!.tooNew, isTrue);
  });

  test(
    'comparar 2.000 días tarda menos de 2 segundos (no funcional)',
    () async {
      Future<void> fill(Database db, int shift) async {
        final batch = db.batch();
        var day = DateTime(2020, 1, 1);
        for (var i = 0; i < 2000; i++) {
          batch.insert('day_entries', {
            'date': day.toIso8601String().substring(0, 10),
            'minutes': 60 + (i % 7 == 0 ? shift : 0),
            'kind': 'normal',
            'reason': 'Motivo inventado $i',
            'updated_at': '2026-11-24T10:00:00.000Z',
          });
          day = day.add(const Duration(days: 1));
        }
        await batch.commit(noResult: true);
      }

      await fill(b.db, 30);
      await b.c.backupNow();
      await fill(a.db, 0);
      final watch = Stopwatch()..start();
      await a.c.checkOtherDevices();
      watch.stop();
      expect(a.c.offer!.diff!.hours, 286);
      expect(watch.elapsedMilliseconds, lessThan(2000));
    },
  );
}
