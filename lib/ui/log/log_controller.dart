// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';

import '../../data/day_entry_repository.dart';
import '../../domain/day_entry.dart';
import '../../domain/day_kind.dart';
import '../../domain/holidays.dart';
import '../../domain/hour_options.dart';
import '../../domain/money.dart';
import '../../domain/month_summary.dart';
import '../../domain/reason_suggestions.dart';
import '../../domain/saved_hours.dart';
import '../format.dart';

enum LogStatus { loading, ready, error }

/// Qué opción del selector corresponde al día elegido (RF-2, RF-4).
enum DayOption { today, yesterday, dayBefore, other }

/// Aviso al intentar apuntar en un mes del Excel (016, RF-4).
const importedMonthBlockedMessage =
    'Este mes viene del Excel como total: no se pueden añadir días.';

/// Estado y acciones de la pantalla de apuntar.
///
/// Cada cambio se ve al momento y se guarda detrás, en una cola que respeta
/// el orden de los toques. Si un guardado falla, el día vuelve a lo último
/// que se guardó bien y se avisa (RF-25).
class LogController extends ChangeNotifier {
  LogController(
    this._repo, {
    DateTime Function()? clock,
    HolidayCalendar Function()? calendar,
    Future<List<SavedMove>> Function()? savedMoves,
  }) : _clock = clock ?? DateTime.now,
       _calendar = calendar,
       _savedMoves = savedMoves;

  final DayEntryRepository _repo;

  /// Las horas guardadas, para no dejar un mes por debajo de lo apartado
  /// (008, RF-8). Si es nulo, no se comprueba.
  final Future<List<SavedMove>> Function()? _savedMoves;
  final HolidayCalendar Function()? _calendar;
  final DateTime Function() _clock;

  /// Se llama cuando un cambio no se ha podido guardar (RF-25).
  VoidCallback? onSaveFailed;

  /// Se llama con el aviso cuando un cambio no se guarda porque el mes
  /// quedaría con menos horas normales que las apartadas (008, RF-8).
  void Function(String message)? onSetAsideBlocked;

  /// Si es verdadero para un día, su mes viene del Excel y no se apuntan
  /// días en él (016, RF-4).
  bool Function(DateTime date)? isImportedMonth;

  /// Se llama cuando no se han podido leer los días de otro mes.
  VoidCallback? onReadFailed;

  /// Se llama tras guardar o borrar un día con éxito (para las copias).
  VoidCallback? onDataChanged;

  LogStatus status = LogStatus.loading;
  DateTime today = _dateOnly(DateTime.now());
  DateTime selectedDate = _dateOnly(DateTime.now());

  /// El primer día que se puede elegir en el calendario (RF-3).
  DateTime get firstSelectableDate => DateTime(2020);

  final _shown = <String, DayEntry>{}; // lo que se ve
  final _saved = <String, DayEntry>{}; // lo confirmado en la base de datos
  final _pending = <String, int>{}; // guardados aún en cola, por día
  final _loadedMonths = <int>{};
  Map<String, int> _reasonUsage = const {};
  DayKind? _pendingKind; // tipo elegido en un día aún sin horas
  DayEntry? _lastDeleted;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  // --- Lectura ---------------------------------------------------------

  DayEntry? get selectedEntry => _shown[dateKey(selectedDate)];
  int get selectedMinutes => selectedEntry?.minutes ?? 0;
  String? get selectedReason => selectedEntry?.reason;
  bool get canEditReason => selectedEntry != null;
  bool get canUndo => _lastDeleted != null;

  /// El tipo guardado; si el día no tiene horas, el elegido o el propuesto.
  DayKind get selectedKind =>
      selectedEntry?.kind ??
      _pendingKind ??
      suggestedKindFor(selectedDate, calendar: _calendar?.call());

  /// El festivo del día elegido, si lo es (004, RF-7).
  Holiday? get selectedHoliday => _calendar?.call().holidayOn(selectedDate);

  DayOption get dayOption => switch (_daysBetween(selectedDate, today)) {
    0 => DayOption.today,
    1 => DayOption.yesterday,
    2 => DayOption.dayBefore,
    _ => DayOption.other,
  };

  MonthSummary get monthSummary => MonthSummary.of(
    _shown.values,
    year: selectedDate.year,
    month: selectedDate.month,
  );

  /// Los días con horas de un mes, para el calendario (RF-28). Nulo si no
  /// se han podido leer.
  Future<List<DayEntry>?> monthEntries(int year, int month) async {
    try {
      await _loadMonth(DateTime(year, month));
    } catch (_) {
      return null;
    }
    return _shown.values
        .where((e) => e.date.year == year && e.date.month == month)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<String> suggestionsFor(String query) =>
      suggestReasons(query, _reasonUsage);

  /// Termina cuando no queda nada por guardar.
  Future<void> get idle async {
    while (true) {
      final current = _queue;
      await current;
      if (identical(current, _queue)) return;
    }
  }

  // --- Arranque y día --------------------------------------------------

  /// Lee los datos y elige hoy (RF-1). Si falla, no toca nada (RF-26).
  Future<void> load() async {
    // Al arrancar ya está en «cargando»: no se avisa mientras se construye
    // la pantalla.
    if (status != LogStatus.loading) {
      status = LogStatus.loading;
      _notify();
    }
    try {
      _shown.clear();
      _saved.clear();
      _loadedMonths.clear();
      today = _dateOnly(_clock());
      await _loadAround(today);
      _reasonUsage = await _repo.reasonUsage();
      selectedDate = today;
      _pendingKind = null;
      status = LogStatus.ready;
    } catch (_) {
      status = LogStatus.error;
    }
    _notify();
  }

  /// Elige un día entre el 1-1-2020 y hoy (RF-3).
  Future<void> selectDate(DateTime date) async {
    final d = _dateOnly(date);
    if (d.isAfter(today) || d.isBefore(firstSelectableDate)) return;
    try {
      await _loadMonth(d);
    } catch (_) {
      onReadFailed?.call();
      return;
    }
    if (d == selectedDate) return;
    selectedDate = d;
    _pendingKind = null;
    _notify();
  }

  /// Si ha cambiado la fecha (p. ej. tras medianoche), recalcula Hoy y lo
  /// elige (RF-5).
  Future<void> refreshToday() async {
    final now = _dateOnly(_clock());
    if (now == today) return;
    today = now;
    try {
      await _loadAround(now);
    } catch (_) {
      onReadFailed?.call();
    }
    selectedDate = now;
    _pendingKind = null;
    _notify();
  }

  // --- Cambios ---------------------------------------------------------

  /// Guarda el total del día, sustituyendo el que hubiera (RF-7, RF-10).
  void setMinutes(int minutes) {
    if (!isValidChoice(minutes)) {
      throw ArgumentError.value(minutes, 'minutes', 'no es una media hora');
    }
    final entry = selectedEntry;
    if (entry?.minutes == minutes) return;
    _change(
      selectedDate,
      entry?.copyWith(minutes: minutes) ??
          DayEntry(date: selectedDate, minutes: minutes, kind: selectedKind),
    );
  }

  /// Alterna Normal y Festiva; sin horas, solo cambia lo que se ve (RF-12).
  void toggleKind() {
    final next = selectedKind == DayKind.festive
        ? DayKind.normal
        : DayKind.festive;
    final entry = selectedEntry;
    if (entry == null) {
      _pendingKind = next;
      _notify();
      return;
    }
    _change(selectedDate, entry.copyWith(kind: next));
  }

  /// Guarda el motivo limpio; solo si el día tiene horas (RF-14, RF-17).
  /// [date] sirve para terminar de guardar lo escrito en un día después de
  /// haber cambiado a otro; si es nulo, es el día elegido.
  void setReason(String text, {DateTime? date}) {
    final day = date == null ? selectedDate : _dateOnly(date);
    final entry = _shown[dateKey(day)];
    if (entry == null) return;
    final reason = normalizeReason(text);
    if (reason == entry.reason) return;
    _change(day, entry.copyWith(reason: () => reason));
  }

  /// Borra el día entero y devuelve lo borrado, o nulo si no había nada
  /// (RF-18).
  DayEntry? deleteSelected() {
    final entry = selectedEntry;
    if (entry == null) return null;
    _change(selectedDate, null);
    _lastDeleted = entry;
    return entry;
  }

  /// Devuelve el último día borrado tal como estaba y lo muestra (RF-19).
  Future<void> undoDelete() async {
    final entry = _lastDeleted;
    if (entry == null) return;
    selectedDate = entry.date;
    _pendingKind = null;
    _change(entry.date, entry);
  }

  // --- Por dentro ------------------------------------------------------

  /// Cualquier cambio de datos quita la posibilidad de deshacer (RF-20).
  void _change(DateTime date, DayEntry? value) {
    final key = dateKey(date);
    _lastDeleted = null;
    _put(_shown, key, value);
    _pending[key] = (_pending[key] ?? 0) + 1;
    _notify();
    _queue = _queue.then((_) => _write(key, date, value));
  }

  Future<void> _write(String key, DateTime date, DayEntry? value) async {
    var failed = false;
    String? blocked;
    try {
      blocked = value != null && (isImportedMonth?.call(date) ?? false)
          ? importedMonthBlockedMessage
          : await _setAsideBlock(key, date, value);
      if (blocked != null) {
        // No se guarda: se vuelve a lo guardado, como en un fallo.
      } else if (value == null) {
        await _repo.delete(date);
      } else {
        await _repo.save(value);
      }
      if (blocked == null) {
        _put(_saved, key, value);
        onDataChanged?.call();
      }
    } catch (_) {
      failed = true; // sin datos personales en ningún registro
    }
    final left = _pending[key]! - 1;
    if (left == 0) {
      _pending.remove(key);
      // Sin más cambios en cola, se ve exactamente lo guardado.
      _put(_shown, key, _saved[key]);
    } else {
      _pending[key] = left;
    }
    if (failed || blocked != null) {
      if (_lastDeleted != null && dateKey(_lastDeleted!.date) == key) {
        _lastDeleted = null;
      }
      if (blocked != null) {
        onSetAsideBlocked?.call(blocked);
      } else {
        onSaveFailed?.call();
      }
    } else {
      try {
        _reasonUsage = await _repo.reasonUsage();
      } catch (_) {
        // Las sugerencias pueden esperar al siguiente guardado.
      }
    }
    _notify();
  }

  /// El aviso si guardar [value] en [date] deja su mes con menos horas
  /// normales que las apartadas a los cajones; nulo si se puede guardar
  /// (008, RF-8). Solo se frena un cambio que baja las horas normales.
  Future<String?> _setAsideBlock(
    String key,
    DateTime date,
    DayEntry? value,
  ) async {
    final read = _savedMoves;
    if (read == null) return null;
    int normal(DayEntry? e) =>
        e != null && e.kind == DayKind.normal ? e.minutes : 0;
    final before = _saved[key];
    if (normal(value) >= normal(before)) return null;
    final month = YearMonth.of(date);
    final moves = [
      for (final m in await read())
        if (m.kind == SavedMoveKind.setAside && YearMonth.of(m.date) == month)
          m,
    ];
    if (moves.isEmpty) return null;
    final monthNormal = _saved.values
        .where((e) => YearMonth.of(e.date) == month)
        .fold(0, (sum, e) => sum + normal(e));
    final apart = setAsideMinutesIn(moves, month);
    if (monthNormal - normal(before) + normal(value) >= apart) return null;
    return setAsideBlockedMessage(moves);
  }

  Future<void> _loadAround(DateTime day) async {
    await _loadMonth(day);
    await _loadMonth(DateTime(day.year, day.month, day.day - 2));
  }

  Future<void> _loadMonth(DateTime d) async {
    final id = d.year * 12 + d.month;
    if (_loadedMonths.contains(id)) return;
    final entries = await _repo.entriesInMonth(d.year, d.month);
    for (final e in entries) {
      final key = dateKey(e.date);
      _saved[key] = e;
      if (!_pending.containsKey(key)) _shown[key] = e;
    }
    _loadedMonths.add(id);
  }

  static void _put(Map<String, DayEntry> map, String key, DayEntry? value) {
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Días enteros entre dos fechas, sin que el cambio de hora lo descuadre.
int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// «Has apartado X h de este mes a (cajón). Quita antes ese apartado.»
/// (008, RF-8).
String setAsideBlockedMessage(List<SavedMove> moves) {
  final minutes = moves.fold(0, (sum, m) => sum + m.minutes);
  final boxes = [
    for (final b in SavedBox.values)
      if (moves.any((m) => m.box == b)) b.label,
  ];
  return 'Has apartado ${formatMinutes(minutes)} h de este mes a ${boxes.join(' y ')}. '
      'Quita antes ese apartado.';
}
