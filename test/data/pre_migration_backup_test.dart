import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/device_store.dart';
import 'package:horas_y_vacaciones/data/app_database.dart';
import 'package:horas_y_vacaciones/data/app_settings.dart';
import 'package:horas_y_vacaciones/data/folder_storage.dart';
import 'package:horas_y_vacaciones/data/pre_migration_backup.dart' as pre;
import 'package:horas_y_vacaciones/domain/backup_names.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../fakes/fake_folder_storage.dart';

void main() {
  late Directory dir;
  late String file;
  late SettingsStore settings;
  late FakeFolderStorage storage;
  final now = DateTime(2026, 11, 12, 22, 30, 5);

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('premig_test_');
    file = p.join(dir.path, 'horas.db');
    settings = SettingsStore(File(p.join(dir.path, settingsFileName)));
    storage = FakeFolderStorage();
    final db = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: file,
      version: 1,
    );
    await db.insert('day_entries', {
      'date': '2026-11-03',
      'minutes': 90,
      'kind': 'normal',
      'reason': null,
      'updated_at': '2026-11-03T10:00:00Z',
    });
    await db.close();
  });
  tearDown(() => dir.delete(recursive: true));

  List<String> local() => [
    for (final e in dir.listSync())
      if (e.path.endsWith('.bak')) p.basename(e.path),
  ];

  test('deja siempre una copia local idéntica', () async {
    await pre.backupBeforeUpgrade(file, clock: () => now);
    expect(local(), hasLength(1));
    final copy = File(p.join(dir.path, local().single));
    expect(await copy.readAsBytes(), await File(file).readAsBytes());
  });

  test('con carpeta accesible deja otra copia, protegida', () async {
    await settings.save(const BackupSettings(folder: 'content://carpeta'));
    await pre.backupBeforeUpgrade(
      file,
      storage: storage,
      settings: settings,
      clock: () => now,
    );
    final names = storage.files('content://carpeta').keys.toList();
    expect(names, hasLength(1));
    expect(parseBackupName(names.single)!.kind, BackupKind.beforeRestore);
  });

  test('la copia de la carpeta lleva el móvil (025, RF-5)', () async {
    await settings.save(const BackupSettings(folder: 'content://carpeta'));
    final deviceFile = File(p.join(dir.path, 'movil.json'));
    await deviceFile.writeAsString('{"id":"abc123","name":"Prueba"}');
    await pre.backupBeforeUpgrade(
      file,
      storage: storage,
      settings: settings,
      device: DeviceStore(deviceFile),
      clock: () => now,
    );
    final info = parseBackupName(
      storage.files('content://carpeta').keys.single,
    )!;
    expect(info.kind, BackupKind.beforeRestore);
    expect(info.deviceId, 'abc123');
  });

  test(
    'si la carpeta falla, la copia local basta y no impide migrar',
    () async {
      await settings.save(const BackupSettings(folder: 'content://carpeta'));
      storage.failWrites = StorageProblem.other;
      await pre.backupBeforeUpgrade(
        file,
        storage: storage,
        settings: settings,
        clock: () => now,
      );
      expect(local(), hasLength(1));
    },
  );

  test('sin carpeta elegida, solo la local', () async {
    await pre.backupBeforeUpgrade(
      file,
      storage: storage,
      settings: settings,
      clock: () => now,
    );
    expect(storage.folders, isEmpty);
  });

  test('si no se puede hacer la copia local, falla (y no se migra)', () async {
    await expectLater(
      pre.backupBeforeUpgrade(p.join(dir.path, 'no-existe.db')),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'unida a openAppDatabase: migra v1 a la actual sin perder días',
    () async {
      final db = await openAppDatabase(
        factory: databaseFactoryFfi,
        path: file,
        backupBeforeUpgrade: (path) =>
            pre.backupBeforeUpgrade(path, clock: () => now),
      );
      expect(await db.getVersion(), databaseVersion);
      expect((await db.query('day_entries')).single['minutes'], 90);
      await db.close();
      expect(local(), hasLength(1));
    },
  );
}
