import 'holidays.dart';

/// Tipo de un día con horas extra: se pagan distinto.
enum DayKind { normal, festive }

/// Tipo que se propone para un día que aún no tiene horas: sábados,
/// domingos y los festivos del [calendar] son festivos (004, RF-1).
DayKind suggestedKindFor(DateTime date, {HolidayCalendar? calendar}) =>
    date.weekday >= DateTime.saturday || calendar?.holidayOn(date) != null
    ? DayKind.festive
    : DayKind.normal;
