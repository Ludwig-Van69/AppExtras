import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_settings.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late File file;
  late SettingsStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ajustes_test_');
    file = File(p.join(dir.path, settingsFileName));
    store = SettingsStore(file);
  });
  tearDown(() => dir.delete(recursive: true));

  test('sin archivo: ajustes por defecto, sin carpeta y con cambios', () async {
    final s = await store.load();
    expect(s.folder, isNull);
    expect(s.lastSuccess, isNull);
    expect(s.lastError, isNull);
    expect(s.dirty, isTrue);
  });

  test('guardar y volver a leer da lo mismo', () async {
    final saved = BackupSettings(
      folder: 'content://carpeta/inventada',
      lastSuccess: DateTime(2026, 11, 10, 18, 42, 5),
      lastError: 'La carpeta ya no existe',
      dirty: false,
    );
    await store.save(saved);
    expect(await store.load(), saved);
  });

  test('guardar de nuevo sustituye lo anterior y no deja temporales', () async {
    await store.save(const BackupSettings(folder: 'a'));
    await store.save(const BackupSettings(folder: 'b', dirty: false));
    final s = await store.load();
    expect(s.folder, 'b');
    expect(s.dirty, isFalse);
    expect(dir.listSync().map((e) => p.basename(e.path)), [settingsFileName]);
  });

  test('archivo dañado: ajustes por defecto, sin fallar', () async {
    await file.writeAsString('{esto no es json');
    expect(await store.load(), const BackupSettings());
  });

  test('JSON que no es un objeto: ajustes por defecto', () async {
    await file.writeAsString('[1, 2, 3]');
    expect(await store.load(), const BackupSettings());
  });

  test('datos de tipo equivocado se ignoran uno a uno', () async {
    await file.writeAsString(
      '{"folder": 5, "lastSuccess": "ayer", "lastError": 7, "dirty": "no"}',
    );
    expect(await store.load(), const BackupSettings());
  });

  test('una carpeta vacía cuenta como no elegida', () async {
    await file.writeAsString('{"folder": "", "dirty": false}');
    final s = await store.load();
    expect(s.folder, isNull);
    expect(s.dirty, isFalse);
  });

  test('copyWith cambia solo lo indicado y permite borrar', () {
    final s = BackupSettings(
      folder: 'a',
      lastSuccess: DateTime(2026, 1, 1),
      lastError: 'x',
    );
    final c = s.copyWith(lastError: () => null, dirty: false);
    expect(c.folder, 'a');
    expect(c.lastSuccess, s.lastSuccess);
    expect(c.lastError, isNull);
    expect(c.dirty, isFalse);
  });

  group('última copia compartida (023)', () {
    test('se guarda y se lee; un archivo antiguo sin ella vale nula', () async {
      final saved = BackupSettings(lastShared: DateTime(2026, 11, 20, 9, 30));
      await store.save(saved);
      expect(await store.load(), saved);
      await file.writeAsString('{"folder": null, "dirty": true}');
      expect((await store.load()).lastShared, isNull);
      await file.writeAsString('{"lastShared": 3}');
      expect((await store.load()).lastShared, isNull);
    });

    test('aviso: nunca, menos de 15 días, 15 o más y con carpeta '
        '(RF-6 a RF-9)', () {
      final now = DateTime(2026, 11, 23, 12);
      expect(const BackupSettings().shareReminder(now), ShareReminder.never);
      BackupSettings at(DateTime d) => BackupSettings(lastShared: d);
      expect(
        at(DateTime(2026, 11, 9, 13)).shareReminder(now),
        ShareReminder.none,
      );
      expect(
        at(DateTime(2026, 11, 8, 12)).shareReminder(now),
        ShareReminder.overdue,
      );
      expect(
        const BackupSettings(folder: 'a').shareReminder(now),
        ShareReminder.none,
      );
      expect(
        BackupSettings(
          folder: 'a',
          lastShared: DateTime(2020),
        ).shareReminder(now),
        ShareReminder.none,
      );
    });
  });
}
