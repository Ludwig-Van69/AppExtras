/// Dinero: tarifas con fecha de inicio, importe de cada mes y estado de los
/// meses (005). Todo en enteros: minutos y céntimos (principio 8).
library;

import 'day_entry.dart';
import 'day_kind.dart';
import 'imported_month.dart';
import 'saved_hours.dart';

/// Tarifa máxima admitida: 1.000 € por hora, en céntimos.
const maxRateCents = 100000;

/// Una tarifa: cuántos céntimos por hora vale un tipo de día desde [start].
class Rate {
  Rate(this.kind, DateTime start, this.cents)
    : start = DateTime(start.year, start.month, start.day) {
    if (cents < 1 || cents > maxRateCents) {
      throw ArgumentError.value(cents, 'cents', 'fuera de rango');
    }
  }

  final DayKind kind;
  final DateTime start;
  final int cents;

  @override
  bool operator ==(Object other) =>
      other is Rate &&
      other.kind == kind &&
      other.start == start &&
      other.cents == cents;

  @override
  int get hashCode => Object.hash(kind, start, cents);
}

/// Un mes concreto (año y mes). Se puede comparar y usar como clave.
class YearMonth implements Comparable<YearMonth> {
  const YearMonth(this.year, this.month);
  YearMonth.of(DateTime d) : this(d.year, d.month);

  final int year;
  final int month;

  /// «AAAA-MM», como se guarda.
  String get key =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}';

  /// Lo contrario de [key]; da [FormatException] si no es válida.
  static YearMonth parse(String key) {
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(key);
    if (m == null) throw FormatException('Mes no válido', key);
    final y = int.parse(m[1]!);
    final mo = int.parse(m[2]!);
    if (mo < 1 || mo > 12) throw FormatException('Mes no válido', key);
    return YearMonth(y, mo);
  }

  @override
  int compareTo(YearMonth other) =>
      (year * 12 + month).compareTo(other.year * 12 + other.month);

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => key;
}

enum MonthStatus { open, delivered, paid }

/// Lo que se sabe de un mes: cuándo se entregó el papel y cuándo se cobró.
/// Cobrado implica entregado.
class MonthRecord {
  MonthRecord(this.month, {DateTime? deliveredOn, DateTime? paidOn})
    : deliveredOn = _day(deliveredOn ?? paidOn),
      paidOn = _day(paidOn);

  final YearMonth month;
  final DateTime? deliveredOn;
  final DateTime? paidOn;

  MonthStatus get status => paidOn != null
      ? MonthStatus.paid
      : deliveredOn != null
      ? MonthStatus.delivered
      : MonthStatus.open;

  static DateTime? _day(DateTime? d) =>
      d == null ? null : DateTime(d.year, d.month, d.day);
}

/// La tarifa que vale para un día de [kind] en [date]: la más reciente que ya
/// había empezado. Nulo si aún no había ninguna (RF-3).
Rate? rateFor(DayKind kind, DateTime date, Iterable<Rate> rates) {
  final day = DateTime(date.year, date.month, date.day);
  Rate? best;
  for (final r in rates) {
    if (r.kind != kind || r.start.isAfter(day)) continue;
    if (best == null || r.start.isAfter(best.start)) best = r;
  }
  return best;
}

/// Una tarifa con el periodo que cubre (021, RF-1, RF-2).
class RatePeriod {
  const RatePeriod(this.rate, this.end);
  final Rate rate;

  /// Último día que cubre: el día antes de que empiece la siguiente del mismo
  /// tipo. Nulo si es la última («hasta hoy»).
  final DateTime? end;
}

/// Las tarifas de [kind] como periodos, de la más reciente a la más antigua.
/// El fin de cada una lo pone la siguiente, así que nunca quedan huecos ni
/// días con dos tarifas.
List<RatePeriod> ratePeriods(Iterable<Rate> rates, DayKind kind) {
  final sorted = [
    for (final r in rates)
      if (r.kind == kind) r,
  ]..sort((a, b) => a.start.compareTo(b.start));
  return [
    for (var i = sorted.length - 1; i >= 0; i--)
      RatePeriod(
        sorted[i],
        i == sorted.length - 1
            ? null
            : DateTime(
                sorted[i + 1].start.year,
                sorted[i + 1].start.month,
                sorted[i + 1].start.day - 1,
              ),
      ),
  ];
}

/// Céntimos de [minutes] a [centsPerHour], redondeando mitades hacia arriba.
int amountCents(int minutes, int centsPerHour) =>
    (minutes * centsPerHour + 30) ~/ 60;

/// Un día con horas y lo que vale.
class PricedDay {
  const PricedDay(this.entry, this.rateCents);
  final DayEntry entry;

  /// Nulo si no había tarifa para ese día.
  final int? rateCents;

  /// Importe exacto en «céntimos × minutos ÷ 60» aún sin redondear; ver
  /// [MonthLine.amountCents] para el importe del mes.
  int get weight => (rateCents ?? 0) * entry.minutes;
}

/// Horas apartadas a un cajón (008) con la tarifa normal de su fecha.
class PricedSetAside {
  const PricedSetAside(this.move, this.rateCents);
  final SavedMove move;

  /// Nulo si no había tarifa normal ese día (no debería pasar: RF-6).
  final int? rateCents;

  int get weight => (rateCents ?? 0) * move.minutes;
}

/// Un mes con horas: sus horas, su importe y su estado. Las horas apartadas
/// a un cajón (008, RF-5) se restan de las horas y del importe del mes. Si
/// el mes viene del Excel ([imported]), sus horas salen de ahí y sus días,
/// si los hubiera, no cuentan: nunca se cuenta dos veces (016, RF-2, RF-3).
class MonthLine {
  MonthLine({
    required this.month,
    required this.days,
    required this.record,
    this.setAside = const [],
    this.imported,
  });

  final YearMonth month;

  /// Los días apuntados del mes (aunque no cuenten, ver [countedDays]).
  final List<PricedDay> days;
  final MonthRecord? record;
  final List<PricedSetAside> setAside;

  /// El total del Excel de este mes, si lo hay (016).
  final PricedImport? imported;

  MonthStatus get status => record?.status ?? MonthStatus.open;

  /// Los días que cuentan: ninguno si el mes viene del Excel (016, RF-3).
  List<PricedDay> get countedDays => imported == null ? days : const [];

  /// El mes viene del Excel y además tiene días apuntados, que no cuentan.
  bool get hasIgnoredDays => imported != null && days.isNotEmpty;

  /// El mes tiene alguna hora (de días o del Excel).
  bool get hasHours => imported != null || days.isNotEmpty;

  /// Horas apuntadas de un tipo, sin restar lo apartado.
  int minutesOf(DayKind kind) =>
      imported?.month.minutesOf(kind) ??
      days
          .where((d) => d.entry.kind == kind)
          .fold(0, (sum, d) => sum + d.entry.minutes);

  /// Horas apuntadas, sin restar lo apartado.
  int get loggedMinutes =>
      minutesOf(DayKind.normal) + minutesOf(DayKind.festive);

  /// Horas apartadas a los cajones (siempre normales).
  int get setAsideMinutes => setAside.fold(0, (sum, s) => sum + s.move.minutes);

  /// Horas a cobrar del mes: las apuntadas menos las apartadas.
  int get minutes => loggedMinutes - setAsideMinutes;

  /// Minutos de días sin tarifa: su importe no está incluido (RF-3).
  int get unpricedMinutes {
    final i = imported;
    if (i != null) {
      return [
        for (final k in DayKind.values)
          if (i.rateOf(k) == null) i.month.minutesOf(k),
      ].fold(0, (a, b) => a + b);
    }
    return days
        .where((d) => d.rateCents == null)
        .fold(0, (sum, d) => sum + d.entry.minutes);
  }

  /// Céntimos × minutos de un tipo (o de todos), sin redondear.
  int _weight([DayKind? only]) {
    final i = imported;
    if (i != null) {
      return only == null
          ? i.weightOf(DayKind.normal) + i.weightOf(DayKind.festive)
          : i.weightOf(only);
    }
    return days
        .where((d) => only == null || d.entry.kind == only)
        .fold(0, (sum, d) => sum + d.weight);
  }

  bool get isComplete => unpricedMinutes == 0;

  /// Importe del mes, ya restado lo apartado, redondeado una sola vez
  /// (RF-4; 008, RF-6).
  int get amountCents {
    final total = _weight() - setAside.fold(0, (sum, s) => sum + s.weight);
    return (total + 30) ~/ 60;
  }

  /// Importe de un tipo de día, redondeado una sola vez y sin restar lo
  /// apartado. La suma de los dos tipos puede diferir en 1 céntimo de
  /// [amountCents]; el del mes es el que cuenta.
  int amountOf(DayKind kind) => (_weight(kind) + 30) ~/ 60;

  /// Lo apartado, en céntimos, redondeado una vez.
  int get setAsideCents =>
      (setAside.fold(0, (sum, s) => sum + s.weight) + 30) ~/ 60;
}

/// Todo el dinero de un vistazo (RF-5, RF-7, RF-10).
class MoneyOverview {
  MoneyOverview._(
    this.months,
    this.toCollectCents,
    this.toCollectMinutes,
    this.deliveredCents,
    this.deliveredMinutes,
  );

  /// Los meses con horas, del más reciente al más antiguo.
  final List<MonthLine> months;

  /// «A cobrar»: meses sin cobrar (RF-5).
  final int toCollectCents;
  final int toCollectMinutes;

  /// La parte de «A cobrar» que ya está entregada (006, RF-3). No se suma
  /// aparte: ya está dentro de [toCollectCents].
  final int deliveredCents;
  final int deliveredMinutes;

  factory MoneyOverview.compute({
    required Iterable<DayEntry> entries,
    required Iterable<Rate> rates,
    required Iterable<MonthRecord> records,
    Iterable<SavedMove> savedMoves = const [],
    Iterable<ImportedMonth> imported = const [],
  }) {
    final byMonth = <YearMonth, List<PricedDay>>{};
    for (final e in entries) {
      final rate = rateFor(e.kind, e.date, rates);
      byMonth
          .putIfAbsent(YearMonth.of(e.date), () => [])
          .add(PricedDay(e, rate?.cents));
    }
    final recordOf = {for (final r in records) r.month: r};
    final setAsideOf = <YearMonth, List<PricedSetAside>>{};
    for (final m in savedMoves) {
      if (m.kind != SavedMoveKind.setAside) continue;
      final rate = rateFor(DayKind.normal, m.date, rates);
      setAsideOf
          .putIfAbsent(YearMonth.of(m.date), () => [])
          .add(PricedSetAside(m, rate?.cents));
    }
    // Mes del Excel: a la tarifa de cada tipo vigente el día 1 (016, RF-2).
    int? rateOn(DayKind kind, YearMonth m) =>
        rateFor(kind, DateTime(m.year, m.month), rates)?.cents;
    final importOf = <YearMonth, PricedImport>{
      for (final i in imported)
        i.month: PricedImport(
          i,
          rateOn(DayKind.normal, i.month),
          rateOn(DayKind.festive, i.month),
        ),
    };
    final keys = {...byMonth.keys, ...importOf.keys}.toList()
      ..sort((a, b) => b.compareTo(a));
    final lines = [
      for (final m in keys)
        MonthLine(
          month: m,
          days: (byMonth[m] ?? <PricedDay>[])
            ..sort((a, b) => a.entry.date.compareTo(b.entry.date)),
          record: recordOf[m],
          setAside: setAsideOf[m] ?? const [],
          imported: importOf[m],
        ),
    ];
    var cents = 0;
    var minutes = 0;
    var deliveredCents = 0;
    var deliveredMinutes = 0;
    for (final l in lines) {
      if (l.status == MonthStatus.paid) continue;
      cents += l.amountCents;
      minutes += l.minutes;
      if (l.status == MonthStatus.delivered) {
        deliveredCents += l.amountCents;
        deliveredMinutes += l.minutes;
      }
    }
    return MoneyOverview._(
      lines,
      cents,
      minutes,
      deliveredCents,
      deliveredMinutes,
    );
  }

  /// Hay horas sin tarifa en meses sin cobrar: el total está incompleto.
  bool get hasUnpriced =>
      months.any((m) => m.status != MonthStatus.paid && !m.isComplete);

  /// Meses ya terminados (anteriores a [today]) que siguen sin entregar.
  List<MonthLine> unsubmittedBefore(DateTime today) {
    final current = YearMonth.of(today);
    return [
      for (final m in months)
        if (m.month.compareTo(current) < 0 && m.status == MonthStatus.open) m,
    ];
  }

  /// Meses entregados que aún no se han cobrado (006, RF-2).
  List<MonthLine> get deliveredUnpaid => [
    for (final m in months)
      if (m.status == MonthStatus.delivered) m,
  ];
}

/// Una línea del desglose: horas de un tipo a una tarifa (018, RF-2).
class BreakdownLine {
  const BreakdownLine(this.kind, this.rateCents, this.minutes);
  final DayKind kind;
  final int rateCents;
  final int minutes;

  /// Importe de la línea, redondeado una vez.
  int get cents => amountCents(minutes, rateCents);
}

/// La cuenta de unos meses (los sin cobrar, o solo los entregados): una
/// línea por tipo y tarifa, las horas sin tarifa y el redondeo que hace
/// cuadrar las líneas con el total (018, RF-1 a RF-4). Lo apartado ya está
/// restado de las normales.
class HoursBreakdown {
  HoursBreakdown._(
    this.lines,
    this.unpricedMinutes,
    this.totalCents,
    this.roundingCents,
  );

  factory HoursBreakdown.of(Iterable<MonthLine> months) {
    final byRate = <(DayKind, int), int>{};
    var unpriced = 0;
    void add(DayKind kind, int? rate, int minutes) {
      if (minutes == 0) return;
      if (rate == null) {
        unpriced += minutes;
      } else {
        byRate.update(
          (kind, rate),
          (v) => v + minutes,
          ifAbsent: () => minutes,
        );
      }
    }

    for (final m in months) {
      if (m.imported case final i?) {
        for (final k in DayKind.values) {
          add(k, i.rateOf(k), i.month.minutesOf(k));
        }
      } else {
        for (final d in m.days) {
          add(d.entry.kind, d.rateCents, d.entry.minutes);
        }
      }
      for (final s in m.setAside) {
        add(DayKind.normal, s.rateCents, -s.move.minutes);
      }
    }
    final keys = byRate.keys.toList()
      ..sort(
        (a, b) => a.$1 != b.$1
            ? a.$1.index.compareTo(b.$1.index)
            : a.$2.compareTo(b.$2),
      );
    final lines = [
      for (final k in keys)
        if (byRate[k] != 0) BreakdownLine(k.$1, k.$2, byRate[k]!),
    ];
    final total = months.fold(0, (s, m) => s + m.amountCents);
    final sum = lines.fold(0, (s, l) => s + l.cents);
    return HoursBreakdown._(lines, unpriced, total, total - sum);
  }

  final List<BreakdownLine> lines;

  /// Horas sin tarifa: no están en el importe (RF-4).
  final int unpricedMinutes;

  /// Lo que valen los meses: su suma (la que cuenta).
  final int totalCents;

  /// Lo que falta sumar a las líneas para llegar al total (RF-3).
  final int roundingCents;

  bool get isEmpty => lines.isEmpty && unpricedMinutes == 0;
}

/// Por qué no se pueden apartar horas de un mes (008, RF-6, RF-7).
enum SetAsideProblem {
  noRate('Falta la tarifa normal en esa fecha.'),
  notOpen(
    'Ese mes ya está entregado o cobrado: no se puede cambiar lo apartado.',
  ),
  tooMany('Ese mes no tiene tantas horas normales sin apartar.');

  const SetAsideProblem(this.message);
  final String message;
}

/// ¿Se puede guardar [move] (un apartado) en su mes? [line] es el mes calculado
/// sin [move] (nulo si no tiene horas). Nulo si se puede.
SetAsideProblem? checkSetAside(
  SavedMove move,
  MonthLine? line,
  Iterable<Rate> rates,
) {
  if (rateFor(DayKind.normal, move.date, rates) == null) {
    return SetAsideProblem.noRate;
  }
  if (line != null && line.status != MonthStatus.open) {
    return SetAsideProblem.notOpen;
  }
  final free = line == null
      ? 0
      : line.minutesOf(DayKind.normal) - line.setAsideMinutes;
  return move.minutes > free ? SetAsideProblem.tooMany : null;
}

/// Horas apartadas a los cajones en [month] (008, RF-8).
int setAsideMinutesIn(Iterable<SavedMove> moves, YearMonth month) => moves
    .where(
      (m) => m.kind == SavedMoveKind.setAside && YearMonth.of(m.date) == month,
    )
    .fold(0, (sum, m) => sum + m.minutes);
