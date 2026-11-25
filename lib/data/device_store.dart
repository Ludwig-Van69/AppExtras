import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/device_identity.dart';
import 'folder_storage.dart';

/// Archivo con el código y el nombre de este móvil (025). Va aparte de la base
/// de datos y la copia de Android no lo guarda (reglas en
/// `android/app/src/main/res/xml/`), para que otro móvil nunca reciba el
/// mismo código (RF-4).
const deviceFileName = 'movil.json';

/// El modelo del móvil según Android (`Build.MODEL`), o nulo si no se sabe.
Future<String?> channelDeviceModel() async {
  try {
    return await const MethodChannel(ChannelFolderStorage.channelName)
        .invokeMethod<String>('deviceModel');
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// Lee y guarda [DeviceIdentity] en un archivo JSON.
class DeviceStore {
  DeviceStore(File file) : _locate = (() async => file);

  DeviceStore.inAppFolder()
    : _locate = (() async =>
          File(p.join(await getDatabasesPath(), deviceFileName)));

  final Future<File> Function() _locate;

  /// Lo guardado; si falta o está dañado, crea un móvil nuevo con el nombre
  /// del modelo y lo guarda (RF-1). Lo peor que pasa es un código nuevo.
  Future<DeviceIdentity> loadOrCreate(
    Future<String?> Function() model, {
    Random? random,
  }) async {
    final saved = await _load();
    if (saved != null) return saved;
    String? m;
    try {
      m = await model();
    } catch (_) {
      m = null;
    }
    final created = DeviceIdentity(
      id: newDeviceId(random),
      name: defaultDeviceName(m),
    );
    try {
      await save(created);
    } on FileSystemException {
      // Sin poder guardarlo, vale para esta sesión.
    }
    return created;
  }

  Future<DeviceIdentity?> _load() async {
    try {
      final json = jsonDecode(await (await _locate()).readAsString());
      if (json is! Map<String, Object?>) return null;
      final id = json['id'];
      final name = json['name'];
      if (id is! String || !isValidDeviceId(id)) return null;
      final seen = <String, String>{};
      final rawSeen = json['seen'];
      if (rawSeen is Map) {
        for (final e in rawSeen.entries) {
          if (e.key is String && e.value is String) {
            seen[e.key as String] = e.value as String;
          }
        }
      }
      return DeviceIdentity(
        id: id,
        name:
            (name is String ? cleanDeviceName(name) : null) ??
            fallbackDeviceName,
        seen: seen,
      );
    } on FileSystemException {
      return null; // No existe o no se puede leer.
    } on FormatException {
      return null; // JSON dañado.
    }
  }

  /// Guarda en un temporal y lo renombra, para no dejar el archivo a medias.
  Future<void> save(DeviceIdentity d) async {
    final file = await _locate();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({'version': 1, 'id': d.id, 'name': d.name, 'seen': d.seen}),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}
