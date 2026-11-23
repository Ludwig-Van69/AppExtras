import 'package:flutter/material.dart';

import '../../data/app_settings.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'backup_controller.dart';

/// Aviso discreto bajo el motivo, con un solo botón (003, RF-3 y RF-8; 023,
/// RF-6 a RF-9). No ocupa sitio cuando todo está en orden.
class BackupNotice extends StatelessWidget {
  const BackupNotice({
    super.key,
    required this.backup,
    required this.onReview,
    this.clock,
  });

  final BackupService backup;

  /// Lleva a la pantalla de copias.
  final VoidCallback onReview;

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
        final String text;
        final String button;
        final VoidCallback action;
        final reminder = s.shareReminder((clock ?? DateTime.now)());
        if (reminder == ShareReminder.never) {
          text = 'Tus horas aún no tienen copia';
          button = 'Hacer copia';
          action = onReview;
        } else if (reminder == ShareReminder.overdue) {
          text =
              'Hace más de ${BackupSettings.shareReminderDays} días que no '
              'guardas una copia';
          button = 'Compartir copia';
          action = () => _share(context);
        } else if (s.folder != null && s.lastError != null) {
          text = 'No se ha podido hacer la copia';
          button = 'Revisar';
          action = onReview;
        } else {
          return const SizedBox.shrink();
        }
        final c = context.colors;
        return Padding(
          padding: const EdgeInsets.only(top: Space.m),
          child: Semantics(
            container: true,
            child: Row(
              children: [
                Icon(
                  s.folder == null
                      ? Icons.cloud_off_outlined
                      : Icons.error_outline,
                  size: 20,
                  color: s.folder == null ? c.textSoft : c.error,
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    text,
                    style: AppText.label.copyWith(color: c.text),
                  ),
                ),
                TextButton(onPressed: action, child: Text(button)),
              ],
            ),
          ),
        );
      },
    );
  }
}
