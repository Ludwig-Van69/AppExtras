// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';

import '../../data/vacation_repository.dart';
import '../../domain/holidays.dart';
import '../../domain/vacations.dart';

enum VacationStatus { loading, ready, error }

/// Qué pasó al tocar un día (RF-5 a RF-7).
enum VacationTap { marked, unmarked, notWorkday, outOfRange, failed }

/// Estado de las vacaciones (010). Cada cambio se guarda y después se vuelve
/// a leer todo, así lo que se ve es lo que hay.
class VacationController extends ChangeNotifier {
  VacationController({
    required VacationRepository repository,
    DateTime Function()? clock,
    HolidayCalendar Function()? calendar,
    Future<void> Function()? onChanged,
  }) : _repo = repository,
       _clock = clock ?? DateTime.now,
       _calendar = calendar,
       _onChanged = onChanged;

  final VacationRepository _repo;
  final DateTime Function() _clock;
  final HolidayCalendar Function()? _calendar;

  /// Avisa a las copias de que hay cambios sin copiar (003, RF-4).
  final Future<void> Function()? _onChanged;

  VacationStatus status = VacationStatus.loading;

  /// Nulo mientras no se configure (RF-4).
  VacationSettings? settings;

  /// Días marcados, por fecha.
  Map<DateTime, VacationDay> days = const {};

  /// Un guardado ha fallado; se avisa en pantalla.
  bool saveFailed = false;

  bool _disposed = false;

  DateTime get today {
    final n = _clock();
    return DateTime(n.year, n.month, n.day);
  }

  bool get isConfigured => settings != null;

  /// Saldo y vistas; nulo sin configurar (RF-4).
  VacationOverview? get overview {
    final s = settings;
    return s == null ? null : VacationOverview.of(s, days.values, today);
  }

  VacationDay? dayOn(DateTime date) =>
      days[DateTime(date.year, date.month, date.day)];

  HolidayCalendar? get calendar => _calendar?.call();

  /// Los festivos han cambiado: la pantalla vuelve a mirar qué días son
  /// laborables y sus avisos (013, RF-14).
  void calendarChanged() => notifyListeners();

  Future<void> load() async {
    if (status != VacationStatus.ready) {
      status = VacationStatus.loading;
      _notify();
    }
    try {
      await _reload();
      status = VacationStatus.ready;
    } catch (_) {
      status = VacationStatus.error;
    }
    _notify();
  }

  Future<void> _reload() async {
    settings = await _repo.settings();
    days = {for (final d in await _repo.days()) d.date: d};
  }

  /// Guarda los ajustes (RF-1, RF-2).
  Future<void> saveSettings(VacationSettings s) =>
      _write(() => _repo.saveSettings(s));

  /// Marca o desmarca [date] (RF-5 a RF-8). Al desmarcar, [lastRemoved]
  /// guarda el día para poder deshacerlo.
  Future<VacationTap> toggle(DateTime date) async {
    final s = settings;
    final d = DateTime(date.year, date.month, date.day);
    if (s == null) return VacationTap.outOfRange;
    final existing = days[d];
    if (existing != null) {
      await _write(() => _repo.deleteDay(d));
      if (saveFailed) return VacationTap.failed;
      lastRemoved = existing;
      return VacationTap.unmarked;
    }
    final (first, last) = vacationRange(s, today);
    if (d.isBefore(first) || d.isAfter(last)) return VacationTap.outOfRange;
    if (!canTakeVacation(d, calendar: calendar)) return VacationTap.notWorkday;
    final year = proposeVacationYear(d, s, days.values, today);
    await _write(() => _repo.saveDay(VacationDay(d, year)));
    return saveFailed ? VacationTap.failed : VacationTap.marked;
  }

  /// El último día desmarcado, para «Deshacer».
  VacationDay? lastRemoved;

  /// Vuelve a marcar un día desmarcado, con su mismo año.
  Future<void> restore(VacationDay day) async {
    await _write(() => _repo.saveDay(day));
    if (lastRemoved == day) lastRemoved = null;
  }

  /// Cambia el año de un día marcado entre el de su fecha y el anterior
  /// (RF-9). Devuelve el año nuevo, o nulo si no se puede.
  Future<int?> switchYear(DateTime date) async {
    final s = settings;
    final day = dayOn(date);
    if (s == null || day == null) return null;
    final next = day.countsForPreviousYear ? day.date.year : day.date.year - 1;
    if (next < s.firstYear) return null;
    await _write(() => _repo.saveDay(day.copyWith(year: next)));
    return saveFailed ? null : next;
  }

  /// Convierte un día marcado en medio día o en día entero (012, RF-9).
  /// Devuelve falso si no está marcado o no se pudo guardar.
  Future<bool> setHalf(DateTime date, bool half) async {
    final day = dayOn(date);
    if (day == null) return false;
    await _write(() => _repo.saveDay(day.copyWith(half: half)));
    return !saveFailed;
  }

  Future<void> _write(Future<void> Function() action) async {
    try {
      await action();
      saveFailed = false;
      // Si avisar a las copias falla, lo guardado sigue bien guardado.
      await _onChanged?.call().catchError((Object _) {});
    } catch (_) {
      saveFailed = true; // sin datos personales en ningún registro
    }
    try {
      await _reload();
    } catch (_) {
      // Se conserva lo último que se vio.
    }
    _notify();
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
