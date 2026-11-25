import '../domain/company.dart';
import '../domain/day_entry.dart';
import '../domain/extras.dart';
import '../domain/imported_month.dart';
import '../domain/money.dart';
import '../domain/saved_hours.dart';
import '../domain/vacations.dart';
import 'backup_file.dart';

/// Una cosa que cambia: cómo está aquí y cómo viene en la copia. Nulo en un
/// lado si allí no está.
class DiffPair<T> {
  const DiffPair(this.here, this.there);
  final T? here;
  final T? there;
}

/// Lo que cambiaría cada apartado al cargar una copia (025, RF-10, RF-12,
/// RF-12b). Cada lista va ordenada por fecha (o por mes).
class BackupDiff {
  const BackupDiff({
    this.days = const [],
    this.vacationDays = const [],
    this.vacationSettings,
    this.items = const [],
    this.savedMoves = const [],
    this.rates = const [],
    this.months = const [],
    this.importedMonths = const [],
    this.company,
  });

  final List<DiffPair<DayEntry>> days;
  final List<DiffPair<VacationDay>> vacationDays;

  /// Los ajustes de vacaciones, solo si cambian.
  final DiffPair<VacationSettings>? vacationSettings;
  final List<DiffPair<ExtraItem>> items;
  final List<DiffPair<SavedMove>> savedMoves;
  final List<DiffPair<Rate>> rates;

  /// Meses entregados o cobrados; nulo en un lado = abierto.
  final List<DiffPair<MonthRecord>> months;
  final List<DiffPair<ImportedMonth>> importedMonths;

  /// La empresa, solo si cambia (026, RF-9).
  final DiffPair<Company>? company;

  int get hours => days.length;
  int get vacation => vacationDays.length + (vacationSettings == null ? 0 : 1);
  int get extras => items.length;
  int get saved => savedMoves.length;
  int get ratesAndMonths => rates.length + months.length;
  int get imported => importedMonths.length;

  /// Cuántos datos de la empresa cambian: nombre, fecha o los dos.
  int get companyChanges {
    final c = company;
    if (c == null) return 0;
    final a = c.here ?? Company.empty;
    final b = c.there ?? Company.empty;
    return (a.name != b.name ? 1 : 0) + (a.start != b.start ? 1 : 0);
  }

  /// La copia trae lo mismo que hay (RF-10).
  bool get isEmpty => sections.every((s) => s.count == 0);

  /// Los apartados en el orden del diálogo (RF-12).
  List<({DiffSection section, String label, int count})> get sections => [
    (section: DiffSection.hours, label: 'Horas', count: hours),
    (section: DiffSection.vacation, label: 'Vacaciones', count: vacation),
    (section: DiffSection.extras, label: 'Multas y extras', count: extras),
    (section: DiffSection.saved, label: 'Horas guardadas', count: saved),
    (
      section: DiffSection.ratesAndMonths,
      label: 'Tarifas y meses',
      count: ratesAndMonths,
    ),
    (section: DiffSection.imported, label: 'Meses del Excel', count: imported),
    (section: DiffSection.company, label: 'Empresa', count: companyChanges),
  ];
}

enum DiffSection {
  hours,
  vacation,
  extras,
  saved,
  ratesAndMonths,
  imported,
  company,
}

/// Compara lo que hay ahora ([current], leído completo) con una copia
/// ([incoming]). No cuenta las marcas internas de modificación. Un apartado
/// que la copia no trae (copia de una versión antigua) se trata como lo
/// trata el restaurar: si se conserva lo actual, «igual»; si se vacía, cada
/// cosa actual cuenta como distinta.
BackupDiff compareBackups(BackupData current, BackupData incoming) {
  final now = current.extras;
  final other = incoming.extras;
  final days = _pairs<DayEntry, DateTime>(
    [for (final d in current.days) d.entry],
    [for (final d in incoming.days) d.entry],
    (e) => e.date,
  );
  if (other == null || now == null) {
    // Copia v1: solo trae días; lo demás se conserva al restaurar.
    return BackupDiff(days: days);
  }

  var vacationDays = <DiffPair<VacationDay>>[];
  DiffPair<VacationSettings>? settings;
  final v = now.vacation;
  final w = other.vacation;
  if (v != null && w != null) {
    vacationDays = _pairs<VacationDay, DateTime>(v.days, w.days, (d) => d.date);
    if (v.settings != w.settings) settings = DiffPair(v.settings, w.settings);
  }

  List<DiffPair<T>> optional<T, K extends Comparable<Object>>(
    List<T>? a,
    List<T>? b,
    K Function(T) key,
  ) => a == null || b == null ? const [] : _pairs(a, b, key);

  return BackupDiff(
    days: days,
    vacationDays: vacationDays,
    vacationSettings: settings,
    items: optional<ExtraItem, _DateId>(
      now.items,
      other.items,
      (e) => _DateId(e.date, e.id ?? 0),
    ),
    savedMoves: optional<SavedMove, _DateId>(
      now.savedMoves,
      other.savedMoves,
      (m) => _DateId(m.date, m.id ?? 0),
    ),
    rates: _pairs<Rate, _DateId>(
      now.rates,
      other.rates,
      (r) => _DateId(r.start, r.kind.index),
    ),
    months: _pairs<MonthRecord, YearMonth>(
      [
        for (final m in now.months)
          if (m.status != MonthStatus.open) m,
      ],
      [
        for (final m in other.months)
          if (m.status != MonthStatus.open) m,
      ],
      (m) => m.month,
      same: (a, b) => a.deliveredOn == b.deliveredOn && a.paidOn == b.paidOn,
    ),
    importedMonths: optional<ImportedMonth, YearMonth>(
      now.importedMonths,
      other.importedMonths,
      (m) => m.month,
    ),
    company:
        now.company == null ||
            other.company == null ||
            now.company == other.company
        ? null
        : DiffPair(now.company, other.company),
  );
}

/// Clave por fecha y un número (id o tipo), para ordenar por fecha.
class _DateId implements Comparable<Object> {
  const _DateId(this.date, this.n);
  final DateTime date;
  final int n;

  @override
  int compareTo(Object other) {
    final o = other as _DateId;
    final byDate = date.compareTo(o.date);
    return byDate != 0 ? byDate : n.compareTo(o.n);
  }

  @override
  bool operator ==(Object other) =>
      other is _DateId && other.date == date && other.n == n;

  @override
  int get hashCode => Object.hash(date, n);
}

/// Lo que está solo en un lado o con otro valor, ordenado por la clave.
List<DiffPair<T>> _pairs<T, K extends Comparable<Object>>(
  List<T> a,
  List<T> b,
  K Function(T) key, {
  bool Function(T, T)? same,
}) {
  final eq = same ?? (T x, T y) => x == y;
  final here = {for (final x in a) key(x): x};
  final there = {for (final y in b) key(y): y};
  final keys = {...here.keys, ...there.keys}.toList()..sort();
  return [
    for (final k in keys)
      if (here[k] == null ||
          there[k] == null ||
          !eq(here[k] as T, there[k] as T))
        DiffPair<T>(here[k], there[k]),
  ];
}
