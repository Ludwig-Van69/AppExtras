/// Formatos de número en castellano para la interfaz.
///
/// Las horas se manejan siempre en minutos enteros y los euros en céntimos
/// (constitución, principio 8); aquí solo se convierten para mostrarlos.
library;

/// Horas a partir de minutos, con coma y como mucho dos decimales, sin ceros
/// sobrantes: 150 → «2,5», 180 → «3», 45 → «0,75», 80 → «1,33».
String formatMinutes(int minutes) {
  final negative = minutes < 0;
  final hundredths = (minutes.abs() * 100 / 60).round();
  final whole = hundredths ~/ 100;
  final fraction = hundredths % 100;
  final sign = negative && hundredths > 0 ? '-' : '';
  if (fraction == 0) return '$sign$whole';
  final decimals = fraction
      .toString()
      .padLeft(2, '0')
      .replaceFirst(RegExp(r'0$'), '');
  return '$sign$whole,$decimals';
}

/// «1 hora», «2,5 horas», «0 horas».
String hoursPhrase(int minutes) =>
    '${formatMinutes(minutes)} ${minutes == 60 ? 'hora' : 'horas'}';

/// Euros a partir de céntimos, con dos decimales y miles con punto:
/// 123450 → «1.234,50 €».
String formatEuros(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = (abs ~/ 100).toString();
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write('.');
    buffer.write(whole[i]);
  }
  final decimals = (abs % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$buffer,$decimals €';
}

/// Lee euros escritos a mano («15», «15,5», «15.50») y devuelve céntimos; nulo
/// si no es un número con como mucho dos decimales.
int? parseEuros(String text) {
  final t = text.trim().replaceAll('€', '').trim();
  final m = RegExp(r'^(\d{1,6})(?:[.,](\d{1,2}))?$').firstMatch(t);
  if (m == null) return null;
  final decimals = (m[2] ?? '').padRight(2, '0');
  return int.parse(m[1]!) * 100 + int.parse(decimals);
}

/// Mes y año: «Noviembre 2026».
String monthYear(int year, int month) {
  final name = monthName(month);
  return '${name[0].toUpperCase()}${name.substring(1)} $year';
}

const _weekdays = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];
const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// El nombre del mes en minúsculas: 11 → «noviembre».
String monthName(int month) => _months[month - 1];

/// «Jueves, 6 de noviembre»; si no es del año de [today], con el año:
/// «Lunes, 13 de octubre de 2025».
String formatLongDate(DateTime date, {required DateTime today}) {
  final base =
      '${_weekdays[date.weekday - 1]}, ${date.day} de ${_months[date.month - 1]}';
  return date.year == today.year ? base : '$base de ${date.year}';
}

/// El día dicho como en una frase: «hoy», «ayer», «anteayer» o «el 12 de
/// octubre» (con el año si no es el de [today]).
String dayPhrase(DateTime date, {required DateTime today}) {
  final days = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(date.year, date.month, date.day)).inDays;
  switch (days) {
    case 0:
      return 'hoy';
    case 1:
      return 'ayer';
    case 2:
      return 'anteayer';
  }
  final year = date.year == today.year ? '' : ' de ${date.year}';
  return 'el ${date.day} de ${_months[date.month - 1]}$year';
}

/// Medios días como días: 21 → «10,5», 44 → «22», −11 → «−5,5».
String formatHalfDays(int halfDays) {
  final sign = halfDays < 0 ? '−' : '';
  final abs = halfDays.abs();
  return '$sign${abs ~/ 2}${abs.isOdd ? ',5' : ''}';
}

/// «11,5», «11.5» o «22» → medios días (23, 23, 44). Nulo si no se entiende
/// o no es un número de días o medios días.
int? parseHalfDays(String text) {
  final m = RegExp(r'^\s*(\d{1,3})(?:[.,](\d))?\s*$').firstMatch(text);
  if (m == null) return null;
  final dec = m[2];
  if (dec != null && dec != '0' && dec != '5') return null;
  return int.parse(m[1]!) * 2 + (dec == '5' ? 1 : 0);
}

/// «12 nov 2026».
String shortDate(DateTime d) =>
    '${d.day} ${monthName(d.month).substring(0, 3)} ${d.year}';

/// Un número entero con los miles con punto: 2459 → «2.459».
String formatCount(int n) {
  final digits = n.abs().toString();
  final buffer = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
