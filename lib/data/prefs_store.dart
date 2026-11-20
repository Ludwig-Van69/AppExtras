import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const prefsFileName = 'preferencias.json';

/// Preferencias de uso del móvil (ocultar importes, tema y calendarios
/// temáticos), en un archivo
/// JSON. Si falta o está dañado, valen los valores de serie. Guardar una
/// preferencia conserva las demás.
class PrefsStore {
  PrefsStore(File file) : _locate = (() async => file);

  PrefsStore.inAppFolder()
    : _locate = (() async =>
          File(p.join(await getDatabasesPath(), prefsFileName)));

  final Future<File> Function() _locate;

  Future<bool> loadHideAmounts() async {
    final v = (await _readAll())['hideAmounts'];
    return v is bool ? v : false;
  }

  Future<void> saveHideAmounts(bool value) => _save('hideAmounts', value);

  /// El tema elegido: `system`, `light` o `dark` (009, RF-10). Nulo si no
  /// hay o no se entiende: entonces vale Automático.
  Future<String?> loadTheme() async {
    final v = (await _readAll())['theme'];
    return v is String ? v : null;
  }

  Future<void> saveTheme(String value) => _save('theme', value);

  /// Calendarios temáticos (013, RF-11): activados si no hay dato.
  Future<bool> loadCalendarDecor() async {
    final v = (await _readAll())['calendarDecor'];
    return v is bool ? v : true;
  }

  Future<void> saveCalendarDecor(bool value) => _save('calendarDecor', value);

  Future<Map<String, Object?>> _readAll() async {
    try {
      final json = jsonDecode(await (await _locate()).readAsString());
      if (json is Map<String, Object?>) return json;
    } on FileSystemException {
      // No existe o no se puede leer.
    } on FormatException {
      // JSON dañado.
    }
    return {};
  }

  Future<void> _save(String key, Object value) async {
    final all = {...await _readAll(), 'version': 1, key: value};
    final file = await _locate();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(all), flush: true);
    await tmp.rename(file.path);
  }
}
