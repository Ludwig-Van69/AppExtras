import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/backup_diff.dart';
import 'package:horas_y_vacaciones/domain/company.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/extras.dart';
import 'package:horas_y_vacaciones/domain/imported_month.dart';
import 'package:horas_y_vacaciones/domain/money.dart';
import 'package:horas_y_vacaciones/domain/saved_hours.dart';
import 'package:horas_y_vacaciones/domain/vacations.dart';
import 'package:horas_y_vacaciones/ui/backup/diff_text.dart';

/// Las líneas del detalle como «qué: aquí → allí», para compararlas fácil.
List<String> lines(BackupDiff d, DiffSection s, {bool hide = false}) => [
  for (final l in diffLines(d, s, hideAmounts: hide))
    '${l.what}: ${l.here} → ${l.there}',
];

void main() {
  test('horas: festiva y motivo (RF-12b)', () {
    final d = BackupDiff(
      days: [
        DiffPair(
          DayEntry(
            date: DateTime(2026, 11, 3),
            minutes: 150,
            kind: DayKind.normal,
            reason: 'Inventario',
          ),
          DayEntry(
            date: DateTime(2026, 11, 3),
            minutes: 150,
            kind: DayKind.festive,
          ),
        ),
      ],
    );
    expect(lines(d, DiffSection.hours), [
      '3 nov 2026: 2,5 h · «Inventario» → 2,5 h festiva',
    ]);
  });

  test('vacaciones: día entero o medio, y ajustes', () {
    final d = BackupDiff(
      vacationDays: [
        DiffPair(
          VacationDay(DateTime(2026, 8, 3), 2026),
          VacationDay(DateTime(2026, 8, 3), 2026, half: true),
        ),
        DiffPair(null, VacationDay(DateTime(2026, 8, 4), 2026)),
      ],
      vacationSettings: DiffPair(
        VacationSettings(firstYear: 2024, firstHalfDays: 44),
        VacationSettings(
          firstYear: 2024,
          firstHalfDays: 44,
          yearlyHalfDays: 45,
        ),
      ),
    );
    expect(lines(d, DiffSection.vacation), [
      '3 ago 2026: día entero → medio día',
      '4 ago 2026: — → día entero',
      'Ajustes de vacaciones: 22 días al año → 22,5 días al año',
    ]);
  });

  test('ajustes que solo cambian en un año corregido: «unos» y «otros»', () {
    final d = BackupDiff(
      vacationSettings: DiffPair(
        VacationSettings(firstYear: 2024, firstHalfDays: 44),
        VacationSettings(
          firstYear: 2024,
          firstHalfDays: 44,
          overrides: {2025: 40},
        ),
      ),
    );
    expect(lines(d, DiffSection.vacation), [
      'Ajustes de vacaciones: unos ajustes → otros',
    ]);
  });

  test('multas y extras: importe y estado, o tapados (RF-12d)', () {
    ExtraItem bonus(ExtraStatus status) => ExtraItem(
      id: 4,
      type: ExtraType.bonus,
      date: DateTime(2026, 10, 30),
      cents: 12050,
      concept: 'Extra inventado',
      status: status,
      closedOn: status == ExtraStatus.pending ? null : DateTime(2026, 11, 5),
    );
    final d = BackupDiff(
      items: [DiffPair(bonus(ExtraStatus.pending), bonus(ExtraStatus.closed))],
    );
    expect(lines(d, DiffSection.extras), [
      'Extra inventado · 30 oct 2026: 120,50 € pendiente → 120,50 € cobrado',
    ]);
    expect(lines(d, DiffSection.extras, hide: true), [
      'Extra inventado · 30 oct 2026: •••• € pendiente → •••• € cobrado',
    ]);
  });

  test('horas guardadas: fecha, tipo y horas', () {
    final d = BackupDiff(
      savedMoves: [
        DiffPair(
          null,
          SavedMove(
            id: 2,
            box: SavedBox.own,
            kind: SavedMoveKind.setAside,
            date: DateTime(2026, 11, 3),
            minutes: 90,
          ),
        ),
      ],
    );
    expect(lines(d, DiffSection.saved), ['3 nov 2026 · Apartar: — → 1,5 h']);
  });

  test('tarifas y meses', () {
    final d = BackupDiff(
      rates: [
        DiffPair(
          Rate(DayKind.festive, DateTime(2026), 2000),
          Rate(DayKind.festive, DateTime(2026), 2150),
        ),
      ],
      months: [
        DiffPair(
          MonthRecord(
            const YearMonth(2026, 10),
            deliveredOn: DateTime(2026, 11, 2),
          ),
          MonthRecord(
            const YearMonth(2026, 10),
            deliveredOn: DateTime(2026, 11, 2),
            paidOn: DateTime(2026, 11, 20),
          ),
        ),
        DiffPair(
          null,
          MonthRecord(
            const YearMonth(2026, 9),
            deliveredOn: DateTime(2026, 10, 2),
          ),
        ),
      ],
    );
    expect(lines(d, DiffSection.ratesAndMonths), [
      'Tarifa festiva desde 1 ene 2026: 20,00 € → 21,50 €',
      'Octubre 2026: entregado → cobrado',
      'Septiembre 2026: abierto → entregado',
    ]);
    expect(
      lines(d, DiffSection.ratesAndMonths, hide: true).first,
      'Tarifa festiva desde 1 ene 2026: •••• € → •••• €',
    );
  });

  test('meses del Excel', () {
    final d = BackupDiff(
      importedMonths: [
        DiffPair(
          ImportedMonth(const YearMonth(2023, 1), 60, 30),
          ImportedMonth(const YearMonth(2023, 1), 60, 0),
        ),
      ],
    );
    expect(lines(d, DiffSection.imported), ['Enero 2023: 1,5 h → 1 h']);
  });

  test('empresa: solo lo que cambia (026, RF-9)', () {
    final d = BackupDiff(
      company: DiffPair(
        Company(name: 'Talleres Ejemplo'),
        Company(name: 'Talleres Ejemplo', start: DateTime(2020, 3, 2)),
      ),
    );
    expect(lines(d, DiffSection.company), ['Fecha de alta: — → 2 mar 2020']);
    final gone = BackupDiff(
      company: DiffPair(Company(name: 'Talleres Ejemplo'), null),
    );
    expect(lines(gone, DiffSection.company), [
      'Nombre de la empresa: Talleres Ejemplo → —',
    ]);
  });
}
