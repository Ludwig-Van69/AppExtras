import 'package:flutter/services.dart';

/// Por qué falló una operación con la carpeta.
enum StorageProblem {
  /// La carpeta ya no existe, se quitó el permiso o no se puede leer.
  noAccess,

  /// El archivo pedido no está.
  notFound,

  /// Ya hay un archivo con ese nombre.
  exists,

  /// Cualquier otro fallo (sin espacio, error de lectura…).
  other,
}

class StorageException implements Exception {
  const StorageException(this.problem);
  final StorageProblem problem;

  /// Explicación sencilla para el usuario.
  String get message => switch (problem) {
    StorageProblem.noAccess => 'La carpeta de las copias ya no está disponible. Elige la carpeta otra vez.',
    StorageProblem.notFound => 'No se encuentra el archivo en la carpeta.',
    StorageProblem.exists => 'Ya había un archivo con ese nombre.',
    StorageProblem.other =>
      'No se ha podido escribir o leer en la carpeta. '
          'Mira si hay espacio en el móvil.',
  };

  @override
  String toString() => 'StorageException(${problem.name})';
}

/// Lo único que la app necesita del sistema de carpetas de Android. Solo toca
/// la carpeta y los archivos que elige el usuario. En los tests se usa una
/// versión falsa.
abstract interface class FolderStorage {
  /// Abre el selector de carpetas. Devuelve su dirección, o nulo si el usuario
  /// cancela. El permiso queda guardado aunque se reinicie el móvil.
  Future<String?> pickFolder();

  /// Abre el selector de archivos y devuelve la ruta de una copia temporal
  /// del archivo elegido, o nulo si cancela (RF-17).
  Future<String?> pickFile();

  /// ¿Se puede seguir usando la carpeta?
  Future<bool> isAccessible(String folder);

  /// Escribe el archivo de forma segura: con otro nombre mientras se escribe y
  /// con el definitivo solo al terminar. Falla con [StorageProblem.exists] si
  /// ya hay uno con ese nombre.
  Future<void> writeFile(String folder, String name, Uint8List bytes);

  /// Nombres de los archivos de la carpeta (no de sus subcarpetas).
  Future<List<String>> listFiles(String folder);

  Future<Uint8List> readFile(String folder, String name);

  /// Borra un archivo de la carpeta.
  Future<void> deleteFile(String folder, String name);

  /// Abre el menú «Compartir» de Android con este archivo.
  Future<void> shareFile(String name, String mimeType, Uint8List bytes);
}

/// La versión real, que habla con el puente de Kotlin.
class ChannelFolderStorage implements FolderStorage {
  ChannelFolderStorage([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'es.horasyvacaciones/storage';
  final MethodChannel _channel;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw StorageException(switch (e.code) {
        'no_access' => StorageProblem.noAccess,
        'not_found' => StorageProblem.notFound,
        'exists' => StorageProblem.exists,
        _ => StorageProblem.other,
      });
    } on MissingPluginException {
      throw const StorageException(StorageProblem.other);
    }
  }

  @override
  Future<String?> pickFolder() => _call<String>('pickFolder');

  @override
  Future<String?> pickFile() => _call<String>('pickFile');

  @override
  Future<bool> isAccessible(String folder) async =>
      await _call<bool>('isAccessible', {'folder': folder}) ?? false;

  @override
  Future<void> writeFile(String folder, String name, Uint8List bytes) =>
      _call<void>('writeFile', {
        'folder': folder,
        'name': name,
        'bytes': bytes,
      });

  @override
  Future<List<String>> listFiles(String folder) async {
    final names = await _call<List<Object?>>('listFiles', {'folder': folder});
    return [...?names?.cast<String>()];
  }

  @override
  Future<Uint8List> readFile(String folder, String name) async {
    final bytes = await _call<Uint8List>('readFile', {
      'folder': folder,
      'name': name,
    });
    if (bytes == null) throw const StorageException(StorageProblem.other);
    return bytes;
  }

  @override
  Future<void> deleteFile(String folder, String name) =>
      _call<void>('deleteFile', {'folder': folder, 'name': name});

  @override
  Future<void> shareFile(String name, String mimeType, Uint8List bytes) =>
      _call<void>('shareFile', {
        'name': name,
        'mime': mimeType,
        'bytes': bytes,
      });
}
