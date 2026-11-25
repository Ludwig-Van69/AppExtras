/// La empresa y la antigüedad en ella (026).
library;

/// Nombre y fecha de alta, los dos opcionales (RF-1). Inmutable.
class Company {
  /// Quita los espacios de los extremos del nombre; vacío queda como sin
  /// nombre (RF-8). Lanza [ArgumentError] con más de [maxName] caracteres o
  /// una fecha anterior a [minYear] (RF-7).
  factory Company({String? name, DateTime? start}) {
    final n = name?.trim();
    if (n != null && n.length > maxName) {
      throw ArgumentError.value(name, 'name', 'más de $maxName caracteres');
    }
    if (start != null && start.year < minYear) {
      throw ArgumentError.value(start, 'start', 'anterior a $minYear');
    }
    return Company._(
      n == null || n.isEmpty ? null : n,
      start == null ? null : DateTime(start.year, start.month, start.day),
    );
  }

  const Company._(this.name, this.start);

  static const empty = Company._(null, null);
  static const maxName = 60;
  static const minYear = 1950;

  final String? name;

  /// Fecha de alta, sin hora.
  final DateTime? start;

  bool get isEmpty => name == null && start == null;

  Company withName(String? name) => Company(name: name, start: start);
  Company withStart(DateTime? start) => Company(name: name, start: start);

  @override
  bool operator ==(Object other) =>
      other is Company && other.name == name && other.start == start;

  @override
  int get hashCode => Object.hash(name, start);

  @override
  String toString() => 'Company($name, $start)';
}

/// Antigüedad a una fecha: días naturales en total y su desglose en años,
/// meses y días de calendario (RF-3, RF-4).
class Seniority {
  const Seniority({
    required this.totalDays,
    required this.years,
    required this.months,
    required this.days,
  });

  /// Como la vida laboral: días naturales del alta a [today], sin contar
  /// [today] (alta ayer → 1 día). Con el alta en el futuro, todo a cero.
  factory Seniority.between(DateTime start, DateTime today) {
    final s = DateTime.utc(start.year, start.month, start.day);
    final t = DateTime.utc(today.year, today.month, today.day);
    if (!t.isAfter(s)) {
      return const Seniority(totalDays: 0, years: 0, months: 0, days: 0);
    }
    var months = (t.year - s.year) * 12 + t.month - s.month;
    var anchor = _addMonths(s, months);
    if (anchor.isAfter(t)) anchor = _addMonths(s, --months);
    return Seniority(
      totalDays: t.difference(s).inDays,
      years: months ~/ 12,
      months: months % 12,
      days: t.difference(anchor).inDays,
    );
  }

  final int totalDays;
  final int years;
  final int months;
  final int days;

  /// [date] más [n] meses; si ese mes es más corto, su último día (31 ene + 1
  /// mes = 28 o 29 feb).
  static DateTime _addMonths(DateTime date, int n) {
    final y = date.year + (date.month - 1 + n) ~/ 12;
    final m = (date.month - 1 + n) % 12 + 1;
    final last = DateTime.utc(y, m + 1, 0).day;
    return DateTime.utc(y, m, date.day > last ? last : date.day);
  }

  /// «5 años, 5 meses y 4 días»; las partes a cero no se escriben y, si todo
  /// es cero, «0 días».
  String get phrase {
    final parts = [
      if (years > 0) '$years ${years == 1 ? 'año' : 'años'}',
      if (months > 0) '$months ${months == 1 ? 'mes' : 'meses'}',
      if (days > 0) '$days ${days == 1 ? 'día' : 'días'}',
    ];
    if (parts.isEmpty) return '0 días';
    if (parts.length == 1) return parts.single;
    return '${parts.sublist(0, parts.length - 1).join(', ')} y ${parts.last}';
  }

  @override
  bool operator ==(Object other) =>
      other is Seniority &&
      other.totalDays == totalDays &&
      other.years == years &&
      other.months == months &&
      other.days == days;

  @override
  int get hashCode => Object.hash(totalDays, years, months, days);

  @override
  String toString() => 'Seniority($totalDays: $years a, $months m, $days d)';
}
