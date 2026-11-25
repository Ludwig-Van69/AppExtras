import 'package:flutter/material.dart';

import '../../data/backup_diff.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'backup_controller.dart';
import 'backup_text.dart';
import 'diff_text.dart';

/// «igual», «1 distinto», «3 distintos».
String diffCountText(int n) => switch (n) {
  0 => 'igual',
  1 => '1 distinto',
  _ => '$n distintos',
};

/// Enseña qué cambia con la copia del otro móvil y pregunta si cargarla
/// (025, RF-12 a RF-15). Cerrar el diálogo cuenta como «Ahora no».
Future<void> showOtherDeviceDialog(
  BuildContext context, {
  required BackupService backup,
  Future<void> Function()? waitForSaves,
  DateTime Function()? clock,
  bool hideAmounts = false,
}) async {
  final offer = backup.offer;
  final diff = offer?.diff;
  if (offer == null || diff == null) return;
  final now = (clock ?? DateTime.now)();
  final load = await showDialog<bool>(
    context: context,
    builder: (context) {
      final c = context.colors;
      return AlertDialog(
        // Con letra grande no cabe: se desplaza en vez de desbordar.
        scrollable: true,
        title: Text('Cambios de ${offer.deviceName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Copia hecha ${backupMoment(offer.info.takenAt, now: now)}',
              style: AppText.body.copyWith(color: c.textSoft),
            ),
            const SizedBox(height: Space.m),
            _DiffSections(
              diff: diff,
              otherName: offer.deviceName,
              hideAmounts: hideAmounts,
            ),
            const SizedBox(height: Space.m),
            Text(
              offer.localChanges
                  ? 'Este móvil tiene cambios sin copia. Se guardarán en la '
                        'copia previa antes de cargar.'
                  : 'Lo de este móvil se guardará en una copia antes de '
                        'cargar.',
              style: AppText.body.copyWith(color: c.textSoft),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cargar'),
          ),
        ],
      );
    },
  );
  if (load != true) {
    await backup.dismissOffer();
    return;
  }
  await waitForSaves?.call(); // primero termina el guardado
  final r = await backup.loadOffer();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          r.ok ? 'Cargados los cambios de ${offer.deviceName}' : r.message,
        ),
      ),
    );
}

/// Los apartados del resumen; los que tienen cambios se despliegan al
/// tocarlos (RF-12b, RF-12c).
class _DiffSections extends StatefulWidget {
  const _DiffSections({
    required this.diff,
    required this.otherName,
    required this.hideAmounts,
  });

  final BackupDiff diff;
  final String otherName;
  final bool hideAmounts;

  @override
  State<_DiffSections> createState() => _DiffSectionsState();
}

class _DiffSectionsState extends State<_DiffSections> {
  final _open = <DiffSection>{};

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final s in widget.diff.sections) ...[
        _row(context, s.section, s.label, s.count),
        if (_open.contains(s.section)) _detail(context, s.section),
      ],
    ],
  );

  Widget _row(BuildContext context, DiffSection section, String label, int n) {
    final c = context.colors;
    final open = _open.contains(section);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.body)),
          const SizedBox(width: Space.s),
          // Con letra grande, la cifra también puede partirse en dos líneas.
          Flexible(
            child: Text(
              diffCountText(n),
              textAlign: TextAlign.end,
              style: n == 0
                  ? AppText.body.copyWith(color: c.textSoft)
                  : AppText.bodyStrong,
            ),
          ),
          if (n > 0)
            Icon(open ? Icons.expand_less : Icons.expand_more, size: 20)
          else
            const SizedBox(width: 20),
        ],
      ),
    );
    if (n == 0) return row;
    return Semantics(
      button: true,
      expanded: open,
      child: InkWell(
        key: ValueKey('apartado-${section.name}'),
        borderRadius: BorderRadius.circular(Radii.small),
        onTap: () =>
            setState(() => open ? _open.remove(section) : _open.add(section)),
        child: row,
      ),
    );
  }

  Widget _detail(BuildContext context, DiffSection section) {
    final c = context.colors;
    final lines = diffLines(
      widget.diff,
      section,
      hideAmounts: widget.hideAmounts,
    );
    final shown = lines.take(diffLinesShown);
    final more = lines.length - shown.length;
    return Padding(
      padding: const EdgeInsets.only(left: Space.m, bottom: Space.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.what,
                    style: AppText.label.copyWith(color: c.textSoft),
                  ),
                  Text(
                    'aquí ${l.here}  →  ${widget.otherName} ${l.there}',
                    style: AppText.body,
                  ),
                ],
              ),
            ),
          if (more > 0)
            Text(
              'y $more más',
              style: AppText.label.copyWith(color: c.textSoft),
            ),
        ],
      ),
    );
  }
}

/// Texto del aviso de Apuntar para una copia de otro móvil (RF-11, RF-17).
String otherDeviceNoticeText(OtherDeviceOffer o, DateTime now) => o.tooNew
    ? '${o.deviceName} tiene una versión más nueva de la app. Actualiza esta '
          'para ver sus cambios'
    : 'Hay cambios de ${o.deviceName} · '
          '${backupMoment(o.info.takenAt, now: now)}';
