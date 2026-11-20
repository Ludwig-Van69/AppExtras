import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/money.dart';

import 'excel_import.dart';
import 'xlsx_reader.dart';

/// Un zip mínimo (comprimido con deflate) para probar el lector.
Uint8List _zip(Map<String, String> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  void u16(BytesBuilder b, int v) => b.add([v & 0xff, v >> 8 & 0xff]);
  void u32(BytesBuilder b, int v) =>
      b.add([v & 0xff, v >> 8 & 0xff, v >> 16 & 0xff, v >> 24 & 0xff]);
  for (final e in files.entries) {
    final name = utf8.encode(e.key);
    final raw = utf8.encode(e.value);
    final data = ZLibEncoder(raw: true).convert(raw);
    final offset = out.length;
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, 0);
    u16(out, 8);
    u32(out, 0);
    u32(out, 0); // CRC: el lector no lo mira
    u32(out, data.length);
    u32(out, raw.length);
    u16(out, name.length);
    u16(out, 0);
    out
      ..add(name)
      ..add(data);
    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0);
    u16(central, 8);
    u32(central, 0);
    u32(central, 0);
    u32(central, data.length);
    u32(central, raw.length);
    u16(central, name.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, offset);
    central.add(name);
  }
  final start = out.length;
  final dir = central.toBytes();
  out.add(dir);
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, files.length);
  u16(out, files.length);
  u32(out, dir.length);
  u32(out, start);
  u16(out, 0);
  return out.toBytes();
}

/// Un libro inventado con la forma del Excel real: «Resumen» con dos años
/// (2025 solo totales, 2026 con días) y las hojas de los meses.
Map<String, Sheet> _book({
  double march26Resumen = 4,
  Map<String, Object> extraMarch = const {},
}) {
  final resumen = <String, Object>{
    'C6': 2025.0,
    'E6': 2026.0,
    'C7': 'Día Normal',
    'D7': 'Día Festivo',
    for (var m = 0; m < 12; m++) 'B${8 + m}': monthNames[m],
    'B20': 'Total anual',
    // 2025: junio 42,5 + 24,5; julio 22,5.
    'C13': 42.5,
    'D13': 24.5,
    'C14': 22.5,
    'C20': 65.0,
    'D20': 24.5,
    // 2026: marzo 4 normales y 3 festivas.
    'E10': march26Resumen,
    'F10': 3.0,
    'E20': march26Resumen,
    'F20': 3.0,
  };
  Sheet month() => {
    'A1': 'Día',
    'B1': 'Horas Extra',
    'C1': 'Horas extra festivas',
    'D1': 'Motivo',
    for (var d = 1; d <= 31; d++) 'A${d + 1}': d.toDouble(),
  };
  return {
    'Resumen': resumen,
    for (final name in monthNames) name: month(),
    'Marzo': {
      ...month(),
      'B3': 1.5, // día 2
      'D3': 'Taller Norte',
      'B4': 2.5, // día 3
      'C4': 'Cliente Sur', // motivo en la columna de festivas
      'C9': 3.0, // día 8, festivo
      // Fila de totales del propio Excel, debajo de los días.
      'B34': '4 Horas',
      'A36': 99.0,
      'B36': 12.0,
      ...extraMarch,
    },
  };
}

ExcelImport _import(Map<String, Sheet> book) => importWorkbook(
  book,
  paidUntil: const YearMonth(2026, 2),
  rateStart: DateTime(2026),
);

void main() {
  group('lector de .xlsx', () {
    test('lee hojas, textos compartidos, números y fórmulas', () {
      final bytes = _zip({
        'xl/workbook.xml':
            '<workbook><sheets><sheet name="Resumen" sheetId="1" '
            'r:id="rId1"/><sheet name="Marzo &amp; más" sheetId="2" '
            'r:id="rId2"/></sheets></workbook>',
        'xl/_rels/workbook.xml.rels':
            '<Relationships><Relationship Id="rId1" Type="x" '
            'Target="worksheets/sheet1.xml"/><Relationship Id="rId2" '
            'Type="x" Target="worksheets/sheet2.xml"/></Relationships>',
        'xl/sharedStrings.xml':
            '<sst><si><t>Día</t></si><si><r><t>Motivo </t></r><r>'
            '<t xml:space="preserve">largo</t></r></si></sst>',
        'xl/worksheets/sheet1.xml':
            '<worksheet><cols><col min="1"/></cols><sheetData><row r="1">'
            '<c r="A1" t="s"><v>0</v></c><c r="B1"><v>15.5</v></c>'
            '<c r="C1"><f>B1*2</f><v>31</v></c><c r="D1" s="2"/>'
            '<c r="E1" t="str"><f>x</f><v>15,5 Horas</v></c>'
            '</row></sheetData></worksheet>',
        'xl/worksheets/sheet2.xml':
            '<worksheet><sheetData><row r="2"><c r="D2" t="s"><v>1</v></c>'
            '</row></sheetData></worksheet>',
      });
      final book = readXlsx(bytes);
      expect(book.keys, ['Resumen', 'Marzo & más']);
      expect(book['Resumen'], {
        'A1': 'Día',
        'B1': 15.5,
        'C1': 31.0,
        'E1': '15,5 Horas',
      });
      expect(book['Marzo & más'], {'D2': 'Motivo largo'});
    });

    test('un archivo que no es zip da error claro', () {
      expect(
        () => readXlsx(Uint8List.fromList(List.filled(40, 1))),
        throwsFormatException,
      );
    });

    test('referencias de celda', () {
      expect(columnOf('A1'), 0);
      expect(columnOf('AD9'), 29);
      expect(rowOf('AD19'), 19);
      expect(refOf(29, 19), 'AD19');
      expect(refOf(0, 2), 'A2');
    });
  });

  group('importación (016)', () {
    test('trae los días del año de detalle con su tipo y motivo (RF-10)', () {
      final r = _import(_book());
      expect(r.detailYear, 2026);
      expect(r.days.map((d) => (d.date.day, d.minutes, d.kind, d.reason)), [
        (2, 90, DayKind.normal, 'Taller Norte'),
        (3, 150, DayKind.normal, 'Cliente Sur'),
        (8, 180, DayKind.festive, null),
      ]);
      expect(
        r.notes.join('\n'),
        contains('«Cliente Sur» estaba en horas festivas'),
      );
    });

    test('trae los totales de los años anteriores como meses del Excel', () {
      final r = _import(_book());
      expect(
        r.imported.map((i) => (i.month, i.normalMinutes, i.festiveMinutes)),
        [
          (const YearMonth(2025, 6), 2550, 1470),
          (const YearMonth(2025, 7), 1350, 0),
        ],
      );
    });

    test('estados: cobrado hasta el mes indicado, con fecha a fin de mes '
        '(RF-11)', () {
      final r = _import(_book());
      expect(r.records.map((m) => m.month), [
        const YearMonth(2025, 6),
        const YearMonth(2025, 7),
      ]);
      expect(r.records.first.paidOn, DateTime(2025, 6, 30));
      expect(r.records.every((m) => m.status == MonthStatus.paid), isTrue);
    });

    test('tarifas conocidas desde la fecha indicada (RF-12)', () {
      final r = _import(_book());
      expect(r.rates, [
        Rate(DayKind.normal, DateTime(2026), 1500),
        Rate(DayKind.festive, DateTime(2026), 2000),
      ]);
    });

    test('con todo cuadrando, el informe lo dice (RF-13)', () {
      final r = _import(_book());
      expect(r.ok, isTrue, reason: r.problems.join('\n'));
      expect(r.checks, hasLength(2));
      expect(r.report(), contains('RESULTADO: todo cuadra.'));
    });

    test('si los días no suman lo de «Resumen», no cuadra y no se crea '
        '(RF-13)', () {
      final r = _import(_book(march26Resumen: 5));
      expect(r.ok, isFalse);
      expect(r.problems.join('\n'), contains('marzo 2026'));
      expect(r.report(), contains('NO CUADRA'));
    });

    test('un día con normales y festivas va como festivo con su total '
        '(RF-15)', () {
      final r = _import(
        _book(march26Resumen: 5, extraMarch: {'B10': 1.0, 'C10': 2.0}),
      );
      final d9 = r.days.firstWhere((d) => d.date.day == 9);
      expect(d9.kind, DayKind.festive);
      expect(d9.minutes, 180);
      expect(r.notes.join('\n'), contains('normales y festivas a la vez'));
    });

    test('un día que no existe en el mes no se importa y lo marca', () {
      final book = _book();
      book['Febrero'] = {...book['Febrero']!, 'B31': 2.0}; // 30 de febrero
      final r = _import(book);
      expect(r.ok, isFalse);
      expect(r.problems.join('\n'), contains('Febrero fila 31'));
    });

    test('sin hoja «Resumen» no sigue', () {
      final r = _import({'Marzo': const {}});
      expect(r.ok, isFalse);
    });
  });
}
