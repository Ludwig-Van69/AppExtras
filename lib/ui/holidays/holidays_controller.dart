// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';

import '../../data/holiday_store.dart';
import '../../domain/holidays.dart';

/// Longitud máxima del nombre de un festivo propio.
const maxHolidayNameLength = 40;

/// Estado de los festivos: los de serie con su interruptor y los propios.
/// Cada cambio se ve al momento y se guarda detrás; si no se puede guardar,
/// sigue valiendo hasta cerrar la app y [saveFailed] lo indica.
class HolidaysController extends ChangeNotifier {
  HolidaysController({
    required Future<HolidayData> Function() load,
    required Future<void> Function(HolidayData) save,
  }) : _load = load,
       _save = save;

  /// Con la persistencia real, en la carpeta de la app.
  factory HolidaysController.withStore(HolidayStore store) =>
      HolidaysController(load: store.load, save: store.save);

  final Future<HolidayData> Function() _load;
  final Future<void> Function(HolidayData) _save;

  HolidayData _data = const HolidayData();
  HolidayCalendar _calendar = HolidayCalendar();
  HolidayCalendar get calendar => _calendar;

  /// El último guardado falló.
  bool saveFailed = false;

  Future<void> load() async {
    try {
      _data = await _load();
    } catch (_) {
      _data = const HolidayData();
    }
    _calendar = _data.calendar;
    notifyListeners();
  }

  /// Activa o desactiva un festivo de serie.
  Future<void> setEnabled(Holiday h, bool enabled) => _change(
    HolidayData(
      disabled: {
        for (final id in _data.disabled)
          if (id != h.id) id,
        if (!enabled) h.id,
      },
      custom: _data.custom,
    ),
  );

  /// Añade un festivo propio. [name] se limpia y se corta; si queda vacío no
  /// se añade y devuelve falso.
  Future<bool> addCustom(
    String name,
    DateTime date, {
    required bool yearly,
  }) async {
    var n = name.trim();
    if (n.length > maxHolidayNameLength) {
      n = n.substring(0, maxHolidayNameLength).trimRight();
    }
    if (n.isEmpty) return false;
    final id = 'c${DateTime.now().microsecondsSinceEpoch}';
    final h = yearly
        ? Holiday.fixed(id, n, HolidayGroup.custom, date.month, date.day)
        : Holiday.once(id, n, date);
    await _change(
      HolidayData(disabled: _data.disabled, custom: [..._data.custom, h]),
    );
    return true;
  }

  Future<void> removeCustom(Holiday h) => _change(
    HolidayData(
      disabled: _data.disabled,
      custom: [
        for (final c in _data.custom)
          if (c.id != h.id) c,
      ],
    ),
  );

  Future<void> _change(HolidayData next) async {
    _data = next;
    _calendar = next.calendar;
    notifyListeners();
    try {
      await _save(next);
      saveFailed = false;
    } catch (_) {
      saveFailed = true;
    }
    notifyListeners();
  }
}
