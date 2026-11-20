import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/holiday_store.dart';
import 'package:horas_y_vacaciones/domain/holidays.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late File file;
  late HolidayStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('festivos_test_');
    file = File(p.join(dir.path, holidaysFileName));
    store = HolidayStore(file);
  });
  tearDown(() => dir.delete(recursive: true));

  test('sin archivo, los de serie', () async {
    final d = await store.load();
    expect(d.disabled, isEmpty);
    expect(d.custom, isEmpty);
  });

  test('guardar y volver a leer', () async {
    await store.save(
      HolidayData(
        disabled: {'nat-reyes'},
        custom: [
          Holiday.once('a', 'Local 2026', DateTime(2026, 6, 29)),
          const Holiday.fixed('b', 'Cada año', HolidayGroup.custom, 7, 16),
        ],
      ),
    );
    final d = await store.load();
    expect(d.disabled, {'nat-reyes'});
    expect(d.custom.map((h) => h.name), ['Local 2026', 'Cada año']);
    expect(d.calendar.holidayOn(DateTime(2026, 6, 29)), isNotNull);
    expect(d.calendar.holidayOn(DateTime(2030, 7, 16)), isNotNull);
    expect(d.calendar.holidayOn(DateTime(2026, 1, 6)), isNull);
  });

  test('archivo dañado: los de serie, sin fallar', () async {
    await file.writeAsString('{no es json');
    expect((await store.load()).custom, isEmpty);
    await file.writeAsString('[1]');
    expect((await store.load()).custom, isEmpty);
  });

  test('un festivo con datos malos se ignora y el resto se conserva', () async {
    await file.writeAsString(
      '{"disabled": [3, "nat-reyes"], "custom": ['
      '{"id": "x", "name": "", "month": 1, "day": 1},'
      '{"id": "y", "name": "Fecha mala", "date": "2026-02-30"},'
      '{"id": "z", "name": "Mes malo", "month": 13, "day": 1},'
      '{"id": "w", "name": "Bueno", "month": 8, "day": 3},'
      '5]}',
    );
    final d = await store.load();
    expect(d.disabled, {'nat-reyes'});
    expect(d.custom.map((h) => h.name), ['Bueno']);
  });
}
