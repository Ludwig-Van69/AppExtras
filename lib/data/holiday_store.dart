import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/day_entry.dart';
import '../domain/holidays.dart';

const holidaysFileName = 'festivos.json';

/// Lo que el usuario ha cambiado: festivos de serie desactivados y festivos
/// propios.
class HolidayData {
  const HolidayData({this.disabled = const {}, this.custom = const []});
  final Set<String> disabled;
  final List<Holiday> custom;

  HolidayCalendar get calendar =>
      HolidayCalendar(disabled: disabled, custom: custom);
}

/// Guarda y lee los festivos en `festivos.json`, en la carpeta privada de la
/// app. Si el archivo falta o está dañado, se usan los de serie.
class HolidayStore {
  HolidayStore(File file) : _locate = (() async => file);

  HolidayStore.inAppFolder()
    : _locate = (() async =>
          File(p.join(await getDatabasesPath(), holidaysFileName)));

  final Future<File> Function() _locate;

  Future<HolidayData> load() async {
    try {
      final json = jsonDecode(await (await _locate()).readAsString());
      if (json is! Map<String, Object?>) return const HolidayData();
      final off = json['disabled'];
      final cust = json['custom'];
      return HolidayData(
        disabled: {if (off is List) ...off.whereType<String>()},
        custom: [
          if (cust is List)
            for (final c in cust)
              if (c is Map<String, Object?>) ?_parse(c),
        ],
      );
    } on FileSystemException {
      return const HolidayData();
    } on FormatException {
      return const HolidayData();
    }
  }

  Future<void> save(HolidayData data) async {
    final file = await _locate();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'version': 1,
        'disabled': data.disabled.toList()..sort(),
        'custom': [for (final h in data.custom) _toJson(h)],
      }),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  static Map<String, Object?> _toJson(Holiday h) => {
    'id': h.id,
    'name': h.name,
    if (h.date != null) 'date': dateKey(h.date!),
    if (h.month != null) 'month': h.month,
    if (h.day != null) 'day': h.day,
  };

  /// Un festivo propio; nulo si los datos no valen (se ignora solo ese).
  static Holiday? _parse(Map<String, Object?> j) {
    final id = j['id'];
    final name = j['name'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) {
      return null;
    }
    try {
      final date = j['date'];
      if (date is String) return Holiday.once(id, name, parseDateKey(date));
      final month = j['month'];
      final day = j['day'];
      if (month is int && day is int) {
        // El 29 de febrero no existe todos los años: se valida con uno bisiesto.
        final probe = DateTime(2024, month, day);
        if (month < 1 || month > 12 || probe.month != month) return null;
        return Holiday.fixed(id, name, HolidayGroup.custom, month, day);
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}
