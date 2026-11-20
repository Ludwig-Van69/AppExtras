/// Horas guardadas (008): la bolsa de empresa y mi reserva. Son horas
/// normales que no se cobran en su mes y que salen más tarde como tiempo libre
/// o cobradas en dinero. El saldo de cada cajón es la suma de sus movimientos;
/// nunca se guarda aparte, para que no se descuadre. Todo en minutos y
/// céntimos enteros (principio 8).
library;

import 'day_entry.dart';
import 'day_kind.dart';
import 'money.dart';

/// Máximo de un movimiento: 999 h (RF-3).
const maxSavedMinutes = 999 * 60;

/// Longitud máxima de la nota (RF-2).
const maxSavedNoteLength = 60;

/// Primer día que se puede apuntar (RF-3).
final firstSavedDate = DateTime(2020);

/// Los dos cajones (RF-1). Funcionan igual: solo cambia el nombre.
enum SavedBox {
  company('Bolsa de empresa'),
  own('Mi reserva');

  const SavedBox(this.label);
  final String label;
}

/// Los cuatro movimientos (RF-2): dos entradas y dos salidas.
enum SavedMoveKind {
  before('Horas de antes', isIn: true),
  setAside('Apartar', isIn: true),
  timeOff('Tiempo libre', isIn: false),
  paid('Cobrar', isIn: false);

  const SavedMoveKind(this.label, {required this.isIn});
  final String label;
  final bool isIn;
}

/// Por qué no se puede guardar lo escrito (RF-3).
enum SavedProblem {
  hours('Elige entre 0,5 y 999 h, en medias horas.'),
  note('La nota puede tener hasta 60 letras.'),
  date('La fecha debe estar entre el 1-1-2020 y hoy.');

  const SavedProblem(this.message);
  final String message;
}

/// Comprueba lo que escribe el usuario. [minutes] es nulo si no se entiende.
/// Devuelve el primer problema, o nulo si se puede guardar.
SavedProblem? validateSavedMove({
  required int? minutes,
  required DateTime date,
  required DateTime today,
  String? note,
}) {
  if (minutes == null ||
      minutes < 30 ||
      minutes > maxSavedMinutes ||
      minutes % 30 != 0) {
    return SavedProblem.hours;
  }
  if ((note?.trim().length ?? 0) > maxSavedNoteLength) return SavedProblem.note;
  final day = _day(date);
  if (day.isBefore(firstSavedDate) || day.isAfter(_day(today))) {
    return SavedProblem.date;
  }
  return null;
}

/// Un movimiento de un cajón. [minutes] siempre es positivo; el signo lo da
/// [kind]. [cents] es el importe congelado de un cobro (RF-9), y solo lo
/// lleva un cobro.
class SavedMove {
  SavedMove({
    this.id,
    required this.box,
    required this.kind,
    required DateTime date,
    required this.minutes,
    String? note,
    this.cents,
  }) : date = _day(date),
       note = _cleanNote(note) {
    if (minutes < 1 || minutes > maxSavedMinutes) {
      throw ArgumentError.value(minutes, 'minutes', 'fuera de rango');
    }
    if ((kind == SavedMoveKind.paid) != (cents != null)) {
      throw ArgumentError('Solo un cobro lleva importe.');
    }
    if (cents != null && cents! < 0) {
      throw ArgumentError.value(cents, 'cents', 'negativo');
    }
    if ((this.note?.length ?? 0) > maxSavedNoteLength) {
      throw ArgumentError.value(note, 'note', 'demasiado larga');
    }
  }

  /// Nulo hasta que se guarda por primera vez.
  final int? id;
  final SavedBox box;
  final SavedMoveKind kind;
  final DateTime date;
  final int minutes;

  /// Nota opcional, ya limpia; nula si no hay.
  final String? note;
  final int? cents;

  /// Con su signo: las salidas restan.
  int get signedMinutes => kind.isIn ? minutes : -minutes;

  @override
  bool operator ==(Object other) =>
      other is SavedMove &&
      other.id == id &&
      other.box == box &&
      other.kind == kind &&
      other.date == date &&
      other.minutes == minutes &&
      other.note == note &&
      other.cents == cents;

  @override
  int get hashCode => Object.hash(id, box, kind, date, minutes, note, cents);
}

/// Importe congelado de un cobro: horas × tarifa normal del día del cobro,
/// redondeado una vez (RF-9). Nulo si ese día no había tarifa normal (RF-10).
int? savedPaidCents(int minutes, DateTime date, Iterable<Rate> rates) {
  final rate = rateFor(DayKind.normal, date, rates);
  return rate == null ? null : amountCents(minutes, rate.cents);
}

/// Meses con más horas apartadas que horas apuntadas, del más antiguo al
/// más reciente. Pasa al restaurar una copia antigua que no traía los
/// apartados (013, RF-16).
List<YearMonth> monthsShortOfSetAside(
  Iterable<DayEntry> days,
  Iterable<SavedMove> moves,
) {
  final logged = <YearMonth, int>{};
  for (final d in days) {
    final m = YearMonth.of(d.date);
    logged[m] = (logged[m] ?? 0) + d.minutes;
  }
  final setAside = <YearMonth, int>{};
  for (final m in moves) {
    if (m.kind != SavedMoveKind.setAside) continue;
    final ym = YearMonth.of(m.date);
    setAside[ym] = (setAside[ym] ?? 0) + m.minutes;
  }
  return [
    for (final e in setAside.entries)
      if (e.value > (logged[e.key] ?? 0)) e.key,
  ]..sort();
}

/// Apartados que se quedarían sin precio si se borra [rate] (013, RF-15):
/// ninguna otra tarifa normal los cubriría.
List<SavedMove> setAsidesLeftUnpriced(
  Rate rate,
  Iterable<Rate> rates,
  Iterable<SavedMove> moves,
) => setAsidesUnpricedBy(rates, [
  for (final r in rates)
    if (!(r.kind == rate.kind && r.start == rate.start)) r,
], moves);

/// Los apartados que tienen precio con [before] y se quedarían sin él con
/// [after] (021, RF-6).
List<SavedMove> setAsidesUnpricedBy(
  Iterable<Rate> before,
  Iterable<Rate> after,
  Iterable<SavedMove> moves,
) => [
  for (final m in moves)
    if (m.kind == SavedMoveKind.setAside &&
        rateFor(DayKind.normal, m.date, before) != null &&
        rateFor(DayKind.normal, m.date, after) == null)
      m,
];

/// Saldo de [box] al final de [date], con todos los movimientos hasta ese día.
int savedBalanceOn(Iterable<SavedMove> moves, SavedBox box, DateTime date) {
  final day = _day(date);
  return moves
      .where((m) => m.box == box && !m.date.isAfter(day))
      .fold(0, (sum, m) => sum + m.signedMinutes);
}

/// Lo máximo que puede salir de [box] en [date] sin que el saldo baje de 0 ni
/// ese día ni ningún día posterior (RF-4). [moves] no debe incluir el
/// movimiento que se está comprobando.
int savedAvailable(Iterable<SavedMove> moves, SavedBox box, DateTime date) {
  final day = _day(date);
  final dates = {
    day,
    for (final m in moves)
      if (m.box == box && m.date.isAfter(day)) m.date,
  };
  return dates
      .map((d) => savedBalanceOn(moves, box, d))
      .reduce((a, b) => a < b ? a : b);
}

/// Un cajón que se queda en negativo: en qué cajón y desde qué día.
class SavedShortfall {
  const SavedShortfall(this.box, this.date);
  final SavedBox box;
  final DateTime date;

  @override
  bool operator ==(Object other) =>
      other is SavedShortfall && other.box == box && other.date == date;

  @override
  int get hashCode => Object.hash(box, date);
}

/// El primer día en que algún cajón queda por debajo de 0, o nulo si todo
/// cuadra (RF-4). Se mira el saldo al final de cada día.
SavedShortfall? findSavedShortfall(Iterable<SavedMove> moves) {
  for (final box in SavedBox.values) {
    final dates = {
      for (final m in moves)
        if (m.box == box) m.date,
    }.toList()..sort();
    for (final d in dates) {
      if (savedBalanceOn(moves, box, d) < 0) return SavedShortfall(box, d);
    }
  }
  return null;
}

/// Lo que se ve de un vistazo (RF-12, RF-13, RF-16).
class SavedSummary {
  SavedSummary._(
    this.balances,
    this.values,
    this.compensatedMinutes,
    this.paidMinutes,
    this.paidCents,
  );

  /// [today] fija la tarifa con que se valora lo que queda: la normal de hoy.
  factory SavedSummary.of(
    Iterable<SavedMove> moves,
    Iterable<Rate> rates,
    DateTime today,
  ) {
    final rate = rateFor(DayKind.normal, today, rates);
    final balances = {
      for (final b in SavedBox.values)
        b: moves
            .where((m) => m.box == b)
            .fold(0, (sum, m) => sum + m.signedMinutes),
    };
    var compensated = 0;
    var paid = 0;
    var paidCents = 0;
    for (final m in moves) {
      if (m.kind == SavedMoveKind.timeOff) compensated += m.minutes;
      if (m.kind == SavedMoveKind.paid) {
        paid += m.minutes;
        paidCents += m.cents!;
      }
    }
    return SavedSummary._(
      balances,
      {
        for (final b in SavedBox.values)
          b: rate == null ? null : amountCents(balances[b]!, rate.cents),
      },
      compensated,
      paid,
      paidCents,
    );
  }

  /// Saldo de cada cajón, en minutos.
  final Map<SavedBox, int> balances;

  /// Valor de cada cajón a la tarifa normal de hoy; nulo si falta la tarifa.
  final Map<SavedBox, int?> values;

  final int compensatedMinutes;
  final int paidMinutes;
  final int paidCents;

  int get totalMinutes => balances.values.fold(0, (a, b) => a + b);

  /// Suma de los valores de cada cajón, para que cuadre con lo que se ve.
  /// Nulo si falta la tarifa (RF-16).
  int? get totalValueCents => values.values.any((v) => v == null)
      ? null
      : values.values.fold<int>(0, (a, b) => a + b!);

  bool get isEmpty =>
      totalMinutes == 0 && compensatedMinutes == 0 && paidMinutes == 0;
}

/// Del más reciente al más antiguo (RF-13). A igual fecha, el apuntado
/// después va arriba.
List<SavedMove> sortSavedMoves(Iterable<SavedMove> moves) =>
    moves.toList()..sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      return (b.id ?? 1 << 31).compareTo(a.id ?? 1 << 31);
    });

String? _cleanNote(String? note) {
  final n = note?.trim();
  return n == null || n.isEmpty ? null : n;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Por qué no se puede guardar [move] en lugar de [old] (o, si [move] es
/// nulo, borrar [old]); nulo si se puede. [all] son todos los movimientos
/// guardados, y [entries], [rates] y [records], los días, tarifas y meses
/// (RF-4, RF-7). El importe de un cobro lo pone quien llama.
String? checkSavedMove({
  required SavedMove? move,
  SavedMove? old,
  required Iterable<SavedMove> all,
  required Iterable<DayEntry> entries,
  required Iterable<Rate> rates,
  required Iterable<MonthRecord> records,
}) {
  final others = [
    for (final m in all)
      if (old == null || m.id != old.id) m,
  ];
  // Cambiar solo la nota siempre se puede.
  final onlyNote =
      old != null &&
      move != null &&
      move.kind == old.kind &&
      move.box == old.box &&
      move.date == old.date &&
      move.minutes == old.minutes;
  if (onlyNote) return null;
  // Un apartado de un mes ya entregado o cobrado no se toca.
  if (old != null && old.kind == SavedMoveKind.setAside) {
    final month = YearMonth.of(old.date);
    final closed = records.any(
      (r) => r.month == month && r.status != MonthStatus.open,
    );
    if (closed) return SetAsideProblem.notOpen.message;
  }
  if (move != null && move.kind == SavedMoveKind.setAside) {
    final month = YearMonth.of(move.date);
    final lines = MoneyOverview.compute(
      entries: entries.where((e) => YearMonth.of(e.date) == month),
      rates: rates,
      records: records,
      savedMoves: others,
    ).months;
    final problem = checkSetAside(move, lines.firstOrNull, rates);
    if (problem != null) return problem.message;
  }
  final after = [...others, ?move];
  final short = findSavedShortfall(after);
  if (short == null) return null;
  if (move != null && !move.kind.isIn && move.box == short.box) {
    final free = savedAvailable(others, move.box, move.date);
    return 'Solo hay ${_hours(free < 0 ? 0 : free)} h en ${move.box.label} '
        'a esa fecha.';
  }
  return 'Esas horas de ${short.box.label} ya han salido. Quita antes la '
      'salida.';
}

/// «39» o «2,5».
String _hours(int minutes) =>
    '${minutes ~/ 60}${minutes % 60 == 0 ? '' : ',${minutes % 60 * 10 ~/ 60}'}';
