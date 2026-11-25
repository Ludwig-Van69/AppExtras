import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../data/app_settings.dart';
import '../../data/backup_diff.dart';
import '../../data/backup_file.dart';
import '../../data/device_store.dart';
import '../../data/folder_storage.dart';
import '../../domain/backup_names.dart';
import '../../domain/csv_export.dart';
import '../../domain/device_identity.dart';
import '../../domain/saved_hours.dart';
import '../../domain/vacations.dart';
import '../format.dart';

/// Resultado de una acción, con un texto sencillo para el usuario.
class BackupOutcome {
  const BackupOutcome.ok(this.message) : ok = true;
  const BackupOutcome.fail(this.message) : ok = false;
  final bool ok;
  final String message;
}

/// Una copia más nueva de otro móvil (025, RF-11 a RF-13, RF-17).
class OtherDeviceOffer {
  const OtherDeviceOffer(
    this.info, {
    this.diff,
    this.localChanges = false,
    this.tooNew = false,
  });

  /// La copia: móvil, fecha y nombre del archivo.
  final BackupInfo info;

  /// Lo que cambiaría al cargarla; nulo si [tooNew].
  final BackupDiff? diff;

  /// Este móvil tiene cambios que aún no están en ninguna copia (RF-13).
  final bool localChanges;

  /// La copia es de una versión más nueva de la app (RF-17): solo se avisa.
  final bool tooNew;

  String get deviceName => info.deviceName ?? 'Otro móvil';
}

/// Una copia de la carpeta, lista para enseñarla en la pantalla de restaurar.
class BackupListing {
  const BackupListing(this.info, this.dayCount);
  final BackupInfo info;

  /// Días con horas que contiene; nulo si el archivo no se pudo leer.
  final int? dayCount;
}

/// Lo que las pantallas necesitan de las copias. [BackupController] es la
/// versión real; en los tests de pantalla se usa una falsa.
abstract interface class BackupService implements Listenable {
  BackupSettings get settings;
  bool get busy;

  /// Sube cada vez que se restaura una copia (RF-14).
  int get restoredCount;

  Future<void> load();
  Future<void> markChanged();
  Future<BackupOutcome?> onLeavingApp();
  Future<bool> chooseFolder();
  Future<BackupOutcome> backupNow();
  Future<List<BackupListing>> listBackups();
  Future<BackupOutcome> restoreFromFolder(String name);

  /// Abre el selector de archivos; devuelve la ruta temporal o nulo (RF-17).
  Future<String?> pickFile();
  Future<BackupOutcome> restoreFromFile(String path);
  Future<BackupOutcome> exportCsv();

  /// Hace una copia completa y abre el menú «Compartir» con ella (023).
  Future<BackupOutcome> shareBackup();

  /// Este móvil: código y nombre (025); nulo mientras se carga.
  DeviceIdentity? get device;

  /// Cambia el nombre de este móvil (025, RF-2). Devuelve el motivo si no
  /// vale (RF-3), o nulo si se ha guardado.
  Future<String?> renameDevice(String name);

  /// La copia más nueva de otro móvil que hay que ofrecer, o nulo (025).
  OtherDeviceOffer? get offer;

  /// Busca en la carpeta una copia más nueva de otro móvil (025, RF-9 a
  /// RF-11, RF-16, RF-17). Se llama al abrir la app y al volver a ella.
  Future<void> checkOtherDevices();

  /// Carga la copia ofrecida, como restaurarla (RF-14).
  Future<BackupOutcome> loadOffer();

  /// «Ahora no»: no se vuelve a ofrecer hasta que haya una más nueva (RF-15).
  Future<void> dismissOffer();
}

/// Lleva las copias: cuándo hacerlas, restaurar y exportar (RF-4 a RF-21).
/// Nunca escribe en los datos de la app salvo al restaurar, y nunca borra
/// copias anteriores si la nueva falla.
class BackupController extends ChangeNotifier implements BackupService {
  BackupController({
    required this.openDatabase,
    required this.settingsStore,
    required this.storage,
    required this.deviceStore,
    this.deviceModel = channelDeviceModel,
    this.factory,
    DateTime Function()? clock,
    Future<Directory> Function()? tempDir,
  }) : _clock = clock ?? DateTime.now,
       _tempDir = tempDir ?? (() => Directory.systemTemp.createTemp('copias_'));

  final Future<Database> Function() openDatabase;
  final SettingsStore settingsStore;
  final FolderStorage storage;

  /// Dónde se guarda quién es este móvil (025).
  final DeviceStore deviceStore;

  /// El modelo del móvil, para su nombre de serie (025, RF-1).
  final Future<String?> Function() deviceModel;
  final DatabaseFactory? factory;
  final DateTime Function() _clock;
  final Future<Directory> Function() _tempDir;

  BackupSettings _settings = const BackupSettings();
  @override
  BackupSettings get settings => _settings;

  bool _busy = false;

  /// Hay una copia, restauración o exportación en marcha.
  @override
  bool get busy => _busy;

  /// Sube cada vez que se restaura una copia; la pantalla de apuntar lo
  /// escucha para volver a leer los datos (RF-14).
  @override
  int restoredCount = 0;

  /// Sube con cada cambio en los datos; sirve para no dar por copiado lo que
  /// cambió mientras se hacía la copia.
  int _changes = 0;

  DeviceIdentity? _device;

  /// Este móvil (025); nulo hasta que termine [load].
  @override
  DeviceIdentity? get device => _device;

  @override
  Future<String?> renameDevice(String name) async {
    final clean = cleanDeviceName(name);
    if (clean == null) return invalidDeviceNameMessage;
    final renamed = (await _ensureDevice()).copyWith(name: clean);
    _device = renamed;
    notifyListeners();
    try {
      await deviceStore.save(renamed);
    } on FileSystemException {
      // Vale para esta sesión; al reabrir volvería el nombre anterior.
    }
    return null;
  }

  /// Lee los ajustes guardados y quién es este móvil. Llamar una vez al
  /// arrancar.
  @override
  Future<void> load() async {
    _settings = await settingsStore.load();
    await _ensureDevice();
    notifyListeners();
    // Al abrir la app, ¿hay algo nuevo de otro móvil? (025, RF-9)
    unawaited(checkOtherDevices());
  }

  Future<DeviceIdentity> _ensureDevice() async =>
      _device ??= await deviceStore.loadOrCreate(deviceModel);

  Future<void> _update(BackupSettings s) async {
    _settings = s;
    notifyListeners();
    try {
      await settingsStore.save(s);
    } on FileSystemException {
      // Sin poder guardar los ajustes, se sigue con los de memoria.
    }
  }

  /// La pantalla de apuntar guardó o borró un día: hay cambios sin copiar.
  @override
  Future<void> markChanged() async {
    _changes++;
    if (!_settings.dirty) await _update(_settings.copyWith(dirty: true));
  }

  /// La app pasa a segundo plano o se cierra (RF-4): copia solo si hay
  /// carpeta y cambios desde la última copia correcta.
  @override
  Future<BackupOutcome?> onLeavingApp() async {
    if (_settings.folder == null || !_settings.dirty || _busy) return null;
    return backupNow();
  }

  /// Abre el selector de carpetas y guarda la elegida (RF-1). Devuelve
  /// verdadero si se eligió una.
  @override
  Future<bool> chooseFolder() async {
    final String? folder;
    try {
      folder = await storage.pickFolder();
    } on StorageException {
      return false;
    }
    if (folder == null) return false;
    await _update(
      _settings.copyWith(folder: () => folder, lastError: () => null),
    );
    return true;
  }

  // ---- Copia ------------------------------------------------------------

  /// Hace una copia ahora, haya o no cambios (RF-11).
  @override
  Future<BackupOutcome> backupNow() => _guarded(() => _backup());

  Future<BackupOutcome> _backup({
    BackupKind kind = BackupKind.automatic,
  }) async {
    final folder = _settings.folder;
    if (folder == null) {
      return const BackupOutcome.fail(
        'Primero elige la carpeta de las copias.',
      );
    }
    final changesBefore = _changes;
    final tmp = await _tempDir();
    try {
      if (!await storage.isAccessible(folder)) {
        throw const StorageException(StorageProblem.noAccess);
      }
      final db = await openDatabase();
      final local = p.join(tmp.path, 'copia-en-curso.db');
      await createBackupFile(db, local, factory: factory);
      final bytes = await File(local).readAsBytes();

      final device = await _ensureDevice();
      final names = (await storage.listFiles(folder)).toSet();
      final name = backupFileName(
        _clock(),
        kind: kind,
        existing: names,
        device: device,
      );
      await storage.writeFile(folder, name, bytes);
      // RF-7: la copia no cuenta hasta leerla de vuelta y ver que es igual.
      final written = await storage.readFile(folder, name);
      if (!_sameBytes(written, bytes)) {
        await _deleteQuietly(folder, name);
        throw const StorageException(StorageProblem.other);
      }
      if (kind == BackupKind.automatic) {
        for (final old in backupsToPrune({
          ...names,
          name,
        }, deviceId: device.id)) {
          await _deleteQuietly(folder, old);
        }
      }
      if (kind == BackupKind.automatic) {
        await _update(
          _settings.copyWith(
            lastSuccess: _clock,
            lastError: () => null,
            dirty: _changes != changesBefore,
          ),
        );
      }
      return BackupOutcome.ok(name);
    } catch (e) {
      final reason = _reasonFor(e);
      if (kind == BackupKind.automatic) {
        await _update(_settings.copyWith(lastError: () => reason));
      }
      return BackupOutcome.fail(reason);
    } finally {
      await _deleteDir(tmp);
    }
  }

  @override
  Future<String?> pickFile() async {
    try {
      return await storage.pickFile();
    } on StorageException {
      return null;
    }
  }

  // ---- Restaurar --------------------------------------------------------

  /// Las copias de la carpeta, de la más reciente a la más antigua, con el
  /// número de días de cada una (RF-12).
  @override
  Future<List<BackupListing>> listBackups() async {
    final folder = _settings.folder;
    if (folder == null) return const [];
    final names = await storage.listFiles(folder);
    final tmp = await _tempDir();
    try {
      final out = <BackupListing>[];
      for (final info in sortedBackups(names)) {
        int? count;
        try {
          final file = await _download(folder, info.name, tmp);
          count = (await readBackupFile(file, factory: factory)).length;
        } catch (_) {
          count = null;
        }
        out.add(BackupListing(info, count));
      }
      return out;
    } finally {
      await _deleteDir(tmp);
    }
  }

  /// Restaura una copia de la carpeta (RF-13, RF-14).
  @override
  Future<BackupOutcome> restoreFromFolder(String name) => _guarded(() async {
    final folder = _settings.folder;
    if (folder == null) {
      return const BackupOutcome.fail(
        'Primero elige la carpeta de las copias.',
      );
    }
    final tmp = await _tempDir();
    try {
      final file = await _download(folder, name, tmp);
      return await _restore(file);
    } on StorageException catch (e) {
      return BackupOutcome.fail(e.message);
    } finally {
      await _deleteDir(tmp);
    }
  });

  /// Restaura un archivo elegido con el selector de Android (RF-17). [path]
  /// es la copia temporal que dejó el selector.
  @override
  Future<BackupOutcome> restoreFromFile(String path) => _guarded(() async {
    try {
      return await _restore(path);
    } finally {
      await _deleteQuietlyFile(path);
    }
  });

  Future<BackupOutcome> _restore(String file) async {
    final BackupData data;
    try {
      data = await readBackupData(file, factory: factory);
    } on BackupException catch (e) {
      return BackupOutcome.fail(e.message); // RF-16: no se toca nada.
    }
    final db = await openDatabase();
    // RF-14/RF-15: antes, una copia de lo actual; si falla, no se restaura.
    // Sin carpeta solo se puede restaurar si no hay nada que perder.
    if (_settings.folder != null) {
      final before = await _backup(kind: BackupKind.beforeRestore);
      if (!before.ok) {
        return BackupOutcome.fail(
          'No se ha podido guardar una copia de lo que tienes ahora, así que '
          'no se ha restaurado nada. ${before.message}',
        );
      }
    } else if ((await readAllDays(db)).isNotEmpty) {
      return const BackupOutcome.fail(
        'Antes de restaurar, elige la carpeta de las copias para guardar lo '
        'que tienes ahora.',
      );
    }
    try {
      await restoreDays(db, data.days, extras: data.extras);
    } catch (_) {
      return const BackupOutcome.fail(
        'No se ha podido restaurar la copia. Tus datos no han cambiado.',
      );
    }
    _changes++;
    restoredCount++;
    await _update(_settings.copyWith(dirty: true));
    final restored = data.days.length == 1
        ? 'Copia restaurada: 1 día con horas.'
        : 'Copia restaurada: ${data.days.length} días con horas.';
    return BackupOutcome.ok(restored + await _setAsideWarning(db));
  }

  /// Una copia antigua no trae los apartados de ahora: si algún mes queda
  /// con menos horas de las apartadas, se avisa sin borrar nada (013,
  /// RF-16).
  Future<String> _setAsideWarning(Database db) async {
    try {
      final days = (await readAllDays(db)).map((d) => d.entry);
      final moves = (await readExtras(db, withSaved: true)).savedMoves!;
      final short = monthsShortOfSetAside(days, moves);
      if (short.isEmpty) return '';
      return ' Revisa los apartados de: '
          '${short.map((m) => monthYear(m.year, m.month).toLowerCase()).join(', ')}'
          ': tienen más horas apartadas que apuntadas.';
    } catch (_) {
      return '';
    }
  }

  // ---- Copias de otros móviles (025) ------------------------------------

  OtherDeviceOffer? _offer;
  @override
  OtherDeviceOffer? get offer => _offer;

  /// Las copias de otros móviles que había en la última búsqueda; sirven
  /// para dar por vistas las más antiguas al cargar o descartar (RF-16).
  List<BackupInfo> _othersSeenInCheck = const [];

  bool _checking = false;

  void _setOffer(OtherDeviceOffer? o) {
    _offer = o;
    notifyListeners();
  }

  @override
  Future<void> checkOtherDevices() async {
    final folder = _settings.folder;
    if (folder == null) {
      if (_offer != null) _setOffer(null);
      return;
    }
    // Mientras se copia o se restaura no se mira: se volverá a mirar.
    if (_busy || _checking) return;
    _checking = true;
    final tmp = await _tempDir();
    try {
      final device = await _ensureDevice();
      final others = [
        for (final b in sortedBackups(await storage.listFiles(folder)))
          if (b.kind == BackupKind.automatic &&
              b.deviceId != null &&
              b.deviceId != device.id)
            b,
      ];
      _othersSeenInCheck = others;
      final newest = others
          .where((b) => b.orderKey.compareTo(device.seen[b.deviceId] ?? '') > 0)
          .firstOrNull;
      if (newest == null) {
        if (_offer != null) _setOffer(null);
        return;
      }
      final BackupData incoming;
      try {
        incoming = await readBackupData(
          await _download(folder, newest.name, tmp),
          factory: factory,
        );
      } on BackupException catch (e) {
        if (e.problem == BackupProblem.tooNew) {
          // Se avisa, pero no se da por vista: se ofrecerá al actualizar.
          _setOffer(OtherDeviceOffer(newest, tooNew: true));
        } else {
          // Dañada: no se ofrece ni se vuelve a intentar con esa.
          await _markSeen(newest);
          if (_offer != null) _setOffer(null);
        }
        return;
      }
      final db = await openDatabase();
      final current = BackupData(
        await readAllDays(db),
        await readExtras(
          db,
          withItems: true,
          withSaved: true,
          withVacation: true,
          withImported: true,
          withCompany: true,
        ),
      );
      final diff = compareBackups(current, incoming);
      if (diff.isEmpty) {
        await _markSeen(newest); // RF-10: ida y vuelta, sin aviso.
        if (_offer != null) _setOffer(null);
        return;
      }
      _setOffer(
        OtherDeviceOffer(newest, diff: diff, localChanges: _settings.dirty),
      );
    } catch (_) {
      // Carpeta no disponible u otro fallo: sin aviso; los fallos de copia
      // ya se avisan aparte (003, RF-8).
    } finally {
      _checking = false;
      await _deleteDir(tmp);
    }
  }

  @override
  Future<BackupOutcome> loadOffer() async {
    final o = _offer;
    if (o == null || o.tooNew) {
      return const BackupOutcome.fail('No hay ninguna copia que cargar.');
    }
    final r = await restoreFromFolder(o.info.name);
    if (r.ok) {
      await _markSeen(o.info);
      _setOffer(null);
    }
    return r;
  }

  @override
  Future<void> dismissOffer() async {
    final o = _offer;
    if (o == null) return;
    await _markSeen(o.info);
    _setOffer(null);
  }

  /// Da por vista [info] y, de los demás móviles, sus copias hasta esa misma
  /// hora (RF-15, RF-16).
  Future<void> _markSeen(BackupInfo info) async {
    final device = await _ensureDevice();
    final seen = {...device.seen};
    void see(BackupInfo b) {
      final id = b.deviceId!;
      if (b.orderKey.compareTo(seen[id] ?? '') > 0) seen[id] = b.orderKey;
    }

    see(info);
    for (final b in _othersSeenInCheck) {
      if (b.deviceId != info.deviceId && !b.takenAt.isAfter(info.takenAt)) {
        see(b);
      }
    }
    final updated = device.copyWith(seen: seen);
    _device = updated;
    try {
      await deviceStore.save(updated);
    } on FileSystemException {
      // Vale para esta sesión.
    }
  }

  // ---- Exportar ---------------------------------------------------------

  /// Crea el CSV, lo guarda en la carpeta si la hay y abre «Compartir»
  /// (RF-18, RF-20, RF-21).
  @override
  Future<BackupOutcome> exportCsv() => _guarded(() async {
    final db = await openDatabase();
    final days = (await readAllDays(db)).map((d) => d.entry).toList();
    final other = await readExtras(
      db,
      withItems: true,
      withSaved: true,
      withVacation: true,
      withImported: true,
    );
    final items = other.items!;
    final saved = other.savedMoves!;
    final vacation = other.vacation!;
    final imported = other.importedMonths!;
    if (days.isEmpty &&
        items.isEmpty &&
        saved.isEmpty &&
        vacation.days.isEmpty &&
        imported.isEmpty) {
      return const BackupOutcome.fail('Aún no hay horas que exportar.');
    }
    final settings = vacation.settings;
    final bytes = Uint8List.fromList(
      utf8.encode(
        buildCsv(
          days,
          extras: items,
          savedMoves: saved,
          imported: imported,
          months: other.months,
          vacationDays: vacation.days,
          vacation: settings == null
              ? null
              : VacationOverview.of(settings, vacation.days, _clock()),
        ),
      ),
    );
    final folder = _settings.folder;
    var name = csvFileName(_clock());
    var savedInFolder = false;
    if (folder != null) {
      try {
        final existing = (await storage.listFiles(folder)).toSet();
        name = csvFileName(_clock(), existing: existing);
        await storage.writeFile(folder, name, bytes);
        savedInFolder = true;
      } on StorageException {
        // Se comparte igualmente; se avisa de que no se guardó en la carpeta.
      }
    }
    try {
      await storage.shareFile(name, 'text/csv', bytes);
    } on StorageException catch (e) {
      return BackupOutcome.fail(e.message);
    }
    return BackupOutcome.ok(
      folder == null || savedInFolder
          ? name
          : '$name (no se ha podido guardar en la carpeta de copias)',
    );
  });

  // ---- Compartir copia (023) --------------------------------------------

  /// Copia completa, comprobada como las automáticas (createBackupFile la lee
  /// de vuelta), al menú «Compartir». No toca la carpeta ni «Última copia»
  /// (RF-2 a RF-5).
  @override
  Future<BackupOutcome> shareBackup() => _guarded(() async {
    final tmp = await _tempDir();
    try {
      final db = await openDatabase();
      final local = p.join(tmp.path, 'copia-a-compartir.db');
      await createBackupFile(db, local, factory: factory);
      final bytes = await File(local).readAsBytes();
      final name = backupFileName(_clock(), device: await _ensureDevice());
      await storage.shareFile(name, 'application/octet-stream', bytes);
      await _update(_settings.copyWith(lastShared: _clock));
      return BackupOutcome.ok(name);
    } finally {
      await _deleteDir(tmp);
    }
  });

  // ---- Utilidades -------------------------------------------------------

  /// Una sola acción a la vez: si ya hay una en marcha, no se lanza otra.
  Future<BackupOutcome> _guarded(
    Future<BackupOutcome> Function() action,
  ) async {
    if (_busy) {
      return const BackupOutcome.fail('Ya hay otra operación en marcha.');
    }
    _busy = true;
    notifyListeners();
    try {
      return await action();
    } catch (e) {
      return BackupOutcome.fail(_reasonFor(e));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Texto sencillo para un fallo; nunca incluye datos de los días.
  String _reasonFor(Object e) => switch (e) {
    StorageException() => e.message,
    BackupException() => e.message,
    _ => 'No se ha podido completar la operación. Tus datos no han cambiado.',
  };

  Future<String> _download(String folder, String name, Directory tmp) async {
    final bytes = await storage.readFile(folder, name);
    final file = File(p.join(tmp.path, 'elegida.db'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  bool _sameBytes(Uint8List a, Uint8List b) => listEquals(a, b);

  Future<void> _deleteQuietly(String folder, String name) async {
    try {
      await storage.deleteFile(folder, name);
    } on StorageException {
      // Una copia vieja que no se puede borrar no es un fallo de la nueva.
    }
  }

  Future<void> _deleteDir(Directory d) async {
    try {
      if (await d.exists()) await d.delete(recursive: true);
    } on FileSystemException {
      // Es temporal: Android la limpiará.
    }
  }

  Future<void> _deleteQuietlyFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // Es temporal.
    }
  }
}
