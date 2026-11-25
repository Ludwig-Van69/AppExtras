import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/backup_diff.dart';
import 'package:horas_y_vacaciones/data/backup_file.dart';
import 'package:horas_y_vacaciones/domain/company.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/extras.dart';
import 'package:horas_y_vacaciones/domain/imported_month.dart';
import 'package:horas_y_vacaciones/domain/money.dart';
import 'package:horas_y_vacaciones/domain/saved_hours.dart';
import 'package:horas_y_vacaciones/domain/vacations.dart';

BackupDay day(int d, int minutes, {String stamp = 'a', String? reason}) =>
    BackupDay(
      DayEntry(
        date: DateTime(2026, 11, d),
        minutes: minutes,
        kind: DayKind.normal,
        reason: reason,
      ),
      stamp,
    );

ExtraItem fine(int id, int cents) => ExtraItem(
  id: id,
  type: ExtraType.fine,
  date: DateTime(2026, 11, 2),
  cents: cents,
  concept: 'Multa inventada',
);

SavedMove move(int id, int minutes) => SavedMove(
  id: id,
  box: SavedBox.own,
  kind: SavedMoveKind.setAside,
  date: DateTime(2026, 11, 3),
  minutes: minutes,
);

BackupData data({
  List<BackupDay> days = const [],
  List<Rate> rates = const [],
  List<MonthRecord> months = const [],
  List<ExtraItem>? items = const [],
  List<SavedMove>? saved = const [],
  BackupVacation? vacation,
  List<ImportedMonth>? imported = const [],
  Company? company = Company.empty,
  bool v1 = false,
}) => BackupData(
  days,
  v1
      ? null
      : BackupExtras(
          rates,
          months,
          items,
          saved,
          vacation ?? BackupVacation(null, const []),
          imported,
          company,
        ),
);

void main() {
  test('lo mismo, aunque cambien las marcas internas: vacío (RF-10)', () {
    final a = data(
      days: [
        day(1, 60, stamp: 'x'),
        day(2, 30),
      ],
    );
    final b = data(
      days: [
        day(2, 30, stamp: 'y'),
        day(1, 60, stamp: 'z'),
      ],
    );
    final diff = compareBackups(a, b);
    expect(diff.isEmpty, isTrue);
    expect(diff.sections.map((s) => s.label), [
      'Horas',
      'Vacaciones',
      'Multas y extras',
      'Horas guardadas',
      'Tarifas y meses',
      'Meses del Excel',
      'Empresa',
    ]);
  });

  test('horas: nuevos, quitados y cambiados cuentan uno cada uno', () {
    final a = data(days: [day(1, 60), day(2, 30), day(3, 90)]);
    final b = data(
      days: [
        day(1, 60),
        day(2, 45),
        day(4, 15),
        day(3, 90, reason: 'Nota'),
      ],
    );
    // 2 cambia, 3 cambia (motivo), 4 nuevo.
    expect(compareBackups(a, b).hours, 3);
    // Al revés: 2 y 3 cambian, 4 se quita.
    expect(compareBackups(b, a).hours, 3);
    expect(compareBackups(a, data()).hours, 3);
  });

  test('vacaciones: días y ajustes', () {
    final settings = VacationSettings(firstYear: 2024, firstHalfDays: 44);
    final a = data(
      vacation: BackupVacation(settings, [
        VacationDay(DateTime(2026, 8, 3), 2026),
      ]),
    );
    final b = data(
      vacation: BackupVacation(
        VacationSettings(firstYear: 2024, firstHalfDays: 40),
        [
          VacationDay(DateTime(2026, 8, 3), 2026, half: true),
          VacationDay(DateTime(2026, 8, 4), 2026),
        ],
      ),
    );
    expect(compareBackups(a, b).vacation, 3);
    expect(compareBackups(a, a).vacation, 0);
  });

  test('multas y extras, y horas guardadas, por su número', () {
    final a = data(items: [fine(1, 500), fine(2, 300)], saved: [move(1, 60)]);
    final b = data(items: [fine(1, 500), fine(2, 350), fine(3, 100)]);
    final diff = compareBackups(a, b);
    expect(diff.extras, 2);
    expect(diff.saved, 1);
  });

  test('tarifas y meses juntos', () {
    final a = data(
      rates: [Rate(DayKind.normal, DateTime(2026), 1500)],
      months: [
        MonthRecord(
          const YearMonth(2026, 10),
          deliveredOn: DateTime(2026, 11, 2),
        ),
      ],
    );
    final b = data(
      rates: [
        Rate(DayKind.normal, DateTime(2026), 1600),
        Rate(DayKind.festive, DateTime(2026), 2000),
      ],
      months: [
        MonthRecord(
          const YearMonth(2026, 10),
          deliveredOn: DateTime(2026, 11, 2),
          paidOn: DateTime(2026, 11, 20),
        ),
      ],
    );
    expect(compareBackups(a, b).ratesAndMonths, 3);
  });

  test('meses del Excel', () {
    final a = data(imported: [ImportedMonth(const YearMonth(2023, 1), 60, 0)]);
    final b = data(imported: [ImportedMonth(const YearMonth(2023, 1), 90, 0)]);
    expect(compareBackups(a, b).imported, 1);
  });

  test('guarda qué cambia, ordenado por fecha (RF-12b)', () {
    final a = data(days: [day(9, 60), day(2, 30)], items: [fine(1, 500)]);
    final b = data(days: [day(2, 45), day(5, 15)], items: [fine(1, 400)]);
    final diff = compareBackups(a, b);
    expect(
      [for (final p in diff.days) (p.here?.minutes, p.there?.minutes)],
      [(30, 45), (null, 15), (60, null)],
    );
    expect(diff.items.single.here!.cents, 500);
    expect(diff.items.single.there!.cents, 400);
  });

  test('los ajustes de vacaciones guardan los dos lados', () {
    final s1 = VacationSettings(firstYear: 2024, firstHalfDays: 44);
    final s2 = VacationSettings(
      firstYear: 2024,
      firstHalfDays: 44,
      yearlyHalfDays: 46,
    );
    final diff = compareBackups(
      data(vacation: BackupVacation(s1, const [])),
      data(vacation: BackupVacation(s2, const [])),
    );
    expect(diff.vacationSettings!.here, s1);
    expect(diff.vacationSettings!.there, s2);
    expect(diff.vacation, 1);
  });

  group('apartados que una copia antigua no trae', () {
    final current = data(
      days: [day(1, 60)],
      rates: [Rate(DayKind.normal, DateTime(2026), 1500)],
      items: [fine(1, 500)],
      saved: [move(1, 60)],
      vacation: BackupVacation(null, [VacationDay(DateTime(2026, 8, 3), 2026)]),
      imported: [ImportedMonth(const YearMonth(2023, 1), 60, 0)],
    );

    test('copia v1 (solo días): lo demás se conserva, cuenta igual', () {
      final diff = compareBackups(current, data(days: [day(1, 60)], v1: true));
      expect(diff.isEmpty, isTrue);
    });

    test(
      'sin multas, horas guardadas ni Excel: igual; las tarifas se vacían',
      () {
        final old = BackupData([day(1, 60)], BackupExtras(const [], const []));
        final diff = compareBackups(current, old);
        expect(diff.extras, 0);
        expect(diff.saved, 0);
        expect(diff.vacation, 0);
        expect(diff.imported, 0);
        // Al restaurar, las tarifas y los meses siempre se sustituyen.
        expect(diff.ratesAndMonths, 1);
      },
    );
  });

  group('empresa (026, RF-9)', () {
    final alta = DateTime(2020, 3, 2);

    test('igual: no cuenta', () {
      final c = Company(name: 'Talleres Ejemplo', start: alta);
      expect(compareBackups(data(company: c), data(company: c)).isEmpty, true);
    });

    test('cuenta el nombre y la fecha por separado', () {
      final here = Company(name: 'Talleres Ejemplo', start: alta);
      final d = compareBackups(
        data(company: here),
        data(company: here.withName('Otra')),
      );
      expect(d.companyChanges, 1);
      expect(d.company!.there!.name, 'Otra');
      final both = compareBackups(data(), data(company: here));
      expect(both.companyChanges, 2);
      expect(both.sections.last.label, 'Empresa');
      expect(both.sections.last.count, 2);
    });

    test('una copia sin empresa (v1-v9) la conserva: no cuenta', () {
      final c = Company(name: 'Talleres Ejemplo', start: alta);
      expect(
        compareBackups(data(company: c), data(company: null)).companyChanges,
        0,
      );
    });
  });
}
