import 'day_kind.dart';

/// Longitud máxima del motivo (RF-14).
const maxReasonLength = 60;

/// Las horas extra apuntadas en un día: como mucho uno por fecha (RF-27).
///
/// Los minutos son enteros (constitución, principio 8). Aquí solo se exige
/// que estén entre 1 y 1440; la regla «medias horas» es de lo que elige el
/// usuario (`hour_options.dart`), para poder abrir datos importados.
class DayEntry {
  DayEntry({
    required DateTime date,
    required this.minutes,
    required this.kind,
    String? reason,
  }) : date = DateTime(date.year, date.month, date.day),
       reason = normalizeReason(reason) {
    if (minutes < 1 || minutes > 1440) {
      throw ArgumentError.value(
        minutes,
        'minutes',
        'debe estar entre 1 y 1440',
      );
    }
  }

  /// Solo el día, sin hora del reloj.
  final DateTime date;
  final int minutes;
  final DayKind kind;

  /// Motivo opcional, ya limpio; nulo si no hay.
  final String? reason;

  DayEntry copyWith({
    int? minutes,
    DayKind? kind,
    String? Function()? reason,
  }) => DayEntry(
    date: date,
    minutes: minutes ?? this.minutes,
    kind: kind ?? this.kind,
    reason: reason == null ? this.reason : reason(),
  );

  @override
  bool operator ==(Object other) =>
      other is DayEntry &&
      other.date == date &&
      other.minutes == minutes &&
      other.kind == kind &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(date, minutes, kind, reason);

  @override
  String toString() => 'DayEntry(${dateKey(date)}, $minutes min, ${kind.name})';
}

/// Quita los espacios de sobra y corta a [maxReasonLength] (RF-17). Un
/// motivo vacío se convierte en «sin motivo» (nulo).
String? normalizeReason(String? text) {
  if (text == null) return null;
  var r = text.trim();
  if (r.length > maxReasonLength) {
    r = r.substring(0, maxReasonLength).trimRight();
  }
  return r.isEmpty ? null : r;
}

/// Fecha como texto «AAAA-MM-DD», la clave con que se guarda cada día.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Lo contrario de [dateKey]; da [FormatException] si la clave no es válida.
DateTime parseDateKey(String key) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
  if (m == null) throw FormatException('Fecha no válida', key);
  final d = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  if (dateKey(d) != key) throw FormatException('Fecha no válida', key);
  return d;
}
