import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/csv_export.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/extras.dart';
import 'package:horas_y_vacaciones/domain/saved_hours.dart';
import 'package:horas_y_vacaciones/domain/vacations.dart';

DayEntry day(int d, int minutes, {DayKind kind = DayKind.normal, String? r}) =>
    DayEntry(
      date: DateTime(2026, 11, d),
      minutes: minutes,
      kind: kind,
      reason: r,
    );

void main() {
  group('csvHours', () {
    test('coma decimal y sin ceros de sobra', () {
      expect(csvHours(150), '2,5');
      expect(csvHours(120), '2');
      expect(csvHours(30), '0,5');
      expect(csvHours(45), '0,75');
      expect(csvHours(1440), '24');
    });

    test('redondea a 2 decimales (el dato exacto está en Minutos)', () {
      expect(csvHours(20), '0,33');
      expect(csvHours(40), '0,67');
      expect(csvHours(1), '0,02');
    });
  });

  group('buildCsv', () {
    test('empieza con la marca UTF-8 y la cabecera', () {
      final csv = buildCsv([]);
      expect(csv, '﻿Fecha;Horas;Minutos;Tipo;Motivo\r\n');
    });

    test('una fila por día, ordenadas por fecha', () {
      final csv = buildCsv([
        day(5, 60, kind: DayKind.festive),
        day(3, 150, r: 'Inventario'),
      ]);
      expect(csv.split('\r\n'), [
        '﻿Fecha;Horas;Minutos;Tipo;Motivo',
        '03/11/2026;2,5;150;Normal;Inventario',
        '05/11/2026;1;60;Festiva;',
        '',
      ]);
    });

    test('ordena por fecha entre años y meses', () {
      final csv = buildCsv([
        DayEntry(date: DateTime(2027, 1, 2), minutes: 30, kind: DayKind.normal),
        DayEntry(
          date: DateTime(2026, 12, 31),
          minutes: 30,
          kind: DayKind.normal,
        ),
      ]);
      final rows = csv.split('\r\n');
      expect(rows[1], startsWith('31/12/2026'));
      expect(rows[2], startsWith('02/01/2027'));
    });

    test('conserva las tildes y la eñe', () {
      final csv = buildCsv([day(3, 60, r: 'Reparación del camión, año')]);
      expect(csv, contains('Reparación del camión, año'));
    });

    test('un motivo que parece fórmula lleva comilla simple (013, RF-19)', () {
      final csv = buildCsv([
        day(1, 60, r: '=SUMA(A1)'),
        day(2, 60, r: '+34 600'),
        day(3, 60, r: '-revisión'),
        day(4, 60, r: '@jefe'),
        day(5, 60, r: 'normal = bien'),
      ]);
      expect(csv, contains("'=SUMA(A1)"));
      expect(csv, contains("'+34 600"));
      expect(csv, contains("'-revisión"));
      expect(csv, contains("'@jefe"));
      expect(csv, isNot(contains("'normal")));
    });

    test('entrecomilla motivos con punto y coma, comillas o saltos', () {
      final csv = buildCsv([
        day(1, 60, r: 'a;b'),
        day(2, 60, r: 'dijo "hola"'),
        day(3, 60, r: 'línea1\nlínea2'),
      ]);
      expect(csv, contains('01/11/2026;1;60;Normal;"a;b"\r\n'));
      expect(csv, contains('02/11/2026;1;60;Normal;"dijo ""hola"""\r\n'));
      expect(csv, contains('03/11/2026;1;60;Normal;"línea1\nlínea2"\r\n'));
    });

    test('un motivo normal no lleva comillas', () {
      expect(buildCsv([day(1, 60, r: 'Cierre')]), contains(';Cierre\r\n'));
    });

    test('multas y extras van detrás, con signo y estado (007, RF-15)', () {
      final csv = buildCsv(
        [day(3, 60)],
        extras: [
          ExtraItem(
            type: ExtraType.bonus,
            date: DateTime(2026, 11, 9),
            cents: 5000,
            concept: 'Dieta; viaje',
          ),
          ExtraItem(
            type: ExtraType.fine,
            date: DateTime(2026, 10, 2),
            cents: 1234567 ~/ 10,
            concept: 'Multa velocidad',
            status: ExtraStatus.closed,
            closedOn: DateTime(2026, 10, 30),
            earlyPayment: true,
          ),
        ],
      );
      expect(csv.split('\r\n'), [
        '﻿Fecha;Horas;Minutos;Tipo;Motivo',
        '03/11/2026;1;60;Normal;',
        '',
        'Fecha;Tipo;Concepto;Importe (€);Estado;Cerrada el;Pronto pago;'
            'La paga la empresa',
        '02/10/2026;Multa;Multa velocidad;-1234,56;Descontada;30/10/2026;Sí;',
        '09/11/2026;Extra;"Dieta; viaje";50,00;Pendiente;;;',
        '',
      ]);
    });

    test('las horas guardadas van al final, con signo (008, RF-22)', () {
      final csv = buildCsv(
        [day(3, 60)],
        savedMoves: [
          SavedMove(
            box: SavedBox.own,
            kind: SavedMoveKind.paid,
            date: DateTime(2026, 11, 10),
            minutes: 150,
            cents: 3750,
          ),
          SavedMove(
            kind: SavedMoveKind.swap,
            date: DateTime(2026, 11, 10),
            minutes: 180,
            note: 'Puente',
            dayOff: DateTime(2026, 12, 7),
          ),
          SavedMove(
            box: SavedBox.company,
            kind: SavedMoveKind.before,
            date: DateTime(2025, 1, 1),
            minutes: 16 * 60,
            note: 'De otros años; sin fecha',
          ),
        ],
      );
      expect(csv.split('\r\n').skip(2), [
        '',
        'Fecha;Cajón;Movimiento;Horas;Minutos;Importe cobrado (€);Nota;'
            'Día libre',
        '01/01/2025;Bolsa de empresa;Horas de antes;16;960;;'
            '"De otros años; sin fecha";',
        '10/11/2026;Mi reserva;Cobrar;-2,5;-150;37,50;;',
        '10/11/2026;;Cambio por libre;-3;-180;;Puente;07/12/2026',
        '',
      ]);
    });

    test('vacaciones: días y años al final (010, RF-21; 012, RF-12)', () {
      final days = [
        VacationDay(DateTime(2026, 1, 2), 2025),
        VacationDay(DateTime(2025, 8, 4), 2025),
        VacationDay(DateTime(2026, 6, 1), 2026, half: true),
      ];
      final csv = buildCsv(
        [day(3, 60)],
        vacationDays: days,
        vacation: VacationOverview.of(
          VacationSettings(firstYear: 2025, firstHalfDays: 3),
          days,
          DateTime(2026, 11, 18),
        ),
      );
      expect(csv.split('\r\n').skip(2), [
        '',
        'Vacaciones;Cuenta para el año;Medio día',
        '04/08/2025;2025;',
        '02/01/2026;2025;',
        '01/06/2026;2026;Sí',
        '',
        'Año;Días generados;Días disfrutados;Días que quedan',
        '2025;1,5;2;-0,5',
        '2026;22;0,5;21,5',
        '',
      ]);
    });

    test('sin multas ni extras, solo las horas', () {
      expect(buildCsv([day(3, 60)]), isNot(contains('Concepto')));
    });
  });

  test('csvEuros', () {
    expect(csvEuros(5), '0,05');
    expect(csvEuros(-10000), '-100,00');
    expect(csvEuros(123456789), '1234567,89');
  });

  test('csvFileName', () {
    expect(csvFileName(DateTime(2026, 11, 10, 18, 42)), 'horas-2026-11-10.csv');
    expect(csvFileName(DateTime(2026, 1, 5)), 'horas-2026-01-05.csv');
  });

  test('csvFileName no pisa un nombre existente', () {
    final d = DateTime(2026, 11, 10);
    expect(
      csvFileName(d, existing: {'horas-2026-11-10.csv'}),
      'horas-2026-11-10-2.csv',
    );
    expect(
      csvFileName(
        d,
        existing: {'horas-2026-11-10.csv', 'horas-2026-11-10-2.csv'},
      ),
      'horas-2026-11-10-3.csv',
    );
  });
}
