import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'backup_controller.dart';

/// Aviso discreto bajo el motivo, con un solo botón (RF-3, RF-8). No ocupa
/// sitio cuando todo está en orden.
class BackupNotice extends StatelessWidget {
  const BackupNotice({super.key, required this.backup, required this.onReview});

  final BackupService backup;

  /// Lleva a la pantalla de copias.
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: backup,
      builder: (context, _) {
        final s = backup.settings;
        final String text;
        final String button;
        final VoidCallback action;
        if (s.folder == null) {
          text = 'Tus horas aún no tienen copia';
          button = 'Elegir carpeta';
          action = backup.chooseFolder;
        } else if (s.lastError != null) {
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
