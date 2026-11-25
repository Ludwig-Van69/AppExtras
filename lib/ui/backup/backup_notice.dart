import 'package:flutter/material.dart';

import '../../data/app_settings.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'backup_controller.dart';
import 'other_device_dialog.dart';

/// Aviso discreto bajo el motivo, con un solo botón (003, RF-3 y RF-8; 023,
/// RF-6 a RF-9; 025, RF-11, RF-17, RF-18). No ocupa sitio cuando todo está
/// en orden.
class BackupNotice extends StatelessWidget {
  const BackupNotice({
    super.key,
    required this.backup,
    required this.onReview,
    this.waitForSaves,
    this.hideAmounts,
    this.clock,
  });

  /// Si los importes están ocultos (005, RF-11): el detalle de cambios del
  /// otro móvil los tapa (025, RF-12d).
  final bool Function()? hideAmounts;

  final BackupService backup;

  /// Lleva a la pantalla de copias.
  final VoidCallback onReview;

  /// Termina cuando no queda ningún guardado pendiente; se espera antes de
  /// cargar la copia de otro móvil.
  final Future<void> Function()? waitForSaves;

  /// Reloj para los tests; si es nulo, la hora real.
  final DateTime Function()? clock;

  Future<void> _share(BuildContext context) async {
    final r = await backup.shareBackup();
    if (!r.ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(r.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: backup,
      builder: (context, _) {
        final s = backup.settings;
        final now = (clock ?? DateTime.now)();
        final String text;
        final String? button;
        final VoidCallback? action;
        final offer = backup.offer;
        final reminder = s.shareReminder(now);
        // Orden (025, RF-18): copia fallida, cambios de otro móvil y
        // recordatorios de copia. Los recordatorios solo salen sin carpeta, y
        // los otros dos solo con carpeta.
        if (s.folder != null && s.lastError != null) {
          text = 'No se ha podido hacer la copia';
          button = 'Revisar';
          action = onReview;
        } else if (offer != null) {
          text = otherDeviceNoticeText(offer, now);
          button = offer.tooNew ? null : 'Ver';
          action = offer.tooNew
              ? null
              : () => showOtherDeviceDialog(
                  context,
                  backup: backup,
                  waitForSaves: waitForSaves,
                  clock: clock,
                  hideAmounts: hideAmounts?.call() ?? false,
                );
        } else if (reminder == ShareReminder.never) {
          text = 'Tus horas aún no tienen copia';
          button = 'Hacer copia';
          action = onReview;
        } else if (reminder == ShareReminder.overdue) {
          text =
              'Hace más de ${BackupSettings.shareReminderDays} días que no '
              'guardas una copia';
          button = 'Compartir copia';
          action = () => _share(context);
        } else {
          return const SizedBox.shrink();
        }
        final c = context.colors;
        final failed = s.folder != null && s.lastError != null;
        return Padding(
          padding: const EdgeInsets.only(top: Space.m),
          child: Semantics(
            container: true,
            child: Row(
              children: [
                Icon(
                  failed
                      ? Icons.error_outline
                      : offer != null
                      ? Icons.sync_outlined
                      : Icons.cloud_off_outlined,
                  size: 20,
                  color: failed ? c.error : c.textSoft,
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    text,
                    style: AppText.label.copyWith(color: c.text),
                  ),
                ),
                if (button != null)
                  TextButton(onPressed: action, child: Text(button)),
              ],
            ),
          ),
        );
      },
    );
  }
}
