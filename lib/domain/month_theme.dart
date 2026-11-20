/// Temas de temporada de los calendarios (013, RF-9, RF-10). Solo decoran:
/// no cambian ninguna cuenta.
enum MonthTheme {
  christmas,
  kings,
  carnival,
  halloween,
  sanJuan,
  semanaGrande,
  spring,
  summer,
  autumn,
  winter,
}

/// Detalle pequeño en la esquina de un día señalado.
enum DayMark { star, confetti, pumpkin, flame, spark }

/// Domingo de Pascua (calendario gregoriano, método anónimo de Meeus).
DateTime easterSunday(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(year, month, day);
}

/// Martes de Carnaval: 47 días antes de Pascua.
DateTime carnivalTuesday(int year) {
  final e = easterSunday(year);
  return DateTime(e.year, e.month, e.day - 47);
}

/// El tema del mes: primero las fiestas y, si no hay, la estación.
MonthTheme monthTheme(int year, int month) {
  if (month == 12) return MonthTheme.christmas;
  if (month == 1) return MonthTheme.kings;
  if (carnivalTuesday(year).month == month) return MonthTheme.carnival;
  return switch (month) {
    10 => MonthTheme.halloween,
    6 => MonthTheme.sanJuan,
    7 => MonthTheme.semanaGrande,
    3 || 4 || 5 => MonthTheme.spring,
    8 => MonthTheme.summer,
    9 || 11 => MonthTheme.autumn,
    _ => MonthTheme.winter,
  };
}

/// El detalle de [date], o nulo si no es un día señalado de su tema.
DayMark? dayMark(DateTime date) {
  final d = date.day;
  switch (monthTheme(date.year, date.month)) {
    case MonthTheme.christmas:
      return d == 24 || d == 25 || d == 31 ? DayMark.star : null;
    case MonthTheme.kings:
      return d == 5 || d == 6 ? DayMark.star : null;
    case MonthTheme.halloween:
      return d == 31 ? DayMark.pumpkin : null;
    case MonthTheme.sanJuan:
      return d == 23 || d == 24 ? DayMark.flame : null;
    case MonthTheme.semanaGrande:
      return d == 25 ? DayMark.spark : null;
    case MonthTheme.carnival:
      // De sábado a martes de Carnaval.
      // En UTC, para que el cambio de hora no descuadre la resta.
      final tue = carnivalTuesday(date.year);
      final diff = DateTime.utc(
        tue.year,
        tue.month,
        tue.day,
      ).difference(DateTime.utc(date.year, date.month, d)).inDays;
      return diff >= 0 && diff <= 3 ? DayMark.confetti : null;
    case MonthTheme.spring ||
        MonthTheme.summer ||
        MonthTheme.autumn ||
        MonthTheme.winter:
      return null;
  }
}
