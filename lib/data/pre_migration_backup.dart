import 'dart:io';

import '../domain/backup_names.dart';
import 'app_settings.dart';
import 'folder_storage.dart';

/// La copia que se hace justo antes de cambiar el formato de los datos
/// (RF-9, 005 RF-14). Se llama desde `openAppDatabase` con el archivo aún sin
/// tocar.
///
/// - Siempre: una copia al lado del archivo (`…antes-de-actualizar-FECHA.bak`).
///   Si falla, lanza y no se migra.
/// - Si hay carpeta de copias accesible: otra copia allí, con el nombre de
///   «antes de restaurar» (no se borra sola y aparece en la lista de
///   restaurar). Esta es opcional: si falla, no impide migrar.
Future<void> backupBeforeUpgrade(
  String dbPath, {
  FolderStorage? storage,
  SettingsStore? settings,
  DateTime Function()? clock,
}) async {
  final now = (clock ?? DateTime.now)();
  final stamp = now.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
  final local = await File(dbPath)
      .copy('$dbPath.antes-de-actualizar-$stamp.bak');
  if (await local.length() != await File(dbPath).length()) {
    await local.delete();
    throw const FileSystemException('La copia no tiene el mismo tamaño');
  }
  if (storage == null || settings == null) return;
  try {
    final folder = (await settings.load()).folder;
    if (folder == null || !await storage.isAccessible(folder)) return;
    final names = (await storage.listFiles(folder)).toSet();
    await storage.writeFile(
      folder,
      backupFileName(now, kind: BackupKind.beforeRestore, existing: names),
      await File(dbPath).readAsBytes(),
    );
  } catch (_) {
    // La copia local ya está hecha; esta es un extra.
  }
}
