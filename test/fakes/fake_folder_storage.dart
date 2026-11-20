import 'dart:typed_data';

import 'package:horas_y_vacaciones/data/folder_storage.dart';

/// Carpeta falsa en memoria, con fallos que se pueden provocar a voluntad.
class FakeFolderStorage implements FolderStorage {
  /// Lo que devolverá [pickFolder] (nulo = el usuario cancela).
  String? folderToPick = 'content://carpeta/inventada';

  /// Lo que devolverá [pickFile] (nulo = el usuario cancela).
  String? fileToPick;

  /// Archivos de cada carpeta: carpeta → nombre → contenido.
  final Map<String, Map<String, Uint8List>> folders = {};

  /// Carpetas que ya no se pueden usar.
  final Set<String> broken = {};

  /// Si no es nulo, las escrituras fallan con este problema.
  StorageProblem? failWrites;

  /// Si no es nulo, los borrados fallan con este problema.
  StorageProblem? failDeletes;

  /// Lo que se ha compartido: nombre, tipo y contenido.
  final List<({String name, String mime, Uint8List bytes})> shared = [];

  Map<String, Uint8List> files(String folder) =>
      folders.putIfAbsent(folder, () => {});

  void _check(String folder) {
    if (broken.contains(folder)) {
      throw const StorageException(StorageProblem.noAccess);
    }
  }

  @override
  Future<String?> pickFolder() async => folderToPick;

  @override
  Future<String?> pickFile() async => fileToPick;

  @override
  Future<bool> isAccessible(String folder) async => !broken.contains(folder);

  @override
  Future<void> writeFile(String folder, String name, Uint8List bytes) async {
    _check(folder);
    if (failWrites != null) throw StorageException(failWrites!);
    if (files(folder).containsKey(name)) {
      throw const StorageException(StorageProblem.exists);
    }
    files(folder)[name] = Uint8List.fromList(bytes);
  }

  @override
  Future<List<String>> listFiles(String folder) async {
    _check(folder);
    return files(folder).keys.toList();
  }

  @override
  Future<Uint8List> readFile(String folder, String name) async {
    _check(folder);
    final bytes = files(folder)[name];
    if (bytes == null) throw const StorageException(StorageProblem.notFound);
    return bytes;
  }

  @override
  Future<void> deleteFile(String folder, String name) async {
    _check(folder);
    if (failDeletes != null) throw StorageException(failDeletes!);
    if (files(folder).remove(name) == null) {
      throw const StorageException(StorageProblem.notFound);
    }
  }

  @override
  Future<void> shareFile(String name, String mimeType, Uint8List bytes) async {
    shared.add((name: name, mime: mimeType, bytes: bytes));
  }
}
