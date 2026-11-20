import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Nombre del archivo de ajustes, junto a la base de datos pero aparte de
/// ella: restaurar una copia no debe traerse una carpeta antigua (RF-1).
const settingsFileName = 'ajustes.json';

/// Ajustes de las copias (RF-1, RF-10). Inmutable: se cambia con [copyWith].
class BackupSettings {
  const BackupSettings({
    this.folder,
    this.lastSuccess,
    this.lastError,
    this.dirty = true,
  });

  /// Dirección de la carpeta elegida (la da el selector de Android); nula si
  /// aún no se ha elegido.
  final String? folder;

  /// Cuándo se hizo la última copia correcta.
  final DateTime? lastSuccess;

  /// Motivo, en palabras sencillas, de que la última copia fallara; nulo si
  /// la última salió bien.
  final String? lastError;

  /// Hay cambios en los datos que aún no están en ninguna copia. Por defecto
  /// sí: ante la duda, se copia.
  final bool dirty;

  BackupSettings copyWith({
    String? Function()? folder,
    DateTime? Function()? lastSuccess,
    String? Function()? lastError,
    bool? dirty,
  }) => BackupSettings(
    folder: folder == null ? this.folder : folder(),
    lastSuccess: lastSuccess == null ? this.lastSuccess : lastSuccess(),
    lastError: lastError == null ? this.lastError : lastError(),
    dirty: dirty ?? this.dirty,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'folder': folder,
    'lastSuccess': lastSuccess?.toUtc().toIso8601String(),
    'lastError': lastError,
    'dirty': dirty,
  };

  /// Lee con tolerancia: un dato que falta o no encaja se queda en su valor
  /// por defecto, sin fallar.
  factory BackupSettings.fromJson(Map<String, Object?> json) {
    final folder = json['folder'];
    final success = json['lastSuccess'];
    final error = json['lastError'];
    final dirty = json['dirty'];
    return BackupSettings(
      folder: folder is String && folder.isNotEmpty ? folder : null,
      lastSuccess: success is String
          ? DateTime.tryParse(success)?.toLocal()
          : null,
      lastError: error is String && error.isNotEmpty ? error : null,
      dirty: dirty is bool ? dirty : true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackupSettings &&
      other.folder == folder &&
      other.lastSuccess == lastSuccess &&
      other.lastError == lastError &&
      other.dirty == dirty;

  @override
  int get hashCode => Object.hash(folder, lastSuccess, lastError, dirty);
}

/// Guarda y lee los ajustes en un archivo JSON.
class SettingsStore {
  SettingsStore(File file) : _locate = (() async => file);

  /// Los ajustes en la carpeta privada de la app, junto a la base de datos.
  SettingsStore.inAppFolder()
    : _locate = (() async =>
          File(p.join(await getDatabasesPath(), settingsFileName)));

  final Future<File> Function() _locate;

  /// Los ajustes guardados. Si el archivo no existe o está dañado, devuelve
  /// los de por defecto (sin carpeta): lo peor que pasa es tener que elegirla
  /// de nuevo.
  Future<BackupSettings> load() async {
    try {
      final decoded = jsonDecode(await (await _locate()).readAsString());
      if (decoded is Map<String, Object?>) {
        return BackupSettings.fromJson(decoded);
      }
    } on FileSystemException {
      // No existe o no se puede leer.
    } on FormatException {
      // JSON dañado.
    }
    return const BackupSettings();
  }

  /// Guarda de forma segura: escribe en un archivo temporal y lo renombra,
  /// para que un corte a mitad no deje el archivo roto.
  Future<void> save(BackupSettings settings) async {
    final file = await _locate();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await tmp.rename(file.path);
  }
}
