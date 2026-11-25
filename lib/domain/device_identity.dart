/// Quién es este móvil para las copias (025, RF-1 a RF-3).
library;

import 'dart:math';

/// Largo del código fijo de cada móvil.
const deviceIdLength = 6;

/// Largo máximo del nombre del móvil (RF-3).
const deviceNameMaxLength = 24;

/// Nombre de serie si no se conoce el modelo.
const fallbackDeviceName = 'Móvil';

/// Mensaje cuando el nombre no vale (RF-3).
const invalidDeviceNameMessage =
    'Usa de 1 a 24 letras, números, espacios o guiones';

const _idChars = 'abcdefghijklmnopqrstuvwxyz0123456789';
final _idPattern = RegExp('^[a-z0-9]{$deviceIdLength}\$');
final _namePattern = RegExp(r'^[\p{L}\p{N} -]+$', unicode: true);
final _notNameChar = RegExp(r'[^\p{L}\p{N} -]', unicode: true);

/// El móvil: su código fijo, su nombre y la última copia cargada o descartada
/// de cada otro móvil (código → clave de orden, ver `BackupInfo.orderKey`).
class DeviceIdentity {
  const DeviceIdentity({
    required this.id,
    required this.name,
    this.seen = const {},
  });

  final String id;
  final String name;
  final Map<String, String> seen;

  DeviceIdentity copyWith({String? name, Map<String, String>? seen}) =>
      DeviceIdentity(id: id, name: name ?? this.name, seen: seen ?? this.seen);

  @override
  bool operator ==(Object other) =>
      other is DeviceIdentity &&
      other.id == id &&
      other.name == name &&
      other.seen.length == seen.length &&
      seen.entries.every((e) => other.seen[e.key] == e.value);

  @override
  int get hashCode => Object.hash(id, name, seen.length);
}

/// Un código nuevo de 6 letras minúsculas o cifras (RF-1).
String newDeviceId([Random? random]) {
  final r = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < deviceIdLength; i++)
      _idChars.codeUnitAt(r.nextInt(_idChars.length)),
  ]);
}

bool isValidDeviceId(String id) => _idPattern.hasMatch(id);

/// El nombre ya limpio, o nulo si no vale (RF-3): de 1 a 24 letras,
/// números, espacios o guiones. Quita los espacios de los extremos y junta
/// los repetidos.
String? cleanDeviceName(String raw) {
  final name = raw.trim().replaceAll(RegExp(r' {2,}'), ' ');
  if (name.isEmpty || name.length > deviceNameMaxLength) return null;
  return _namePattern.hasMatch(name) ? name : null;
}

/// Nombre de serie a partir del modelo (RF-1): quita lo que no vale y lo
/// recorta. Si no queda nada, «Móvil».
String defaultDeviceName(String? model) {
  if (model == null) return fallbackDeviceName;
  var name = model.replaceAll(_notNameChar, ' ').trim();
  name = name.replaceAll(RegExp(r' {2,}'), ' ');
  if (name.length > deviceNameMaxLength) {
    name = name.substring(0, deviceNameMaxLength).trim();
  }
  return cleanDeviceName(name) ?? fallbackDeviceName;
}
