import 'day_kind.dart';
import 'money.dart';

/// Una cifra de Métricas con sus horas y sus euros a la vez (015, RF-2).
/// Horas en minutos y euros en céntimos: siempre enteros.
class Figure {
  const Figure(
    this.minutes,
    this.cents, {
    this.approx = false,
    this.missing = false,
  });

  static const zero = Figure(0, 0);

  final int minutes;
  final int cents;

  /// Alguna hora se ha contado con la primera tarifa de su tipo porque es
  /// anterior a ella (015, RF-5).
  final bool approx;

  /// Hay horas sin ninguna tarifa posible: sus euros no están incluidos.
  final bool missing;

  Figure operator +(Figure o) => Figure(
    minutes + o.minutes,
    cents + o.cents,
    approx: approx || o.approx,
    missing: missing || o.missing,
  );

  Figure operator -(Figure o) => Figure(
    minutes - o.minutes,
    cents - o.cents,
    approx: approx || o.approx,
    missing: missing || o.missing,
  );

  @override
  bool operator ==(Object other) =>
      other is Figure &&
      other.minutes == minutes &&
      other.cents == cents &&
      other.approx == approx &&
      other.missing == missing;

  @override
  int get hashCode => Object.hash(minutes, cents, approx, missing);

  @override
  String toString() => 'Figure($minutes min, $cents c, approx: $approx)';
}

/// Una barra del gráfico de un año: un mes (014, RF-14).
class MonthBar {
  const MonthBar({
    required this.month,
    required this.figure,
    required this.previous,
    required this.isCurrent,
  });

  final YearMonth month;
  final Figure figure;

  /// El mismo mes del año anterior (si ese año tiene horas).
  final Figure? previous;
  final bool isCurrent;
}

/// Lo de este año hasta una fecha frente a lo mismo del anterior (RF-10).
class YearComparison {
  const YearComparison({
    required this.current,
    required this.previous,
    required this.previousYear,
    required this.until,
  });

  final Figure current;
  final Figure previous;
  final int previousYear;

  /// Hasta qué día se compara; nulo si se comparan años enteros.
  final DateTime? until;

  Figure get difference => current - previous;
}

/// Las cifras de un año (014; 015, RF-2).
class YearMetrics {
  const YearMetrics({
    required this.year,
    required this.bars,
    required this.total,
    required this.normal,
    required this.festive,
    required this.average,
    required this.comparison,
    required this.forecast,
    required this.weekdayMinutes,
    required this.workdays,
    required this.workdaysWithHours,
  });

  final int year;
  final List<MonthBar> bars;
  final Figure total;
  final Figure normal;
  final Figure festive;

  /// Media de los meses terminados; nula si aún no hay ninguno.
  final Figure? average;
  final YearComparison? comparison;

  /// Estimación de fin de año, redondeada a horas y euros enteros.
  final Figure? forecast;

  /// Minutos de cada día, de lunes (0) a domingo (6).
  final List<int> weekdayMinutes;
  final int workdays;
  final int workdaysWithHours;

  bool get empty => total.minutes == 0;
}

/// Un año en la lista de «Todos los años» (015, RF-11).
class YearRow {
  const YearRow(this.year, this.figure);
  final int year;
  final Figure figure;
}

/// Podio de años por horas: año → puesto (1 oro, 2 plata, 3 bronce). Con
/// empate gana el más reciente; con un solo año no hay podio (018, RF-6).
Map<int, int> podium(List<YearRow> years) {
  final ranked = years.where((y) => y.figure.minutes > 0).toList()
    ..sort(
      (a, b) => a.figure.minutes != b.figure.minutes
          ? b.figure.minutes.compareTo(a.figure.minutes)
          : b.year.compareTo(a.year),
    );
  if (ranked.length < 2) return const {};
  return {
    for (var i = 0; i < ranked.length && i < 3; i++) ranked[i].year: i + 1,
  };
}

/// Un punto de la línea de evolución: un mes (015, RF-10).
class MonthPoint {
  const MonthPoint(this.month, this.figure, [this.average]);
  final YearMonth month;
  final Figure figure;

  /// Media de las horas de este mes y los 11 anteriores, en minutos; nula
  /// hasta el duodécimo mes (017, RF-3).
  final int? average;
}

/// Media móvil de [window] valores: la de cada posición y las
/// [window] − 1 anteriores, redondeada; nula mientras no hay [window]
/// valores (017, RF-3).
List<int?> movingAverage(List<int> values, int window) {
  final out = List<int?>.filled(values.length, null);
  var sum = 0;
  for (var i = 0; i < values.length; i++) {
    sum += values[i];
    if (i >= window) sum -= values[i - window];
    if (i >= window - 1) out[i] = _divide(sum, window);
  }
  return out;
}

/// Las cifras de todos los años (015, RF-7 a RF-11).
class GlobalMetrics {
  const GlobalMetrics({
    required this.total,
    required this.normal,
    required this.festive,
    required this.averagePerYear,
    required this.averagePerMonth,
    required this.bestYear,
    required this.bestMonth,
    required this.series,
    required this.years,
  });

  final Figure total;
  final Figure normal;
  final Figure festive;

  /// Solo años terminados; nula si no hay ninguno.
  final Figure? averagePerYear;

  /// Solo meses terminados, desde el primero con horas; nula si no hay.
  final Figure? averagePerMonth;
  final YearRow? bestYear;
  final MonthPoint? bestMonth;

  /// Un punto por mes, del primero con horas al actual.
  final List<MonthPoint> series;

  /// Del más reciente al más antiguo.
  final List<YearRow> years;

  bool get empty => total.minutes == 0;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

int _daysIn(int year, int month) => DateTime(year, month + 1, 0).day;

/// División entera redondeando la mitad hacia arriba (cifras positivas).
int _divide(int a, int b) => (2 * a + b) ~/ (2 * b);

/// Primer año con horas, o nulo si no hay ninguna (límite del selector).
int? firstMetricsYear(Iterable<MonthLine> months) {
  int? first;
  for (final m in months) {
    if (!m.hasHours) continue;
    if (first == null || m.month.year < first) first = m.month.year;
  }
  return first;
}

/// Pone precio a los días y apartados. Con tarifa del día, igual que
/// Resumen; antes de la primera tarifa de su tipo, con esa primera (aprox.).
class _Pricer {
  _Pricer(Iterable<Rate> rates) {
    for (final r in rates) {
      final f = _first[r.kind];
      if (f == null || r.start.isBefore(f.start)) _first[r.kind] = r;
    }
  }

  final _first = <DayKind, Rate>{};

  /// Precio por hora y si es aproximado; nulo si no hay ninguna tarifa.
  (int, bool)? rate(DayKind kind, int? exact) {
    if (exact != null) return (exact, false);
    final f = _first[kind];
    return f == null ? null : (f.cents, true);
  }

  /// La cifra de un mes, hasta [until] incluido si se indica. Si el mes
  /// tiene todas sus tarifas, sus euros son exactamente los de Resumen.
  Figure month(MonthLine? l, {DateTime? until, DayKind? only}) {
    if (l == null) return Figure.zero;
    var minutes = 0;
    var weight = 0;
    var approx = false;
    var missing = false;
    // Mes del Excel: sin días, con su total por tipo (016, RF-2).
    final imported = l.imported;
    if (imported != null) {
      for (final k in DayKind.values) {
        if (only != null && k != only) continue;
        final m = imported.month.minutesOf(k);
        if (m == 0) continue;
        minutes += m;
        final r = rate(k, imported.rateOf(k));
        if (r == null) {
          missing = true;
          continue;
        }
        weight += r.$1 * m;
        approx = approx || r.$2;
      }
    }
    for (final d in l.countedDays) {
      if (until != null && d.entry.date.isAfter(until)) continue;
      if (only != null && d.entry.kind != only) continue;
      minutes += d.entry.minutes;
      final r = rate(d.entry.kind, d.rateCents);
      if (r == null) {
        missing = true;
        continue;
      }
      weight += r.$1 * d.entry.minutes;
      approx = approx || r.$2;
    }
    // Lo apartado (siempre horas normales) resta euros, no horas: en Horas
    // cuentan todas las apuntadas (014, RF-5). No se resta al pedir solo
    // las festivas.
    if (only != DayKind.festive) {
      for (final s in l.setAside) {
        if (until != null && _day(s.move.date).isAfter(until)) continue;
        final r = rate(DayKind.normal, s.rateCents);
        if (r == null) continue;
        weight -= r.$1 * s.move.minutes;
        approx = approx || r.$2;
      }
    }
    return Figure(
      minutes,
      (weight + 30) ~/ 60,
      approx: approx,
      missing: missing,
    );
  }
}

/// Las cifras de [year] (014; 015). [months] son los de Resumen.
YearMetrics computeYearMetrics({
  required Iterable<MonthLine> months,
  required Iterable<Rate> rates,
  required int year,
  required DateTime today,
  bool Function(DateTime date)? isHoliday,
  bool Function(DateTime date)? isVacation,
}) {
  final now = _day(today);
  final current = YearMonth.of(now);
  final lineOf = {for (final m in months) m.month: m};
  final price = _Pricer(rates);
  final shown = [for (var m = 1; m <= 12; m++) YearMonth(year, m)];

  bool yearHasHours(int y) =>
      months.any((m) => m.month.year == y && m.hasHours);
  final previousYear = yearHasHours(year - 1) ? year - 1 : null;

  var total = Figure.zero;
  var festive = Figure.zero;
  final bars = <MonthBar>[];
  for (final m in shown) {
    final f = price.month(lineOf[m]);
    total += f;
    festive += price.month(lineOf[m], only: DayKind.festive);
    bars.add(
      MonthBar(
        month: m,
        figure: f,
        previous: previousYear == null
            ? null
            : price.month(lineOf[YearMonth(previousYear, m.month)]),
        isCurrent: m == current,
      ),
    );
  }

  final first = _firstMonth(months);
  final closed = [
    for (final m in shown)
      if (m.compareTo(current) < 0 && first != null && m.compareTo(first) >= 0)
        m,
  ];
  final average = closed.isEmpty
      ? null
      : _average(
          closed.fold(Figure.zero, (s, m) => s + price.month(lineOf[m])),
          closed.length,
        );

  Figure toDate(int y, DateTime until) {
    var sum = Figure.zero;
    for (var month = 1; month <= until.month; month++) {
      final l = lineOf[YearMonth(y, month)];
      sum += month < until.month
          ? price.month(l)
          : price.month(l, until: until);
    }
    return sum;
  }

  YearComparison? comparison;
  if (previousYear != null) {
    if (year == now.year) {
      // Si el mismo mes del año anterior viene del Excel (sin días), no se
      // puede cortar a mitad: los dos años se comparan hasta el final del
      // mes anterior (016, RF-6).
      final cut = lineOf[YearMonth(previousYear, now.month)]?.imported != null;
      final currentUntil = cut ? DateTime(year, now.month, 0) : now;
      final previousUntil = cut
          ? DateTime(previousYear, now.month, 0)
          : DateTime(
              previousYear,
              now.month,
              now.day.clamp(1, _daysIn(previousYear, now.month)),
            );
      comparison = YearComparison(
        current: currentUntil.year == year
            ? toDate(year, currentUntil)
            : Figure.zero,
        previous: previousUntil.year == previousYear
            ? toDate(previousYear, previousUntil)
            : Figure.zero,
        previousYear: previousYear,
        until: currentUntil,
      );
    } else if (year < now.year) {
      comparison = YearComparison(
        current: toDate(year, DateTime(year, 12, 31)),
        previous: toDate(previousYear, DateTime(previousYear, 12, 31)),
        previousYear: previousYear,
        until: null,
      );
    }
  }

  // Previsión: no antes del 1 de febrero; a horas y euros enteros.
  Figure? forecast;
  if (year == now.year && now.month > 1) {
    final elapsed = now.difference(DateTime(now.year)).inHours ~/ 24 + 1;
    final inYear =
        DateTime(now.year + 1).difference(DateTime(now.year)).inHours ~/ 24;
    final done = toDate(now.year, now);
    int project(int v, int step) =>
        _divide(v + _divide(v * (inYear - elapsed), elapsed), step) * step;
    forecast = Figure(
      project(done.minutes, 60),
      project(done.cents, 100),
      approx: done.approx,
      missing: done.missing,
    );
  }

  final weekday = List.filled(7, 0);
  final minutesOn = <DateTime, int>{};
  for (final m in shown) {
    for (final d in lineOf[m]?.countedDays ?? const <PricedDay>[]) {
      weekday[d.entry.date.weekday - 1] += d.entry.minutes;
      minutesOn[_day(d.entry.date)] = d.entry.minutes;
    }
  }
  final end = DateTime(year, 12, 31);
  final last = end.isBefore(now) ? end : now;
  var workdays = 0;
  var withHours = 0;
  for (
    var d = DateTime(year);
    !d.isAfter(last);
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    if (d.weekday > DateTime.friday) continue;
    if (isHoliday?.call(d) ?? false) continue;
    if (isVacation?.call(d) ?? false) continue;
    workdays++;
    if ((minutesOn[d] ?? 0) > 0) withHours++;
  }

  return YearMetrics(
    year: year,
    bars: bars,
    total: total,
    festive: festive,
    // Lo apartado siempre son horas normales: el reparto suma el total.
    normal: total - festive,
    average: average,
    comparison: comparison,
    forecast: forecast,
    weekdayMinutes: weekday,
    workdays: workdays,
    workdaysWithHours: withHours,
  );
}

/// Las cifras de todos los años (015, RF-7 a RF-11).
GlobalMetrics computeGlobalMetrics({
  required Iterable<MonthLine> months,
  required Iterable<Rate> rates,
  required DateTime today,
}) {
  final now = _day(today);
  final current = YearMonth.of(now);
  final lineOf = {for (final m in months) m.month: m};
  final price = _Pricer(rates);
  final first = _firstMonth(months);
  if (first == null) {
    return const GlobalMetrics(
      total: Figure.zero,
      normal: Figure.zero,
      festive: Figure.zero,
      averagePerYear: null,
      averagePerMonth: null,
      bestYear: null,
      bestMonth: null,
      series: [],
      years: [],
    );
  }

  final series = <MonthPoint>[];
  var total = Figure.zero;
  var festive = Figure.zero;
  var closedMonths = Figure.zero;
  var closedCount = 0;
  final byYear = <int, Figure>{};
  for (
    var m = first;
    m.compareTo(current) <= 0;
    m = YearMonth.of(DateTime(m.year, m.month + 1))
  ) {
    final f = price.month(lineOf[m]);
    series.add(MonthPoint(m, f));
    total += f;
    festive += price.month(lineOf[m], only: DayKind.festive);
    byYear[m.year] = (byYear[m.year] ?? Figure.zero) + f;
    if (m.compareTo(current) < 0) {
      closedMonths += f;
      closedCount++;
    }
  }
  // Horas posteriores al mes actual (no debería haber): también suman.
  for (final l in months) {
    if (l.month.compareTo(current) > 0 && l.hasHours) {
      final f = price.month(l);
      total += f;
      festive += price.month(l, only: DayKind.festive);
      byYear[l.month.year] = (byYear[l.month.year] ?? Figure.zero) + f;
    }
  }

  final averages = movingAverage([
    for (final p in series) p.figure.minutes,
  ], 12);
  for (var i = 0; i < series.length; i++) {
    series[i] = MonthPoint(series[i].month, series[i].figure, averages[i]);
  }

  final years = [
    for (final y in byYear.keys.toList()..sort((a, b) => b.compareTo(a)))
      YearRow(y, byYear[y]!),
  ];
  final closedYears = years.where((y) => y.year < now.year).toList();

  // Con empate gana el más reciente: se recorren del más reciente al más
  // antiguo y solo se cambia si es estrictamente mayor.
  YearRow? bestYear;
  for (final y in years) {
    if (bestYear == null || y.figure.minutes > bestYear.figure.minutes) {
      bestYear = y;
    }
  }
  MonthPoint? bestMonth;
  for (final p in series.reversed) {
    if (p.figure.minutes == 0) continue;
    if (bestMonth == null || p.figure.minutes > bestMonth.figure.minutes) {
      bestMonth = p;
    }
  }

  return GlobalMetrics(
    total: total,
    festive: festive,
    normal: total - festive,
    averagePerYear: closedYears.isEmpty
        ? null
        : _average(
            closedYears.fold(Figure.zero, (s, y) => s + y.figure),
            closedYears.length,
          ),
    averagePerMonth: closedCount == 0
        ? null
        : _average(closedMonths, closedCount),
    bestYear: bestYear,
    bestMonth: bestMonth,
    series: series,
    years: years,
  );
}

YearMonth? _firstMonth(Iterable<MonthLine> months) {
  YearMonth? first;
  for (final m in months) {
    if (!m.hasHours) continue;
    if (first == null || m.month.compareTo(first) < 0) first = m.month;
  }
  return first;
}

Figure _average(Figure sum, int count) => Figure(
  _divide(sum.minutes, count),
  _divide(sum.cents, count),
  approx: sum.approx,
  missing: sum.missing,
);
