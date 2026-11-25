import 'package:flutter/foundation.dart';
import 'package:horas_y_vacaciones/data/app_settings.dart';
import 'package:horas_y_vacaciones/domain/backup_names.dart';
import 'package:horas_y_vacaciones/domain/device_identity.dart';
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

  BackupOutcome shareResult = const BackupOutcome.ok('horas-copia.db');

  /// Fecha que se anota al compartir bien.
  DateTime sharedAt = DateTime(2026, 11, 6, 18);

  @override
  Future<BackupOutcome> shareBackup() async {
    calls.add('shareBackup');
    if (shareResult.ok) {
      settings = _settings.copyWith(lastShared: () => sharedAt);
    }
    return shareResult;
  }

  @override
  DeviceIdentity? device = const DeviceIdentity(id: 'abc123', name: 'moto g75');

  OtherDeviceOffer? _offer;
  @override
  OtherDeviceOffer? get offer => _offer;
  set offer(OtherDeviceOffer? o) {
    _offer = o;
    notifyListeners();
  }

  @override
  Future<void> checkOtherDevices() async => calls.add('checkOtherDevices');

  BackupOutcome loadResult = const BackupOutcome.ok('Copia restaurada.');

  @override
  Future<BackupOutcome> loadOffer() async {
    calls.add('loadOffer');
    if (loadResult.ok) {
      restoredCount++;
      offer = null;
    }
    return loadResult;
  }

  @override
  Future<void> dismissOffer() async {
    calls.add('dismissOffer');
    offer = null;
  }

  @override
  Future<String?> renameDevice(String name) async {
    calls.add('renameDevice:$name');
    final clean = cleanDeviceName(name);
    if (clean == null) return invalidDeviceNameMessage;
    device = device!.copyWith(name: clean);
    notifyListeners();
    return null;
  }
}

/// Una copia de la lista, con datos inventados.
BackupListing listing(
  DateTime takenAt,
  int? days, {
  BackupKind kind = BackupKind.automatic,
  DeviceIdentity? device,
}) {
  final name = backupFileName(takenAt, kind: kind, device: device);
  return BackupListing(
    BackupInfo(
      name,
      kind,
      takenAt,
      1,
      deviceId: device?.id,
      deviceName: device?.name,
    ),
    days,
  );
}
