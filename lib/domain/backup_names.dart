/// Nombres de los archivos de copia y qué copias sobran (RF-5, RF-6; con el
/// móvil que la hizo desde la 025).
library;

import 'device_identity.dart';

/// Cuántas copias automáticas se guardan (RF-6).
const backupsToKeep = 10;

enum BackupKind {
  /// Las que se hacen solas o con «Hacer copia ahora»; se borran las viejas.
  automatic('horas-copia-'),

  /// La que se guarda justo antes de restaurar; nunca se borra sola (RF-14).
  beforeRestore('horas-antes-de-restaurar-');

  const BackupKind(this.prefix);
  final String prefix;
}

/// Una copia reconocida por su nombre.
class BackupInfo {
  const BackupInfo(
    this.name,
    this.kind,
    this.takenAt,
    this.copyNumber, {
    this.deviceId,
    this.deviceName,
  });

  final String name;
  final BackupKind kind;
  final DateTime takenAt;

  /// 1 para la primera de ese segundo; 2, 3… si se repite (`-2`, `-3`).
  final int copyNumber;

  /// Código y nombre del móvil que la hizo (025, RF-5); nulos en las copias
  /// antiguas (RF-7).
  final String? deviceId;
  final String? deviceName;

  /// Ordena las copias de un mismo móvil al compararlas como texto: fecha y
  /// número de copia (025, RF-9).
  String get orderKey =>
      '${_stamp(takenAt)}-${copyNumber.toString().padLeft(4, '0')}';
}

/// Nombre para una copia hecha en [takenAt] (hora local) por [device]
/// (`…_código_nombre.db`, 025 RF-5). Si ya existe alguno de [existing],
/// añade `-2`, `-3`… tras la hora para no pisarlo.
String backupFileName(
  DateTime takenAt, {
  BackupKind kind = BackupKind.automatic,
  Set<String> existing = const {},
  DeviceIdentity? device,
}) {
  final base = '${kind.prefix}${_stamp(takenAt)}';
  final tail = device == null ? '.db' : '_${device.id}_${device.name}.db';
  var name = '$base$tail';
  for (var n = 2; existing.contains(name); n++) {
    name = '$base-$n$tail';
  }
  return name;
}

final _pattern = RegExp(
  r'^(horas-copia-|horas-antes-de-restaurar-)'
  r'(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})(?:-([2-9]|[1-9]\d+))?'
  r'(?:_([a-z0-9]{6})_([\p{L}\p{N} -]{1,24}))?\.db$',
  unicode: true,
);

/// La copia que corresponde a [name], o nulo si no es una copia de la app.
BackupInfo? parseBackupName(String name) {
  final m = _pattern.firstMatch(name);
  if (m == null) return null;
  final kind = BackupKind.values.firstWhere((k) => k.prefix == m[1]);
  final p = [for (var i = 2; i <= 7; i++) int.parse(m[i]!)];
  final t = DateTime(p[0], p[1], p[2], p[3], p[4], p[5]);
  // Rechaza fechas imposibles (30 de febrero, 25 horas…).
  if (_stamp(t) !=
      name.substring(kind.prefix.length, kind.prefix.length + 19)) {
    return null;
  }
  final deviceName = m[10];
  if (deviceName != null && cleanDeviceName(deviceName) != deviceName) {
    return null;
  }
  return BackupInfo(
    name,
    kind,
    t,
    m[8] == null ? 1 : int.parse(m[8]!),
    deviceId: m[9],
    deviceName: deviceName,
  );
}

/// Las copias de [names], de la más reciente a la más antigua; ignora el
/// resto de archivos.
List<BackupInfo> sortedBackups(Iterable<String> names) =>
    names.map(parseBackupName).whereType<BackupInfo>().toList()..sort((a, b) {
      final byTime = b.takenAt.compareTo(a.takenAt);
      return byTime != 0 ? byTime : b.copyNumber.compareTo(a.copyNumber);
    });

/// Las copias automáticas de este móvil ([deviceId]) que sobran, de la más
/// antigua a la más reciente. Nunca incluye copias de otros móviles, copias
/// antiguas sin móvil, copias previas a restaurar ni archivos ajenos (RF-6;
/// 025, RF-6).
List<String> backupsToPrune(
  Iterable<String> names, {
  required String deviceId,
  int keep = backupsToKeep,
}) =>
    sortedBackups(names)
        .where((b) => b.kind == BackupKind.automatic && b.deviceId == deviceId)
        .skip(keep)
        .map((b) => b.name)
        .toList()
        .reversed
        .toList();

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      '_${two(t.hour)}-${two(t.minute)}-${two(t.second)}';
}
