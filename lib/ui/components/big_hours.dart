import 'package:flutter/material.dart';

import '../format.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'haptics.dart';
import 'roll_switcher.dart';

/// Cifra grande de horas, siempre del mismo tamaño (RF-16). Al cambiar, la
/// anterior sale y la nueva entra como un marcador (RF-28). Incluye la acción
/// «Borrar las horas del día» (RF-17).
class BigHours extends StatefulWidget {
  const BigHours({super.key, required this.minutes, this.onDelete});

  final int minutes;

  /// Si es nulo, no se muestra la acción de borrar.
  final VoidCallback? onDelete;

  /// La cifra más ancha que puede mostrarse; fija el tamaño para todas.
  static const widest = '88,88';

  @override
  State<BigHours> createState() => _BigHoursState();
}

class _BigHoursState extends State<BigHours> {
  bool _rising = true;

  @override
  void didUpdateWidget(BigHours old) {
    super.didUpdateWidget(old);
    if (old.minutes != widget.minutes) _rising = widget.minutes > old.minutes;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = formatMinutes(widget.minutes);
    final showDelete = widget.minutes > 0 && widget.onDelete != null;

    // El botón de borrar ocupa siempre su hueco a la derecha, aunque no se
    // vea, y la cifra tiene un tamaño fijo calculado para la más ancha:
    // así el botón nunca se mueve y nada se sale de su sitio.
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - Sizes.touch - Space.s;
        final unit = AppText.title.copyWith(color: c.text);
        final scale = _fit(context, available);
        final hero = AppText.hero.copyWith(
          color: c.text,
          fontSize: AppText.hero.fontSize! * scale,
        );

        final number = RollSwitcher(
          value: text,
          forward: _rising,
          vertical: true,
          duration: Motion.roll,
          alignment: Alignment.bottomLeft,
          clip: true,
          child: Text(text, style: hero, maxLines: 1, softWrap: false),
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Semantics(
                label: hoursPhrase(widget.minutes),
                excludeSemantics: true,
                // La «h» va justo detrás de la cifra, en la misma línea
                // base, y se desliza a la vez que entra la nueva: su sitio
                // sigue a la cifra que entra, no a la que sale.
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: _textSize(context, text, hero).width),
                      duration: context.motion(Motion.roll),
                      curve: Curves.easeOutCubic,
                      // Lo que sobresale del hueco se recorta, para que la
                      // «h» nunca pise una cifra mientras cambia.
                      builder: (context, width, child) => ClipRect(
                        child: SizedBox(
                          key: const ValueKey('big-hours-number'),
                          width: width,
                          height: _textSize(context, text, hero).height,
                          child: OverflowBox(
                            alignment: Alignment.bottomLeft,
                            minWidth: 0,
                            maxWidth: double.infinity,
                            child: child,
                          ),
                        ),
                      ),
                      child: number,
                    ),
                    const SizedBox(width: Space.s),
                    Text('h', style: unit),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Space.s),
            SizedBox.square(
              dimension: Sizes.touch,
              child: showDelete
                  ? IconButton(
                      onPressed: () {
                        Haptics.delete();
                        widget.onDelete!();
                      },
                      tooltip: 'Borrar las horas del día',
                      icon: const Icon(Icons.delete_outline),
                      style: IconButton.styleFrom(
                        backgroundColor: c.surface,
                        side: BorderSide(color: c.outline),
                      ),
                    )
                  : null,
            ),
          ],
        );
      },
    );
  }

  /// Tamaño que ocupa [text] con [style] y el tamaño de letra del móvil.
  Size _textSize(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final size = painter.size;
    painter.dispose();
    return size;
  }

  /// Escala de la cifra para que la más ancha posible quepa en [available].
  /// Es la misma para todos los valores, así la cifra no cambia de tamaño.
  double _fit(BuildContext context, double available) {
    final scaler = MediaQuery.textScalerOf(context);
    double widthOf(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    }

    final number = widthOf(BigHours.widest, AppText.hero);
    final unit = widthOf('h', AppText.title);
    // Solo se encoge la cifra: el hueco y la «h» mantienen su tamaño.
    // Se dejan 2 px de margen por los redondeos al dibujar.
    final room = available - Space.s - unit - 2;
    final scale = number <= room ? 1.0 : (room / number).clamp(0.1, 1.0);
    return scale;
  }
}
