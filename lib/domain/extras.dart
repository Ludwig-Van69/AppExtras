/// Multas y extras (007): dinero que no son horas y que no es seguro. Las
/// multas (de tráfico, que en teoría debes a la empresa) restan y los extras
/// (que la empresa te debe aparte de las horas) suman, siempre en un total
/// aparte de «A cobrar por horas» (principio 9). Todo en céntimos enteros.
library;

/// Importe máximo de un apunte: 10.000 €, en céntimos (RF-3).
const maxExtraCents = 1000000;

/// Longitud máxima del concepto (RF-3).
const maxConceptLength = 60;

/// Primer día que se puede apuntar (RF-3).
final firstExtraDate = DateTime(2020);

enum ExtraType { fine, bonus }

/// Pendiente; cerrada (multa descontada o extra cobrado, con fecha); o
/// anulada (multa anulada o extra descartado). Solo cuentan las pendientes.
enum ExtraStatus { pending, closed, cancelled }

/// Por qué no se puede guardar lo escrito (RF-3).
enum ExtraProblem {
  amount('Escribe un importe entre 0,01 € y 10.000 €.'),
  concept('Escribe un concepto de hasta 60 letras.'),
  date('La fecha debe estar entre el 1-1-2020 y hoy.');

  const ExtraProblem(this.message);
  final String message;
}

/// Comprueba lo que escribe el usuario. [cents] es nulo si el importe no se
/// entiende. Devuelve el primer problema, o nulo si se puede guardar.
ExtraProblem? validateExtra({
  required int? cents,
  required String concept,
  required DateTime date,
  required DateTime today,
}) {
  if (cents == null || cents < 1 || cents > maxExtraCents) {
    return ExtraProblem.amount;
  }
  final c = concept.trim();
  if (c.isEmpty || c.length > maxConceptLength) return ExtraProblem.concept;
  final day = _day(date);
  if (day.isBefore(firstExtraDate) || day.isAfter(_day(today))) {
    return ExtraProblem.date;
  }
  return null;
}

/// Una multa o un extra. [cents] siempre es positivo; el signo lo da [type].
class ExtraItem {
  ExtraItem({
    this.id,
    required this.type,
    required DateTime date,
    required this.cents,
    required String concept,
    this.status = ExtraStatus.pending,
    DateTime? closedOn,
    this.earlyPayment = false,
    this.companyPays = false,
  }) : date = _day(date),
       concept = concept.trim(),
       closedOn = closedOn == null ? null : _day(closedOn) {
    if (cents < 1 || cents > maxExtraCents) {
      throw ArgumentError.value(cents, 'cents', 'fuera de rango');
    }
    if (this.concept.isEmpty || this.concept.length > maxConceptLength) {
      throw ArgumentError.value(concept, 'concept', 'vacío o largo');
    }
    if (type != ExtraType.fine && (earlyPayment || companyPays)) {
      throw ArgumentError(
        'Solo una multa tiene pronto pago o la paga la '
        'empresa.',
      );
    }
    if ((status == ExtraStatus.closed) != (closedOn != null)) {
      throw ArgumentError('Solo una cerrada lleva fecha de cierre.');
    }
  }

  /// Nulo hasta que se guarda por primera vez.
  final int? id;
  final ExtraType type;
  final DateTime date;
  final int cents;
  final String concept;
  final ExtraStatus status;
  final DateTime? closedOn;

  /// Multa pagada en plazo: cuenta la mitad (019, RF-2).
  final bool earlyPayment;

  /// Multa que paga la empresa: no cuenta (019, RF-4).
  final bool companyPays;

  /// Lo que cuenta: la mitad con pronto pago (el medio céntimo hacia
  /// arriba) y nada si la paga la empresa (019, RF-2, RF-4).
  int get dueCents => companyPays
      ? 0
      : earlyPayment
      ? (cents + 1) ~/ 2
      : cents;

  /// Con su signo: las multas restan.
  int get signedCents => type == ExtraType.fine ? -dueCents : dueCents;

  bool get isPending => status == ExtraStatus.pending;

  ExtraItem copyWith({
    int? id,
    ExtraType? type,
    DateTime? date,
    int? cents,
    String? concept,
    bool? earlyPayment,
    bool? companyPays,
  }) {
    final t = type ?? this.type;
    final fine = t == ExtraType.fine;
    return ExtraItem(
      id: id ?? this.id,
      type: t,
      date: date ?? this.date,
      cents: cents ?? this.cents,
      concept: concept ?? this.concept,
      status: status,
      closedOn: closedOn,
      earlyPayment: fine && (earlyPayment ?? this.earlyPayment),
      companyPays: fine && (companyPays ?? this.companyPays),
    );
  }

  /// El mismo apunte con otro estado; [on] es la fecha de cierre y solo se
  /// usa si [s] es cerrada.
  ExtraItem withStatus(ExtraStatus s, {DateTime? on}) => ExtraItem(
    id: id,
    type: type,
    date: date,
    cents: cents,
    concept: concept,
    status: s,
    closedOn: s == ExtraStatus.closed ? (on ?? closedOn ?? date) : null,
    earlyPayment: earlyPayment,
    companyPays: companyPays,
  );

  @override
  bool operator ==(Object other) =>
      other is ExtraItem &&
      other.id == id &&
      other.type == type &&
      other.date == date &&
      other.cents == cents &&
      other.concept == concept &&
      other.status == status &&
      other.closedOn == closedOn &&
      other.earlyPayment == earlyPayment &&
      other.companyPays == companyPays;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    date,
    cents,
    concept,
    status,
    closedOn,
    earlyPayment,
    companyPays,
  );
}

/// Lo pendiente de cobrar y de pagar (RF-7, RF-9).
class ExtrasTotals {
  const ExtrasTotals(this.pendingBonusCents, this.pendingFineCents);

  factory ExtrasTotals.of(Iterable<ExtraItem> items) {
    var bonus = 0;
    var fine = 0;
    for (final e in items) {
      if (!e.isPending) continue;
      if (e.type == ExtraType.fine) {
        fine += e.dueCents;
      } else {
        bonus += e.dueCents;
      }
    }
    return ExtrasTotals(bonus, fine);
  }

  final int pendingBonusCents;
  final int pendingFineCents;

  bool get isEmpty => pendingBonusCents == 0 && pendingFineCents == 0;

  /// «Con multas y extras»: lo que se cobraría por horas, más los extras y
  /// menos las multas pendientes. Puede ser negativo.
  int withHours(int toCollectCents) =>
      toCollectCents + pendingBonusCents - pendingFineCents;
}

/// La primera multa de cada año por fecha, sin contar las anuladas (019,
/// RF-3). A igual fecha, la apuntada antes. Devuelve sus ids.
Set<int> firstFinesOfYear(Iterable<ExtraItem> items) {
  final first = <int, ExtraItem>{};
  for (final e in items) {
    if (e.type != ExtraType.fine ||
        e.status == ExtraStatus.cancelled ||
        e.id == null) {
      continue;
    }
    final f = first[e.date.year];
    if (f == null ||
        e.date.isBefore(f.date) ||
        (e.date == f.date && e.id! < f.id!)) {
      first[e.date.year] = e;
    }
  }
  return {for (final e in first.values) e.id!};
}

/// Pendientes primero; en cada grupo, de la más reciente a la más antigua
/// (RF-6). A igual fecha, la apuntada después va arriba.
List<ExtraItem> sortExtras(Iterable<ExtraItem> items) =>
    items.toList()..sort((a, b) {
      if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      return (b.id ?? 1 << 31).compareTo(a.id ?? 1 << 31);
    });

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Nombre del estado según el tipo (RF-4): una multa se descuenta o se anula;
/// un extra se cobra o se descarta.
String extraStatusName(ExtraType type, ExtraStatus status) =>
    switch ((type, status)) {
      (_, ExtraStatus.pending) => 'Pendiente',
      (ExtraType.fine, ExtraStatus.closed) => 'Descontada',
      (ExtraType.fine, ExtraStatus.cancelled) => 'Anulada',
      (ExtraType.bonus, ExtraStatus.closed) => 'Cobrado',
      (ExtraType.bonus, ExtraStatus.cancelled) => 'Descartado',
    };

/// «Multa» o «Extra».
String extraTypeName(ExtraType type) =>
    type == ExtraType.fine ? 'Multa' : 'Extra';
