import 'package:flutter/material.dart';

import '../../domain/metrics.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Evolución de todos los meses: una barra por mes y, encima, la media de
/// los últimos 12 meses (017, RF-3). Siempre en horas. Al tocar o arrastrar
/// el dedo se marca un mes y arriba sale su cifra (RF-4).
class EvolutionChart extends StatefulWidget {
  const EvolutionChart({
    super.key,
    required this.points,
    required this.label,
    required this.averageLabel,
  });

  final List<MonthPoint> points;
  final String Function(MonthPoint) label;

  /// «Media de 12 meses: 8,5 h», en su propia línea (017, RF-4).
  final String Function(int minutes) averageLabel;

  static const height = 160.0;

  @override
  State<EvolutionChart> createState() => _EvolutionChartState();
}

class _EvolutionChartState extends State<EvolutionChart> {
  /// Mes marcado; nulo: el último.
  int? _selected;

  void _pick(double dx, double width) {
    final n = widget.points.length;
    if (n == 0 || width <= 0) return;
    final i = (dx / width * n).floor().clamp(0, n - 1);
    if (i != _selected) setState(() => _selected = i);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final points = widget.points;
    final shown = (_selected ?? points.length - 1).clamp(0, points.length - 1);
    final hasAverage = points.any((p) => p.average != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            widget.label(points[shown]),
            key: const ValueKey('evolucion-elegido'),
            style: AppText.bodyStrong,
          ),
        ),
        // La media va en su línea, siempre reservada, para que el gráfico no
        // salte al recorrer los meses.
        if (hasAverage)
          Text(
            points[shown].average == null
                ? ''
                : widget.averageLabel(points[shown].average!),
            key: const ValueKey('evolucion-media'),
            style: AppText.caption.copyWith(color: c.textSoft),
          ),
        const SizedBox(height: Space.s),
        LayoutBuilder(
          builder: (context, box) => Semantics(
            label:
                'Gráfico de evolución de ${points.length} meses. Desliza el '
                'dedo para ver cada mes.',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _pick(d.localPosition.dx, box.maxWidth),
              onHorizontalDragStart: (d) =>
                  _pick(d.localPosition.dx, box.maxWidth),
              onHorizontalDragUpdate: (d) =>
                  _pick(d.localPosition.dx, box.maxWidth),
              child: CustomPaint(
                key: const ValueKey('grafico-evolucion'),
                size: Size(box.maxWidth, EvolutionChart.height),
                painter: _EvolutionPainter(
                  values: [for (final p in points) p.figure.minutes],
                  averages: [for (final p in points) p.average],
                  years: [
                    for (var i = 0; i < points.length; i++)
                      if (i == 0 || points[i].month.month == 1)
                        (i, '${points[i].month.year}'),
                  ],
                  selected: shown,
                  bar: c.outline,
                  barSelected: c.text,
                  average: c.normal.strong,
                  grid: c.line,
                  surface: c.background,
                  labelStyle: AppText.caption.copyWith(color: c.textSoft),
                ),
              ),
            ),
          ),
        ),
        if (hasAverage) ...[
          const SizedBox(height: Space.s),
          Wrap(
            key: const ValueKey('leyenda-media'),
            spacing: Space.l,
            runSpacing: Space.xs,
            children: [
              _legend(
                Container(
                  width: Sizes.legendSwatch,
                  height: Sizes.legendSwatch,
                  decoration: BoxDecoration(
                    color: c.outline,
                    borderRadius: BorderRadius.circular(Radii.tiny),
                  ),
                ),
                'Horas del mes',
              ),
              _legend(
                Container(width: 16, height: 3, color: c.normal.strong),
                'Media de 12 meses',
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _legend(Widget swatch, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      swatch,
      const SizedBox(width: Space.tileGap),
      Text(text, style: AppText.caption),
    ],
  );
}

class _EvolutionPainter extends CustomPainter {
  _EvolutionPainter({
    required this.values,
    required this.averages,
    required this.years,
    required this.selected,
    required this.bar,
    required this.barSelected,
    required this.average,
    required this.grid,
    required this.surface,
    required this.labelStyle,
  });

  final List<int> values;
  final List<int?> averages;

  /// Índice del mes donde empieza cada año y su etiqueta.
  final List<(int, String)> years;
  final int selected;
  final Color bar;
  final Color barSelected;
  final Color average;
  final Color grid;
  final Color surface;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    // Abajo queda sitio para los años; arriba, un margen para la línea.
    final labelHeight = (labelStyle.fontSize ?? 12) * 1.6;
    const top = 6.0;
    final bottom = size.height - labelHeight;
    final plot = bottom - top;
    final max = values.fold(0, (a, b) => a > b ? a : b);
    final n = values.length;
    final slot = size.width / n;
    // Barras finas con un hueco entre ellas; con muchos meses, al menos 1 px.
    final width = (slot * 0.62).clamp(1.0, 14.0);
    double center(int i) => slot * i + slot / 2;
    double y(int v) => max <= 0 ? bottom : bottom - plot * v / max;

    // Línea base y separaciones de año, recesivas.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, bottom), Offset(size.width, bottom), gridPaint);
    // Con muchos años no caben todas las etiquetas: se salta la que pisaría
    // a la anterior (la separación sí se dibuja).
    var freeFrom = double.negativeInfinity;
    for (final (i, label) in years) {
      final gx = slot * i;
      if (i > 0) {
        canvas.drawLine(Offset(gx, top), Offset(gx, bottom), gridPaint);
      }
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final lx = (gx + 2).clamp(0.0, size.width - tp.width);
      if (lx < freeFrom) continue;
      tp.paint(canvas, Offset(lx, bottom + 4));
      freeFrom = lx + tp.width + 6;
    }

    // Barras, con la parte de arriba redondeada.
    for (var i = 0; i < n; i++) {
      if (values[i] <= 0) continue;
      final h = (bottom - y(values[i])).clamp(2.0, plot);
      final r = Radius.circular((width / 2).clamp(0.0, 3.0));
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(center(i) - width / 2, bottom - h, width, h),
          topLeft: r,
          topRight: r,
        ),
        Paint()..color = i == selected ? barSelected : bar,
      );
    }

    // Media de 12 meses: línea de 2 px con un anillo del fondo debajo, para
    // que se lea al cruzar las barras.
    final path = Path();
    var started = false;
    for (var i = 0; i < n; i++) {
      final a = averages[i];
      if (a == null) continue;
      final p = Offset(center(i), y(a));
      started ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
      started = true;
    }
    if (started) {
      canvas.drawPath(
        path,
        Paint()
          ..color = surface
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = average
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      final a = averages[selected];
      if (a != null) {
        final p = Offset(center(selected), y(a));
        canvas.drawCircle(p, 5, Paint()..color = surface);
        canvas.drawCircle(p, 3.5, Paint()..color = average);
      }
    }
  }

  @override
  bool shouldRepaint(_EvolutionPainter old) =>
      old.values != values ||
      old.averages != averages ||
      old.selected != selected ||
      old.bar != bar ||
      old.grid != grid;
}
