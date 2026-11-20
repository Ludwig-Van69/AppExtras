import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Marca grande «✓ Apuntado» que confirma que se han guardado horas
/// (012, RF-5). Aparece cada vez que cambia [trigger] (con 0 se quita) y
/// se va sola en [SavedMark.duration]. Con las animaciones reducidas, aparece
/// y desaparece sin movimiento. No se puede tocar: nunca tapa un botón.
class SavedMark extends StatefulWidget {
  const SavedMark({super.key, required this.trigger, required this.kind});

  /// Contador de apuntes: cada valor nuevo enseña la marca otra vez.
  final int trigger;

  /// Color de la marca: el del tipo de hora (Normal o Festiva).
  final DataKind kind;

  /// Lo que dura en pantalla, de principio a fin.
  static const duration = Duration(milliseconds: 1400);

  @override
  State<SavedMark> createState() => _SavedMarkState();
}

class _SavedMarkState extends State<SavedMark>
    with SingleTickerProviderStateMixin {
  // «preserve»: con las animaciones reducidas, la marca no se mueve pero se
  // queda en pantalla el mismo tiempo, para que dé tiempo a leerla.
  late final _c = AnimationController(
    vsync: this,
    duration: SavedMark.duration,
    animationBehavior: AnimationBehavior.preserve,
  )..addListener(() => setState(() {}));

  @override
  void didUpdateWidget(SavedMark old) {
    super.didUpdateWidget(old);
    if (widget.trigger == old.trigger) return;
    // 0: el apunte no se pudo guardar; la marca se quita al momento.
    widget.trigger > 0 ? _c.forward(from: 0) : _c.reset();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_c.isAnimating) return const SizedBox.shrink();
    final t = _c.value;
    final calm = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // Entra suave, sin rebote (0-20 %), se queda y sale fundiéndose
    // (80-100 %).
    final opacity = calm
        ? 1.0
        : t < 0.2
        ? t / 0.2
        : t > 0.8
        ? (1 - t) / 0.2
        : 1.0;
    final scale = calm
        ? 1.0
        : t < 0.2
        ? 0.9 + 0.1 * Curves.easeOutCubic.transform(t / 0.2)
        : 1.0;
    final c = context.colors;
    final k = c.of(widget.kind);
    return IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale,
          child: Semantics(
            liveRegion: true,
            child: Container(
              key: const ValueKey('marca-apuntado'),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.xl,
                vertical: Space.m,
              ),
              decoration: BoxDecoration(
                color: k.strong,
                borderRadius: BorderRadius.circular(Radii.medium),
                boxShadow: [
                  // Sombra neutra y pequeña, sin color.
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: k.onStrong, size: 28),
                  const SizedBox(width: Space.s),
                  Text(
                    'Apuntado',
                    style: AppText.title.copyWith(color: k.onStrong),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
