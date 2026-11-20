// Importación real del Excel (016, RF-10 a RF-14). No es un test de
// comportamiento: es la herramienta, y solo se ejecuta a mano.
//
// 1. Informe:  flutter test test/_importar/importar_excel_test.dart --dart-define=IMPORTAR=true
// 2. Copia:    añade --dart-define=CREAR=true (solo si el informe cuadra)
//
// Lee `datos/excel-original.xlsx` y deja el informe y la copia en `datos/`
// (que git no sube). Sin esas opciones, no hace nada.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_database.dart';
import 'package:horas_y_vacaciones/data/backup_file.dart';
import 'package:horas_y_vacaciones/data/day_entry_repository.dart';
import 'package:horas_y_vacaciones/data/money_repository.dart';
import 'package:horas_y_vacaciones/domain/money.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'excel_import.dart';
import 'xlsx_reader.dart';

const _run = bool.fromEnvironment('IMPORTAR');
const _create = bool.fromEnvironment('CREAR');

void main() {
  test(
    'importar el Excel',
    () async {
      sqfliteFfiInit();
      final source = File('datos/excel-original.xlsx');
      final result = importWorkbook(
        readXlsx(await source.readAsBytes()),
        paidUntil: const YearMonth(2026, 7),
        rateStart: DateTime(2026),
      );
      // Lo que la app enseñará como «A cobrar» tras restaurar (016, T5).
      final overview = MoneyOverview.compute(
        entries: result.days,
        rates: result.rates,
        records: result.records,
        imported: result.imported,
      );
      final report =
          '${result.report()}'
          '\n«A cobrar» tras restaurar: '
          '${overview.toCollectMinutes / 60} h y '
          '${overview.toCollectCents / 100} €\n';
      await File('datos/informe-importacion.txt').writeAsString(report);
      // ignore: avoid_print
      print(report);
      expect(result.ok, isTrue, reason: 'El informe no cuadra');
      if (!_create) return;

      // Ruta completa: SQLite toma las relativas desde su propia carpeta.
      final out = File('datos/horas-copia-importada-excel.db').absolute;
      if (await out.exists()) {
        fail('Ya existe ${out.path}: bórrala o renómbrala antes.');
      }
      final tmp = await Directory.systemTemp.createTemp('importar_');
      Database? db;
      try {
        db = await openAppDatabase(
          factory: databaseFactoryFfi,
          path: p.join(tmp.path, 'horas.db'),
        );
        final now = DateTime.now().toUtc();
        final open = db;
        final days = SqliteDayEntryRepository(
          () async => open,
          clock: () => now,
        );
        for (final d in result.days) {
          await days.save(d);
        }
        final money = SqliteMoneyRepository(() async => open);
        for (final r in result.rates) {
          await money.saveRate(r);
        }
        for (final m in result.records) {
          await money.saveMonth(m);
        }
        for (final i in result.imported) {
          await open.insert('imported_months', importedMonthToRow(i));
        }
        await createBackupFile(open, out.path, factory: databaseFactoryFfi);
        // ignore: avoid_print
        print('Copia creada: ${out.path}');
      } finally {
        // La base intermedia lleva datos personales: se cierra y se borra
        // siempre, también si algo falla.
        await db?.close();
        // En Windows SQLite puede tardar en soltar el archivo: si no se
        // puede borrar la carpeta temporal, se queda (no tiene nada útil).
        try {
          await tmp.delete(recursive: true);
        } on FileSystemException {
          // ignorado a propósito
        }
      }
    },
    skip: _run ? false : 'Herramienta: solo con --dart-define=IMPORTAR=true',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
