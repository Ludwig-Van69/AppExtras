import 'package:flutter/foundation.dart';
import 'package:horas_y_vacaciones/data/app_settings.dart';
import 'package:horas_y_vacaciones/domain/backup_names.dart';
import 'package:horas_y_vacaciones/ui/backup/backup_controller.dart';

/// Copias falsas para los tests de pantalla: devuelven lo que se les diga y
/// apuntan lo que se les ha pedido.
class FakeBackupService extends ChangeNotifier implements BackupService {
  FakeBackupService({BackupSettings settings = const BackupSettings()})
    : _settings = settings; // ignore: prefer_initializing_formals

  BackupSettings _settings;
  @override
  BackupSettings get settings => _settings;
  set settings(BackupSettings s) {
    _settings = s;
    notifyListeners();
  }

  bool _busy = false;
  @override
  bool get busy => _busy;
  set busy(bool v) {
    _busy = v;
    notifyListeners();
  }

  @override
  int restoredCount = 0;

  /// Lo que se ha pedido, en orden.
  final List<String> calls = [];

  BackupOutcome backupResult = const BackupOutcome.ok('x');
  BackupOutcome restoreResult = const BackupOutcome.ok('Copia restaurada.');
  BackupOutcome exportResult = const BackupOutcome.ok('horas.csv');
  List<BackupListing> listing = [];
  String? fileToPick;
  String? folderToPick =
      'content://com.android.externalstorage.documents/tree/'
      'primary%3ADocuments%2FHoras';

  /// Se completa cuando se quiera que una restauración termine.
  Future<void>? restoreGate;

  /// Lo que pasa justo al restaurar bien (p. ej. cambiar los datos).
  VoidCallback? onRestored;

  @override
  Future<void> load() async {}

  @override
  Future<void> markChanged() async => calls.add('markChanged');

  @override
  Future<BackupOutcome?> onLeavingApp() async {
    calls.add('onLeavingApp');
    return null;
  }

  @override
  Future<bool> chooseFolder() async {
    calls.add('chooseFolder');
    final folder = folderToPick;
    if (folder == null) return false;
    settings = _settings.copyWith(folder: () => folder, lastError: () => null);
    return true;
  }

  @override
  Future<BackupOutcome> backupNow() async {
    calls.add('backupNow');
    return backupResult;
  }

  @override
  Future<List<BackupListing>> listBackups() async => listing;

  @override
  Future<BackupOutcome> restoreFromFolder(String name) async {
    calls.add('restoreFromFolder:$name');
    await restoreGate;
    if (restoreResult.ok) {
      restoredCount++;
      onRestored?.call();
      notifyListeners();
    }
    return restoreResult;
  }

  @override
  Future<String?> pickFile() async => fileToPick;

  @override
  Future<BackupOutcome> restoreFromFile(String path) async {
    calls.add('restoreFromFile:$path');
    if (restoreResult.ok) restoredCount++;
    return restoreResult;
  }

  @override
  Future<BackupOutcome> exportCsv() async {
    calls.add('exportCsv');
    return exportResult;
  }
}

/// Una copia de la lista, con datos inventados.
BackupListing listing(
  DateTime takenAt,
  int? days, {
  BackupKind kind = BackupKind.automatic,
}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final name =
      '${kind.prefix}${takenAt.year}-${two(takenAt.month)}-${two(takenAt.day)}'
      '_${two(takenAt.hour)}-${two(takenAt.minute)}-${two(takenAt.second)}.db';
  return BackupListing(BackupInfo(name, kind, takenAt, 1), days);
}
