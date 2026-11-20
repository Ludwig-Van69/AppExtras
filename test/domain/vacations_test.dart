import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/holidays.dart';
import 'package:horas_y_vacaciones/domain/vacations.dart';

/// Datos inventados con la forma del Excel: primer año 2021 con 11,5 días y
/// 22 al año después.
final _settings = VacationSettings(firstYear: 2021, firstHalfDays: 23);
final _today = DateTime(2026, 11, 18, 10);

/// [count] días laborables seguidos desde [from], para el año [year] (por
/// defecto, el de cada fecha).
List<VacationDay> _workdays(DateTime from, int count, {int? year}) {
  final out = <VacationDay>[];
  var d = from;
  while (out.length < count) {
    if (d.weekday <= DateTime.friday) out.add(VacationDay(d, year ?? d.year));
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return out;
}

void main() {
  group('días generados (RF-1 a RF-3)', () {
    test('primer año, años siguientes y correcciones', () {
      final s = _settings.copyWith(overrides: {2024: 40});
      expect(s.generatedHalfDays(2020, 2026), 0);
      expect(s.generatedHalfDays(2021, 2026), 23);
      expect(s.generatedHalfDays(2022, 2026), 44);
      expect(s.generatedHalfDays(2024, 2026), 40);
      expect(s.generatedHalfDays(2026, 2026), 44);
      expect(s.generatedHalfDays(2027, 2026), 0); // aún no ha llegado
    });

    test('rechaza valores imposibles', () {
      expect(
        () => VacationSettings(firstYear: 2019, firstHalfDays: 10),
        throwsArgumentError,
      );
      expect(
        () => VacationSettings(firstYear: 2021, firstHalfDays: 121),
        throwsArgumentError,
      );
      expect(
        () => _settings.copyWith(overrides: {2022: -1}),
        throwsArgumentError,
      );
    });
  });

  group('día de vacaciones', () {
    test('pertenece a su año o al anterior', () {
      expect(
        VacationDay(DateTime(2026, 1, 2), 2025).countsForPreviousYear,
        isTrue,
      );
      expect(
        VacationDay(DateTime(2026, 1, 2, 15), 2026).date,
        DateTime(2026, 1, 2),
      );
      expect(
        () => VacationDay(DateTime(2026, 1, 2), 2024),
        throwsArgumentError,
      );
      expect(
        () => VacationDay(DateTime(2026, 1, 2), 2027),
        throwsArgumentError,
      );
    });

    test('sábados, domingos y festivos no gastan días (RF-6)', () {
      final calendar = HolidayCalendar();
      expect(canTakeVacation(DateTime(2026, 11, 18)), isTrue); // miércoles
      expect(canTakeVacation(DateTime(2026, 11, 21)), isFalse); // sábado
      expect(canTakeVacation(DateTime(2026, 11, 22)), isFalse); // domingo
      // 8 de diciembre de 2026, martes y festivo nacional.
      expect(canTakeVacation(DateTime(2026, 12, 8)), isTrue);
      expect(
        canTakeVacation(DateTime(2026, 12, 8), calendar: calendar),
        isFalse,
      );
    });

    test('se marca del primer año al final del siguiente (RF-7)', () {
      final (first, last) = vacationRange(_settings, _today);
      expect(first, DateTime(2021));
      expect(last, DateTime(2027, 12, 31));
    });
  });

  group('año propuesto (RF-8)', () {
    test('en enero, el anterior si le quedan días', () {
      final days = _workdays(DateTime(2025, 6, 2), 20);
      expect(
        proposeVacationYear(DateTime(2026, 1, 2), _settings, days, _today),
        2025,
      );
    });

    test('en enero, el de la fecha si al anterior no le quedan', () {
      final days = _workdays(DateTime(2025, 6, 2), 22);
      expect(
        proposeVacationYear(DateTime(2026, 1, 2), _settings, days, _today),
        2026,
      );
    });

    test('fuera de enero, o antes del primer año, el de la fecha', () {
      expect(
        proposeVacationYear(DateTime(2026, 2, 2), _settings, const [], _today),
        2026,
      );
      expect(
        proposeVacationYear(DateTime(2021, 1, 4), _settings, const [], _today),
        2021,
      );
    });
  });

  group('saldo y vistas (RF-12 a RF-14)', () {
    // 111 días: 17 de 2021 (más de lo generado: a cuenta), 20 de 2022,
    // 22 de 2023, 22 de 2024 (2 en enero de 2025), 14 de 2025 (5 en enero
    // de 2026) y 16 de 2026.
    final days = [
      ..._workdays(DateTime(2021, 8, 2), 17),
      ..._workdays(DateTime(2022, 8, 1), 20),
      ..._workdays(DateTime(2023, 8, 1), 22),
      ..._workdays(DateTime(2024, 9, 2), 20),
      ..._workdays(DateTime(2025, 1, 2), 2, year: 2024),
      ..._workdays(DateTime(2025, 6, 2), 9),
      ..._workdays(DateTime(2026, 1, 2), 5, year: 2025),
      ..._workdays(DateTime(2026, 6, 1), 16),
    ];

    test('121,5 generados − 111 disfrutados = 10,5', () {
      expect(days, hasLength(111));
      final o = VacationOverview.of(_settings, days, _today);
      expect(o.leftHalfDays, 21);
      expect(o.plannedHalfDays, 0);
    });

    test('vista principal: por año al que pertenecen', () {
      final o = VacationOverview.of(_settings, days, _today);
      expect(
        [for (final r in o.byOwnYear) r.year],
        [
          2021, 2022, 2023, 2024, 2025, 2026, //
        ],
      );
      final y2021 = o.byOwnYear.first;
      expect(y2021.usedHalfDays, 34);
      expect(y2021.leftHalfDays, 23 - 34); // −5,5: a cuenta
      expect(o.byOwnYear[3].usedHalfDays, 44); // 2024 con 2 de enero de 2025
      expect(o.byOwnYear[4].usedHalfDays, 28); // 2025 con 5 de enero de 2026
      expect(o.byOwnYear[4].leftHalfDays, 16);
    });

    test('vista por año en que se disfrutan', () {
      final o = VacationOverview.of(_settings, days, _today);
      // En medios días.
      expect(o.byCalendarYear[2024], 40);
      expect(o.byCalendarYear[2025], 22);
      expect(o.byCalendarYear[2026], 42);
    });

    test('lo planificado resta y aparece el año siguiente', () {
      final planned = [
        ...days,
        ..._workdays(DateTime(2026, 12, 21), 2),
        VacationDay(DateTime(2027, 3, 1), 2027),
      ];
      final o = VacationOverview.of(_settings, planned, _today);
      expect(o.plannedHalfDays, 6);
      expect(o.leftHalfDays, 21 - 6);
      expect(o.byOwnYear.last.year, 2027);
      expect(o.byOwnYear.last.generatedHalfDays, 0);
      expect(o.byOwnYear.last.leftHalfDays, -2);
      expect(o.byCalendarYear[2027], 2);
    });

    test('sin días: todo lo generado queda', () {
      final o = VacationOverview.of(_settings, const [], _today);
      expect(o.leftHalfDays, 23 + 5 * 44);
      expect(o.byCalendarYear.keys.first, 2021);
    });
  });

  group('medio día (012, RF-10)', () {
    final whole = VacationDay(DateTime(2026, 6, 1), 2026);
    final half = VacationDay(DateTime(2026, 6, 2), 2026, half: true);

    test('gasta 1 medio día; uno entero, 2', () {
      expect(half.halfDays, 1);
      expect(whole.halfDays, 2);
      expect(usedHalfDays([whole, half]), 3);
    });

    test('se distingue de un día entero', () {
      expect(half, isNot(VacationDay(DateTime(2026, 6, 2), 2026)));
      expect(half.copyWith(year: 2025).half, isTrue);
      expect(
        half.copyWith(half: false),
        VacationDay(DateTime(2026, 6, 2), 2026),
      );
    });

    test('resta 0,5 en todas las cuentas', () {
      final s = VacationSettings(firstYear: 2026, firstHalfDays: 44);
      final planned = VacationDay(DateTime(2026, 12, 21), 2026, half: true);
      final o = VacationOverview.of(s, [whole, half, planned], _today);
      expect(o.leftHalfDays, 44 - 4); // 22 − 2 = 20 días
      expect(o.plannedHalfDays, 1);
      expect(o.byOwnYear.single.usedHalfDays, 4);
      expect(o.byOwnYear.single.leftHalfDays, 40);
      expect(o.byCalendarYear[2026], 4);
      expect(halfDaysLeftIn(2026, s, [whole, half, planned], _today), 40);
    });

    test('en enero se propone el año anterior si le queda medio día', () {
      final s = VacationSettings(firstYear: 2025, firstHalfDays: 3);
      final days = [VacationDay(DateTime(2025, 6, 2), 2025)];
      final today = DateTime(2026, 1, 10);
      expect(proposeVacationYear(DateTime(2026, 1, 12), s, days, today), 2025);
      final spent = [
        ...days,
        VacationDay(DateTime(2025, 6, 3), 2025, half: true),
      ];
      expect(proposeVacationYear(DateTime(2026, 1, 12), s, spent, today), 2026);
    });
  });
}
