import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/device_store.dart';
import 'package:horas_y_vacaciones/domain/device_identity.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late File file;
  late DeviceStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('movil_test_');
    file = File(p.join(dir.path, deviceFileName));
    store = DeviceStore(file);
  });
  tearDown(() => dir.delete(recursive: true));

  test(
    'la primera vez crea un móvil con el modelo y lo guarda (RF-1)',
    () async {
      final d = await store.loadOrCreate(
        () async => 'moto g75',
        random: Random(3),
      );
      expect(isValidDeviceId(d.id), isTrue);
      expect(d.name, 'moto g75');
      expect(d.seen, isEmpty);
      expect(await file.exists(), isTrue);
      // La segunda vez lee lo mismo, sin preguntar el modelo.
      final again = await store.loadOrCreate(
        () async => fail('no debe llamarse'),
      );
      expect(again, d);
    },
  );

  test('si el modelo falla, se llama «Móvil»', () async {
    final d = await store.loadOrCreate(() async => throw Exception('x'));
    expect(d.name, 'Móvil');
  });

  test('guarda el nombre y las copias vistas', () async {
    final d = await store.loadOrCreate(() async => 'moto g75');
    final changed = d.copyWith(
      name: 'Trabajo',
      seen: {'x7b2m1': '2026-11-24_18-42-00-0001'},
    );
    await store.save(changed);
    expect(await DeviceStore(file).loadOrCreate(() async => null), changed);
  });

  test('archivo dañado o con código malo: móvil nuevo', () async {
    await file.writeAsString('{no es json');
    final a = await store.loadOrCreate(() async => 'A');
    expect(a.name, 'A');
    await file.writeAsString('{"id":"MAL","name":"B"}');
    final b = await store.loadOrCreate(() async => 'C');
    expect(b.name, 'C');
    expect(b.id, isNot('MAL'));
  });

  test('un nombre guardado que no vale pasa a «Móvil»', () async {
    await file.writeAsString('{"id":"abc123","name":"a_b","seen":{"x":1}}');
    final d = await store.loadOrCreate(() async => 'Z');
    expect(d.id, 'abc123');
    expect(d.name, 'Móvil');
    expect(d.seen, isEmpty);
  });
}
