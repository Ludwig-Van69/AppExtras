/// Vacaciones (010): días generados cada año, días marcados con el año al que
/// pertenecen, saldo y las dos vistas. Lo generado va en medios días enteros
/// (22 días = 44) y lo gastado, en días enteros (principio 8).
library;

import 'holidays.dart';

/// Máximo de días generados en un año: 60 días, en medios días (RF-1).
const maxVacationHalfDays = 120;

/// Primer año que se puede configurar (RF-1).
const firstVacationYear = 2020;

/// Días al año que se proponen al configurar (RF-1).
const defaultYearlyHalfDays = 44;

/// Los ajustes de vacaciones de cada persona (RF-1 a RF-3).
class VacationSettings {
  VacationSettings({
    required this.firstYear,
    required this.firstHalfDays,
    this.yearlyHalfDays = defaultYearlyHalfDays,
    Map<int, int> overrides = const {},
  }) : overrides = Map.unmodifiable(overrides) {
    if (firstYear < firstVacationYear) {
      throw ArgumentError.value(firstYear, 'firstYear', 'anterior a 2020');
    }
    for (final v in [firstHalfDays, yearlyHalfDays, ...overrides.values]) {
      if (v < 0 || v > maxVacationHalfDays) {
        throw ArgumentError.value(v, 'halfDays', 'fuera de rango');
      }
    }
  }

  final int firstYear;
  final int firstHalfDays;
  final int yearlyHalfDays;

  /// Correcciones a mano de años concretos (RF-2).
  final Map<int, int> overrides;

  VacationSettings copyWith({
    int? firstYear,
    int? firstHalfDays,
    int? yearlyHalfDays,
    Map<int, int>? overrides,
  }) => VacationSettings(
    firstYear: firstYear ?? this.firstYear,
    firstHalfDays: firstHalfDays ?? this.firstHalfDays,
    yearlyHalfDays: yearlyHalfDays ?? this.yearlyHalfDays,
    overrides: overrides ?? this.overrides,
  );

  /// Medios días generados en [year], sabiendo que hoy es [currentYear]
  /// (RF-3): antes del primer año y después del actual, nada.
  int generatedHalfDays(int year, int currentYear) {
    if (year < firstYear || year > currentYear) return 0;
    return overrides[year] ??
        (year == firstYear ? firstHalfDays : yearlyHalfDays);
  }

  @override
  bool operator ==(Object other) =>
      other is VacationSettings &&
      other.firstYear == firstYear &&
      other.firstHalfDays == firstHalfDays &&
      other.yearlyHalfDays == yearlyHalfDays &&
      _sameMap(other.overrides, overrides);

  @override
  int get hashCode => Object.hash(
    firstYear,
    firstHalfDays,
    yearlyHalfDays,
    Object.hashAllUnordered(overrides.entries.map((e) => (e.key, e.value))),
  );
}

bool _sameMap(Map<int, int> a, Map<int, int> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

/// Un día de vacaciones y el año al que pertenece: el de su fecha o el
/// anterior (RF-8). Puede ser medio día (012, RF-10).
class VacationDay {
  VacationDay(DateTime date, this.year, {this.half = false})
    : date = _day(date) {
    if (year != date.year && year != date.year - 1) {
      throw ArgumentError.value(
        year,
        'year',
        'ni el de la fecha ni el anterior',
      );
    }
  }

  final DateTime date;
  final int year;

  /// Medio día: gasta 0,5 días en lugar de 1 (012, RF-10).
  final bool half;

  /// Lo que gasta, en medios días: 1 o 2.
  int get halfDays => half ? 1 : 2;

  VacationDay copyWith({int? year, bool? half}) =>
      VacationDay(date, year ?? this.year, half: half ?? this.half);

  /// Pertenece al año anterior al de su fecha.
  bool get countsForPreviousYear => year != date.year;

  @override
  bool operator ==(Object other) =>
      other is VacationDay &&
      other.date == date &&
      other.year == year &&
      other.half == half;

  @override
  int get hashCode => Object.hash(date, year, half);

  @override
  String toString() => 'VacationDay($date, $year${half ? ', medio' : ''})';
}

/// Los sábados, domingos y festivos activos no gastan días (RF-6).
bool canTakeVacation(DateTime date, {HolidayCalendar? calendar}) =>
    date.weekday <= DateTime.friday && calendar?.holidayOn(date) == null;

/// Primer y último día que se pueden marcar (RF-7).
(DateTime, DateTime) vacationRange(VacationSettings s, DateTime today) =>
    (DateTime(s.firstYear), DateTime(today.year + 1, 12, 31));

/// Medios días que gastan [days], contando 1 por cada medio día y 2 por cada
/// día entero (012, RF-10). La única cuenta de lo gastado: se usa en todas
/// partes para no contar nada dos veces.
int usedHalfDays(Iterable<VacationDay> days) =>
    days.fold(0, (a, d) => a + d.halfDays);

/// Medios días que le quedan a [year]: generados menos los días que le
/// pertenecen. Puede ser negativo.
int halfDaysLeftIn(
  int year,
  VacationSettings s,
  Iterable<VacationDay> days,
  DateTime today,
) =>
    s.generatedHalfDays(year, today.year) -
    usedHalfDays(days.where((d) => d.year == year));

/// El año que se propone al marcar [date] (RF-8): en enero, el anterior si
/// aún le quedan días; si no, el de la fecha.
int proposeVacationYear(
  DateTime date,
  VacationSettings s,
  Iterable<VacationDay> days,
  DateTime today,
) {
  final previous = date.year - 1;
  if (date.month == DateTime.january &&
      previous >= s.firstYear &&
      halfDaysLeftIn(previous, s, days, today) > 0) {
    return previous;
  }
  return date.year;
}

/// Una fila de la vista principal: un año con lo generado, lo disfrutado
/// que le pertenece y lo que le queda (RF-13).
class VacationYearRow {
  const VacationYearRow(this.year, this.generatedHalfDays, this.usedHalfDays);
  final int year;
  final int generatedHalfDays;

  /// Disfrutados, en medios días (012, RF-10).
  final int usedHalfDays;
  int get leftHalfDays => generatedHalfDays - usedHalfDays;
}

/// Saldo y vistas (RF-12 a RF-14).
class VacationOverview {
  VacationOverview._(
    this.leftHalfDays,
    this.plannedHalfDays,
    this.byOwnYear,
    this.byCalendarYear,
  );

  factory VacationOverview.of(
    VacationSettings s,
    Iterable<VacationDay> days,
    DateTime today,
  ) {
    final now = _day(today);
    final list = days.toList();
    var generated = 0;
    for (var y = s.firstYear; y <= now.year; y++) {
      generated += s.generatedHalfDays(y, now.year);
    }
    int lastOf(Iterable<int> years) =>
        years.fold(now.year, (a, b) => b > a ? b : a);
    final lastOwn = lastOf(list.map((d) => d.year));
    final lastCalendar = lastOf(list.map((d) => d.date.year));
    final firstCalendar = list.fold(
      s.firstYear,
      (a, d) => d.date.year < a ? d.date.year : a,
    );
    return VacationOverview._(
      generated - usedHalfDays(list),
      usedHalfDays(list.where((d) => d.date.isAfter(now))),
      [
        for (var y = s.firstYear; y <= lastOwn; y++)
          VacationYearRow(
            y,
            s.generatedHalfDays(y, now.year),
            usedHalfDays(list.where((d) => d.year == y)),
          ),
      ],
      {
        for (var y = firstCalendar; y <= lastCalendar; y++)
          y: usedHalfDays(list.where((d) => d.date.year == y)),
      },
    );
  }

  /// «Te quedan», en medios días. Puede ser negativo.
  final int leftHalfDays;

  /// Medios días marcados después de hoy (ya restados en [leftHalfDays]).
  final int plannedHalfDays;

  /// Vista principal: por año al que pertenecen.
  final List<VacationYearRow> byOwnYear;

  /// Vista por año en que se disfrutan: medios días de cada año natural.
  final Map<int, int> byCalendarYear;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
