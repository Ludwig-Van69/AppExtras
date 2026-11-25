// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';

import '../../data/day_entry_repository.dart';
import '../../data/money_repository.dart';
import '../../data/saved_hours_repository.dart';
import '../../domain/day_entry.dart';
import '../../domain/day_kind.dart';
import '../../domain/money.dart';
import '../../domain/saved_hours.dart';

enum MoneyStatus { loading, ready, error }

/// Estado del dinero: tarifas, meses y totales (005). Cada cambio se guarda y
/// se vuelve a calcular todo desde lo guardado, así lo que se ve es siempre
/// lo que hay.
class MoneyController extends ChangeNotifier {
  MoneyController({
    required DayEntryRepository days,
    required MoneyRepository money,
    SavedHoursRepository? saved,
    DateTime Function()? clock,
    Future<bool> Function()? loadHidden,
    Future<void> Function(bool)? saveHidden,
    Future<void> Function()? onChanged,
  }) : _days = days,
       _money = money,
       _saved = saved,
       _clock = clock ?? DateTime.now,
       _loadHidden = loadHidden,
       _saveHidden = saveHidden,
       _onChanged = onChanged;

  final DayEntryRepository _days;
  final MoneyRepository _money;

  /// Las horas guardadas (008); si es nulo, no hay.
  final SavedHoursRepository? _saved;
  final DateTime Function() _clock;
  final Future<bool> Function()? _loadHidden;
  final Future<void> Function(bool)? _saveHidden;

  /// Avisa a las copias de que hay cambios sin copiar (003, RF-4).
  final Future<void> Function()? _onChanged;

  MoneyStatus status = MoneyStatus.loading;
  MoneyOverview overview = MoneyOverview.compute(
    entries: const [],
    rates: const [],
    records: const [],
  );
  List<Rate> rates = const [];

  /// Movimientos de las horas guardadas, del más reciente al más antiguo
  /// (008, RF-13), y su resumen (RF-12).
  List<SavedMove> savedMoves = const [];
  SavedSummary savedSummary = SavedSummary.of(const [], const [], DateTime(0));

  /// Hay horas guardadas que enseñar.
  bool get hasSavedHours => _saved != null;

  List<DayEntry> _entries = const [];
  List<MonthRecord> _records = const [];

  /// Los importes se enseñan como «•••• €» (RF-11).
  bool hideAmounts = false;

  /// Un guardado ha fallado; se avisa en pantalla.
  bool saveFailed = false;

  bool _disposed = false;

  DateTime get today => _clock();

  /// Hay al menos una tarifa de cada tipo.
  bool get hasRates =>
      DayKind.values.every((k) => rates.any((r) => r.kind == k));

  /// Lee todo y calcula. Si falla, queda en error y se puede reintentar.
  Future<void> load() async {
    if (status != MoneyStatus.ready) {
      status = MoneyStatus.loading;
      _notify();
    }
    try {
      hideAmounts = await (_loadHidden?.call() ?? Future.value(false));
      await _recompute();
      status = MoneyStatus.ready;
    } catch (_) {
      status = MoneyStatus.error;
    }
    _notify();
  }

  /// Vuelve a calcular tras cambiar horas o restaurar una copia (RF-12), sin
  /// pasar por «cargando».
  Future<void> refresh() async {
    try {
      await _recompute();
      status = MoneyStatus.ready;
    } catch (_) {
      // Se conserva lo último que se vio; el siguiente cambio lo reintenta.
    }
    _notify();
  }

  Future<void> _recompute() async {
    final entries = await _days.allEntries();
    final r = await _money.rates();
    final months = await _money.months();
    final saved = await _saved?.all() ?? const <SavedMove>[];
    final imported = await _money.importedMonths();
    rates = r;
    importedMonths = {for (final i in imported) i.month};
    _entries = entries;
    _records = months;
    savedMoves = sortSavedMoves(saved);
    savedSummary = SavedSummary.of(saved, r, _clock());
    overview = MoneyOverview.compute(
      entries: entries,
      rates: r,
      records: months,
      savedMoves: saved,
      imported: imported,
    );
  }

  /// Los meses que vienen del Excel: en ellos no se apuntan días (016,
  /// RF-4).
  Set<YearMonth> importedMonths = const {};

  /// El día [date] está en un mes del Excel.
  bool isImportedMonth(DateTime date) =>
      importedMonths.contains(YearMonth.of(date));

  /// Todos los movimientos, para comprobar Apuntar (RF-8).
  Future<List<SavedMove>> readSavedMoves() async =>
      await _saved?.all() ?? const [];

  // --- Horas guardadas (008) ------------------------------------------

  /// Guarda [move] (en lugar de [old], si se edita). Devuelve el aviso si no
  /// se puede (RF-4, RF-7, RF-10) o si falla, o nulo si se ha guardado. Un
  /// cobro se guarda con su importe congelado (RF-9).
  Future<String?> saveSavedMove(SavedMove move, {SavedMove? old}) async {
    final repo = _saved;
    if (repo == null) return _saveFailedText;
    var m = move;
    if (m.kind == SavedMoveKind.paid) {
      final cents = savedPaidCents(m.minutes, m.date, rates);
      if (cents == null) return 'Falta la tarifa normal en esa fecha.';
      m = SavedMove(
        id: m.id,
        box: m.box,
        kind: m.kind,
        date: m.date,
        minutes: m.minutes,
        note: m.note,
        cents: cents,
      );
    }
    final problem = _check(m, old);
    if (problem != null) return problem;
    await _write(() => repo.save(m));
    return saveFailed ? _saveFailedText : null;
  }

  /// Borra [move]. Devuelve el aviso si no se puede o falla; nulo si se ha
  /// borrado (y se puede deshacer con [restoreSavedMove]).
  Future<String?> deleteSavedMove(SavedMove move) async {
    final repo = _saved;
    final id = move.id;
    if (repo == null || id == null) return _saveFailedText;
    final problem = _check(null, move);
    if (problem != null) return problem;
    await _write(() => repo.delete(id));
    return saveFailed ? _saveFailedText : null;
  }

  /// Vuelve a crear un movimiento borrado, con su mismo id.
  Future<void> restoreSavedMove(SavedMove move) async {
    final repo = _saved;
    if (repo == null) return;
    await _write(() => repo.save(move));
  }

  String? _check(SavedMove? move, SavedMove? old) => checkSavedMove(
    move: move,
    old: old,
    all: savedMoves,
    entries: _entries,
    rates: rates,
    records: _records,
  );

  static const _saveFailedText =
      'No se ha podido guardar el último cambio. Vuelve a intentarlo.';

  Future<void> toggleHideAmounts() async {
    hideAmounts = !hideAmounts;
    _notify();
    try {
      await _saveHidden?.call(hideAmounts);
    } catch (_) {
      // La preferencia vale hasta cerrar la app.
    }
  }

  // --- Meses -----------------------------------------------------------

  /// Cambia el estado de un mes (RF-6). [date] es el día de la entrega o del
  /// cobro; si es nulo, hoy. Pasar a Entregado o Abierto quita el cobro; pasar
  /// a Abierto quita también la entrega.
  Future<void> setStatus(
    YearMonth month,
    MonthStatus status, {
    DateTime? date,
  }) async {
    final current = _recordOf(month);
    final day = date ?? _clock();
    final record = switch (status) {
      MonthStatus.open => MonthRecord(month),
      MonthStatus.delivered => MonthRecord(
        month,
        deliveredOn: current?.deliveredOn ?? day,
      ),
      MonthStatus.paid => MonthRecord(
        month,
        deliveredOn: current?.deliveredOn,
        paidOn: day,
      ),
    };
    await _write(() => _money.saveMonth(record));
  }

  /// Marca varios meses como cobrados de una vez (RF-9).
  Future<void> markPaid(Iterable<YearMonth> months, DateTime date) async {
    await _write(() async {
      for (final m in months) {
        final current = _recordOf(m);
        await _money.saveMonth(
          MonthRecord(m, deliveredOn: current?.deliveredOn, paidOn: date),
        );
      }
    });
  }

  MonthRecord? _recordOf(YearMonth m) {
    for (final l in overview.months) {
      if (l.month == m) return l.record;
    }
    return null;
  }

  // --- Tarifas ---------------------------------------------------------

  Future<void> saveRate(DayKind kind, int cents, DateTime start) =>
      _write(() => _money.saveRate(Rate(kind, start, cents)));

  Future<void> deleteRate(Rate rate) =>
      _write(() => _money.deleteRate(rate.kind, rate.start));

  /// Cambia el importe o el inicio de una tarifa (021, RF-3).
  Future<void> replaceRate(Rate old, Rate updated) =>
      _write(() => _money.replaceRate(old, updated));

  Future<void> _write(Future<void> Function() action) async {
    try {
      await action();
      saveFailed = false;
      // Si avisar a las copias falla, lo guardado sigue bien guardado.
      await _onChanged?.call().catchError((Object _) {});
    } catch (_) {
      saveFailed = true;
    }
    await refresh();
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
