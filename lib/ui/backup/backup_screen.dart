import 'package:flutter/material.dart';

import '../../domain/backup_names.dart';
import '../../domain/device_identity.dart';
import '../components/confirm_dialog.dart';
import '../components/info_button.dart';
import '../components/state_message.dart';
import '../format.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'backup_controller.dart';
import 'backup_text.dart';

const _syncthingTitle = 'Llevar las copias a otro sitio';
const _syncthingText =
    'Con la app gratuita Syncthing puedes llevar la carpeta de las copias al '
    'ordenador o a otro móvil. Con un solo móvil, ponla en modo «Solo '
    'enviar», para que nada de fuera pueda cambiar las copias. Con dos '
    'móviles, elige en los dos la misma carpeta y ponla en «Enviar y '
    'recibir» en ambos: al abrir la app, cada uno te ofrecerá cargar los '
    'cambios del otro, por turnos y guardando antes lo tuyo. Hay más '
    'detalle en Ayuda.';

const _shareTitle = 'Compartir copia';
const _shareText =
    'Hace una copia completa de tus datos y abre el menú «Compartir» del '
    'móvil para que la guardes donde quieras: en Google Drive, en tu correo, '
    'en WhatsApp… Para recuperarla, en «Restaurar una copia» pulsa «Elegir '
    'otro archivo…» y búscala donde la guardaste. Sin carpeta de copias, '
    'solo se puede restaurar con la app vacía (por ejemplo, en un móvil '
    'nuevo). La app no sabe si llegaste a guardarla: te lo recordará a los '
    '15 días.';

void _say(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Pide el nuevo nombre del móvil (025, RF-2, RF-3). Se queda abierto,
/// con el motivo, mientras el nombre no valga.
class _RenameDeviceDialog extends StatefulWidget {
  const _RenameDeviceDialog({required this.backup, required this.current});

  final BackupService backup;
  final String current;

  @override
  State<_RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<_RenameDeviceDialog> {
  late final _text = TextEditingController(text: widget.current);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final error = await widget.backup.renameDevice(_text.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nombre de este móvil'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sale en el nombre de sus copias, para saber de qué móvil es '
            'cada una',
            style: AppText.body.copyWith(color: context.colors.textSoft),
          ),
          const SizedBox(height: Space.m),
          TextField(
            key: const ValueKey('nombre-movil'),
            controller: _text,
            autofocus: true,
            maxLength: deviceNameMaxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(errorText: _error),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}

/// Pantalla «Copias y exportación» (Ajustes).
class BackupScreen extends StatelessWidget {
  const BackupScreen({
    super.key,
    required this.backup,
    this.waitForSaves,
    this.clock,
  });

  final BackupService backup;

  /// Termina cuando no queda ningún guardado pendiente; se espera antes de
  /// restaurar.
  final Future<void> Function()? waitForSaves;

  /// Reloj para los tests; si es nulo, la hora real.
  final DateTime Function()? clock;

  DateTime get _now => (clock ?? DateTime.now)();

  Future<void> _run(
    BuildContext context,
    Future<BackupOutcome> Function() action,
    String okText,
  ) async {
    final r = await action();
    if (context.mounted) _say(context, r.ok ? okText : r.message);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Copias y exportación')),
      body: ListenableBuilder(
        listenable: backup,
        builder: (context, _) {
          final s = backup.settings;
          final busy = backup.busy;
          final folder = s.folder;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.s,
              Space.gutter,
              Space.xxxl,
            ),
            children: [
              if (busy) const LinearProgressIndicator(),
              Container(
                padding: const EdgeInsets.all(Space.l),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(Radii.medium),
                  border: Border.all(color: c.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 025, RF-2.
                    if (backup.device case final device?) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Este móvil',
                                  style: AppText.label.copyWith(
                                    color: c.textSoft,
                                  ),
                                ),
                                Text(device.name, style: AppText.bodyStrong),
                              ],
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('cambiar-nombre-movil'),
                            tooltip: 'Cambiar el nombre del móvil',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => _RenameDeviceDialog(
                                backup: backup,
                                current: device.name,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.s),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Carpeta',
                                style: AppText.label.copyWith(
                                  color: c.textSoft,
                                ),
                              ),
                              Text(
                                folder == null
                                    ? 'Sin elegir'
                                    : folderLabel(folder),
                                style: AppText.bodyStrong,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: folder == null
                              ? 'Elegir carpeta'
                              : 'Cambiar carpeta',
                          icon: Icon(
                            folder == null
                                ? Icons.create_new_folder_outlined
                                : Icons.edit_outlined,
                          ),
                          onPressed: busy ? null : backup.chooseFolder,
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.s),
                    Text(
                      'Última copia',
                      style: AppText.label.copyWith(color: c.textSoft),
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.lastSuccess == null
                                ? 'Todavía ninguna'
                                : capitalized(
                                    backupMoment(s.lastSuccess!, now: _now),
                                  ),
                            style: AppText.bodyStrong,
                          ),
                        ),
                        if (s.lastSuccess != null && s.lastError == null) ...[
                          const SizedBox(width: Space.s),
                          Icon(
                            Icons.check_circle_outline,
                            size: 20,
                            color: c.normal.strong,
                            semanticLabel: 'Correcta',
                          ),
                        ],
                      ],
                    ),
                    if (s.lastError != null) ...[
                      const SizedBox(height: Space.s),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline, size: 20, color: c.error),
                          const SizedBox(width: Space.s),
                          Expanded(
                            child: Text(
                              'La última copia falló. ${s.lastError}',
                              style: AppText.body.copyWith(color: c.error),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: Space.l),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: busy
                            ? null
                            : () => _run(
                                context,
                                backup.backupNow,
                                'Copia hecha correctamente.',
                              ),
                        child: const Text('Hacer copia ahora'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.l),
              // 023, RF-1 y RF-10.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('compartir-copia'),
                      onPressed: busy
                          ? null
                          : () => _run(
                              context,
                              backup.shareBackup,
                              'Listo: elige dónde guardar la copia.',
                            ),
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Compartir copia'),
                    ),
                  ),
                  const InfoButton(title: _shareTitle, text: _shareText),
                ],
              ),
              if (s.lastShared != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    'Última copia compartida: '
                    '${backupMoment(s.lastShared!, now: _now)}',
                    style: AppText.label.copyWith(color: c.textSoft),
                  ),
                ),
              const SizedBox(height: Space.l),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => RestoreScreen(
                              backup: backup,
                              waitForSaves: waitForSaves,
                              clock: clock,
                            ),
                          ),
                        ),
                  child: const Text('Restaurar una copia'),
                ),
              ),
              const SizedBox(height: Space.s),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _run(
                          context,
                          backup.exportCsv,
                          'Listo: elige dónde enviar el archivo.',
                        ),
                  child: const Text('Exportar a Excel'),
                ),
              ),
              const SizedBox(height: Space.l),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cómo llevar las copias al ordenador o a otro móvil con '
                      'Syncthing',
                      style: AppText.body.copyWith(color: c.textSoft),
                    ),
                  ),
                  const InfoButton(
                    title: _syncthingTitle,
                    text: _syncthingText,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Lista de copias para elegir una y restaurarla (RF-12, RF-13, RF-17).
class RestoreScreen extends StatefulWidget {
  const RestoreScreen({
    super.key,
    required this.backup,
    this.waitForSaves,
    this.clock,
  });

  final BackupService backup;
  final Future<void> Function()? waitForSaves;
  final DateTime Function()? clock;

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  late Future<List<BackupListing>> _list = _load();
  bool _working = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  Future<List<BackupListing>> _load() => widget.backup.listBackups();

  Future<void> _restore({
    required String what,
    required Future<BackupOutcome> Function() action,
  }) async {
    final ok = await confirmDelete(
      context,
      title: 'Restaurar una copia',
      message:
          'Se sustituirán todos tus datos por los de $what. Antes '
          'guardaremos una copia de lo que tienes ahora.',
      confirmLabel: 'Restaurar',
    );
    if (!ok || !mounted) return;
    setState(() => _working = true);
    await widget.waitForSaves?.call(); // primero termina el guardado
    final r = await action();
    if (!mounted) return;
    setState(() => _working = false);
    _say(context, r.message);
    if (r.ok) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _pickFile() async {
    final path = await widget.backup.pickFile();
    if (path == null || !mounted) return;
    await _restore(
      what: 'este archivo',
      action: () => widget.backup.restoreFromFile(path),
    );
  }

  /// «la copia del 3 de noviembre» (con el año si no es el actual).
  String _copyName(DateTime t) =>
      'la copia del ${t.day} de ${monthName(t.month)}'
      '${t.year == _now.year ? '' : ' de ${t.year}'}';

  /// De qué móvil es (025, RF-7, RF-8).
  String _device(BackupInfo info) {
    if (info.deviceId == null) return 'Copia antigua';
    if (info.deviceId == widget.backup.device?.id) return 'Este móvil';
    return info.deviceName ?? 'Otro móvil';
  }

  String _title(BackupListing b) {
    final when = capitalized(backupMoment(b.info.takenAt, now: _now));
    return b.info.kind == BackupKind.beforeRestore
        ? '$when · antes de restaurar'
        : when;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Restaurar una copia')),
      body: FutureBuilder<List<BackupListing>>(
        future: _list,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: StateMessage.loading(message: 'Buscando copias…'),
            );
          }
          if (snap.hasError) {
            return Center(
              child: StateMessage.error(
                title: 'No se pueden leer las copias',
                message:
                    'Mira que la carpeta siga existiendo y vuelve a '
                    'intentarlo.',
                actionLabel: 'Reintentar',
                onAction: () => setState(() => _list = _load()),
              ),
            );
          }
          final copies = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.s,
              Space.gutter,
              Space.xxxl,
            ),
            children: [
              if (_working) const LinearProgressIndicator(),
              if (copies.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.l),
                  child: Text(
                    widget.backup.settings.folder == null
                        ? 'Aún no has elegido carpeta de copias. Puedes '
                              'restaurar un archivo de copia de todos modos.'
                        : 'No hay copias en la carpeta todavía.',
                    style: AppText.body.copyWith(color: c.textSoft),
                  ),
                ),
              for (final b in copies)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  minVerticalPadding: Space.s,
                  title: Text(_title(b), style: AppText.bodyStrong),
                  subtitle: Text(
                    '${_device(b.info)} · ${switch (b.dayCount) {
                      null => 'no se puede leer',
                      1 => '1 día con horas',
                      final n => '$n días con horas',
                    }}',
                    style: AppText.body.copyWith(color: c.textSoft),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !_working,
                  onTap: () => _restore(
                    what: _copyName(b.info.takenAt),
                    action: () => widget.backup.restoreFromFolder(b.info.name),
                  ),
                ),
              const SizedBox(height: Space.l),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _working ? null : _pickFile,
                  child: const Text('Elegir otro archivo…'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
