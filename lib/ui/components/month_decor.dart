import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/month_theme.dart';
import '../theme/decor_colors.dart';

/// Dibujo pequeño de temporada junto al título del mes (013, RF-9, RF-10).
/// Trazos simples, sin imágenes; el lector de pantalla no lo lee.
class MonthDecor extends StatelessWidget {
  const MonthDecor({super.key, required this.theme});

  final MonthTheme theme;

  static const size = Size(44, 30);

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      key: ValueKey('decor-${theme.name}'),
      size: size,
      painter: _MonthPainter(theme, DecorColors.of(context)),
    ),
  );
}

/// Detalle de la esquina de un día señalado (013, RF-9).
class DayMarkIcon extends StatelessWidget {
  const DayMarkIcon({super.key, required this.mark});

  final DayMark mark;

  static const size = 11.0;

  @override
  Widget build(BuildContext context) => CustomPaint(
    key: ValueKey('marca-${mark.name}'),
    size: const Size.square(size),
    painter: _MarkPainter(mark, DecorColors.of(context)),
  );
}

Paint _fill(Color c) => Paint()..color = c;

Paint _stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

void _flake(Canvas canvas, Offset o, double r, Color c) {
  final p = _stroke(c, 1.4);
  for (var i = 0; i < 4; i++) {
    final a = i * math.pi / 4;
    final d = Offset(math.cos(a) * r, math.sin(a) * r);
    canvas.drawLine(o - d, o + d, p);
  }
}

Path _star(Offset o, double r) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final a = -math.pi / 2 + i * math.pi / 5;
    final rr = i.isOdd ? r * 0.45 : r;
    final pt = o + Offset(math.cos(a) * rr, math.sin(a) * rr);
    i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
  }
  return path..close();
}

void _crown(Canvas canvas, double x, double y, Color c) {
  final path = Path()
    ..moveTo(x, y + 8)
    ..lineTo(x, y)
    ..lineTo(x + 3, y + 4)
    ..lineTo(x + 5, y - 1)
    ..lineTo(x + 7, y + 4)
    ..lineTo(x + 10, y)
    ..lineTo(x + 10, y + 8)
    ..close();
  canvas.drawPath(path, _fill(c));
}

void _burst(Canvas canvas, Offset o, double r, Color c) {
  final p = _stroke(c, 1.6);
  for (var i = 0; i < 8; i++) {
    final a = i * math.pi / 4;
    final d = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(o + d * r * 0.35, o + d * r, p);
  }
  canvas.drawCircle(o, 1.4, _fill(c));
}

class _MonthPainter extends CustomPainter {
  _MonthPainter(this.theme, this.c);

  final MonthTheme theme;
  final DecorColors c;

  @override
  void paint(Canvas canvas, Size size) {
    // Se dibuja en una caja de 44 × 30 y se escala al tamaño real.
    canvas.scale(size.width / 44, size.height / 30);
    switch (theme) {
      case MonthTheme.christmas:
        // Gorro de Papá Noel y copos.
        canvas.drawPath(
          Path()
            ..moveTo(6, 22)
            ..cubicTo(10, 8, 20, 4, 30, 9)
            ..lineTo(33, 22)
            ..close(),
          _fill(c.red),
        );
        final brim = RRect.fromLTRBR(
          4,
          21,
          35,
          26.5,
          const Radius.circular(2.7),
        );
        canvas.drawRRect(brim, _fill(c.paper));
        canvas.drawRRect(brim, _stroke(c.snow, 1.2));
        canvas.drawCircle(const Offset(33, 9.5), 3.2, _fill(c.paper));
        canvas.drawCircle(const Offset(33, 9.5), 3.2, _stroke(c.snow, 1.2));
        _flake(canvas, const Offset(40, 6), 3, c.snow);
        _flake(canvas, const Offset(39.5, 21), 2.2, c.snow);
      case MonthTheme.kings:
        // Tres coronas y la estrella de Oriente.
        _crown(canvas, 2, 13, c.gold);
        _crown(canvas, 14, 9, c.purple);
        _crown(canvas, 26, 13, c.red);
        canvas.drawLine(
          const Offset(37.5, 8.5),
          const Offset(31, 4),
          _stroke(c.gold.withValues(alpha: 0.7), 1.2),
        );
        canvas.drawPath(_star(const Offset(40, 6), 4.2), _fill(c.gold));
      case MonthTheme.carnival:
        // Plumas y confeti, al estilo de Río.
        canvas.drawPath(
          Path()
            ..moveTo(10, 26)
            ..cubicTo(4, 18, 4, 8, 9, 2)
            ..cubicTo(12, 10, 12, 18, 10, 26)
            ..close(),
          _fill(c.pink),
        );
        canvas.drawPath(
          Path()
            ..moveTo(14, 26)
            ..cubicTo(14, 16, 18, 7, 24, 3)
            ..cubicTo(23, 12, 20, 19, 14, 26)
            ..close(),
          _fill(c.orange),
        );
        canvas.drawPath(
          Path()
            ..moveTo(18, 27)
            ..cubicTo(21, 20, 27, 15, 33, 14)
            ..cubicTo(29, 20, 24, 24, 18, 27)
            ..close(),
          _fill(c.green),
        );
        canvas.drawCircle(const Offset(35, 5), 1.8, _fill(c.blue));
        canvas.drawCircle(const Offset(40, 12), 1.6, _fill(c.pink));
        canvas.drawCircle(const Offset(30, 24), 1.4, _fill(c.purple));
        canvas.save();
        canvas.translate(37.5, 21.5);
        canvas.rotate(0.44);
        canvas.drawRect(const Rect.fromLTWH(-1.5, -1.5, 3, 3), _fill(c.gold));
        canvas.restore();
      case MonthTheme.halloween:
        // Calabaza y murciélago.
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(16, 18), width: 22, height: 18),
          _fill(c.orange),
        );
        final ribs = _stroke(c.paper.withValues(alpha: 0.5), 1);
        canvas.drawLine(const Offset(16, 9.5), const Offset(16, 18), ribs);
        canvas.drawPath(
          Path()
            ..moveTo(10, 12)
            ..cubicTo(8, 16, 8, 21, 10, 25)
            ..moveTo(22, 12)
            ..cubicTo(24, 16, 24, 21, 22, 25),
          ribs,
        );
        canvas.drawPath(
          Path()
            ..moveTo(16, 9.5)
            ..cubicTo(16, 6, 18, 4, 20, 4),
          _stroke(c.green, 2),
        );
        canvas.drawPath(
          Path()
            ..moveTo(31, 8)
            ..cubicTo(33, 5, 35, 5, 36, 7)
            ..cubicTo(37, 5, 39, 5, 41, 8)
            ..cubicTo(39, 8, 38, 9, 36, 11)
            ..cubicTo(34, 9, 33, 8, 31, 8)
            ..close(),
          _fill(c.ink),
        );
      case MonthTheme.sanJuan:
        // Hoguera con chispas.
        final wood = _stroke(c.ink, 2.4);
        canvas.drawLine(const Offset(12, 28), const Offset(30, 22), wood);
        canvas.drawLine(const Offset(12, 22), const Offset(30, 28), wood);
        canvas.drawPath(
          Path()
            ..moveTo(21, 24)
            ..cubicTo(12, 21, 13, 12, 18, 6)
            ..cubicTo(18, 11, 20, 12, 22, 9)
            ..cubicTo(23, 13, 27, 14, 27, 18)
            ..cubicTo(27, 21, 25, 23, 21, 24)
            ..close(),
          _fill(c.orange),
        );
        canvas.drawPath(
          Path()
            ..moveTo(21, 23)
            ..cubicTo(17, 21, 18, 17, 20, 14)
            ..cubicTo(21, 17, 23, 17, 24, 19)
            ..cubicTo(24, 21, 23, 22, 21, 23)
            ..close(),
          _fill(c.gold),
        );
        canvas.drawCircle(const Offset(33, 9), 1.2, _fill(c.orange));
        canvas.drawCircle(const Offset(36, 15), 1, _fill(c.gold));
        canvas.drawCircle(const Offset(9, 10), 1, _fill(c.orange));
      case MonthTheme.semanaGrande:
        // Fuegos artificiales.
        _burst(canvas, const Offset(13, 12), 9, c.pink);
        _burst(canvas, const Offset(32, 9), 7, c.blue);
        _burst(canvas, const Offset(29, 23), 5, c.gold);
      case MonthTheme.spring:
        // Flor.
        canvas.drawPath(
          Path()
            ..moveTo(14, 28)
            ..cubicTo(14, 22, 15, 18, 15, 15),
          _stroke(c.green, 1.6),
        );
        canvas.drawPath(
          Path()
            ..moveTo(14.5, 23)
            ..cubicTo(10, 22, 8, 19, 8, 17)
            ..cubicTo(11, 17, 14, 19, 14.5, 23)
            ..close(),
          _fill(c.green),
        );
        for (var i = 0; i < 5; i++) {
          canvas.save();
          canvas.translate(15, 12);
          canvas.rotate(i * 2 * math.pi / 5);
          canvas.drawOval(
            Rect.fromCenter(
              center: const Offset(0, -3.5),
              width: 5.6,
              height: 8.6,
            ),
            _fill(c.pink),
          );
          canvas.restore();
        }
        canvas.drawCircle(const Offset(15, 12), 2.4, _fill(c.gold));
        canvas.drawCircle(
          const Offset(32, 18),
          2,
          _fill(c.pink.withValues(alpha: 0.6)),
        );
        canvas.drawCircle(
          const Offset(38, 10),
          1.5,
          _fill(c.pink.withValues(alpha: 0.45)),
        );
      case MonthTheme.summer:
        // Sol y una ola.
        canvas.drawCircle(const Offset(16, 14), 6.5, _fill(c.gold));
        final ray = _stroke(c.gold, 1.8);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          final d = Offset(math.cos(a), math.sin(a));
          canvas.drawLine(
            const Offset(16, 14) + d * 9.5,
            const Offset(16, 14) + d * 12.5,
            ray,
          );
        }
        canvas.drawPath(
          Path()
            ..moveTo(30, 22)
            ..cubicTo(33, 19, 36, 19, 39, 22)
            ..cubicTo(41, 24, 43, 24, 44, 23),
          _stroke(c.blue, 1.6),
        );
      case MonthTheme.autumn:
        // Dos hojas.
        canvas.drawPath(
          Path()
            ..moveTo(8, 24)
            ..cubicTo(6, 14, 14, 5, 26, 4)
            ..cubicTo(27, 15, 20, 24, 8, 24)
            ..close(),
          _fill(c.orange),
        );
        canvas.drawLine(
          const Offset(8, 24),
          const Offset(22, 9),
          _stroke(c.paper.withValues(alpha: 0.6), 1.1),
        );
        canvas.drawPath(
          Path()
            ..moveTo(30, 26)
            ..cubicTo(29, 20, 33, 15, 40, 15)
            ..cubicTo(40, 21, 36, 26, 30, 26)
            ..close(),
          _fill(c.red.withValues(alpha: 0.8)),
        );
      case MonthTheme.winter:
        _flake(canvas, const Offset(14, 14), 8, c.snow);
        _flake(canvas, const Offset(32, 8), 4.5, c.snow);
        _flake(canvas, const Offset(36, 22), 3.2, c.snow);
    }
  }

  @override
  bool shouldRepaint(_MonthPainter old) => old.theme != theme || old.c != c;
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.mark, this.c);

  final DayMark mark;
  final DecorColors c;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 12, size.height / 12);
    switch (mark) {
      case DayMark.star:
        canvas.drawPath(_star(const Offset(6, 6), 5.2), _fill(c.gold));
      case DayMark.confetti:
        canvas.drawCircle(const Offset(3, 3), 1.5, _fill(c.pink));
        canvas.drawCircle(const Offset(9, 5), 1.4, _fill(c.blue));
        canvas.drawCircle(const Offset(5, 9), 1.4, _fill(c.gold));
      case DayMark.pumpkin:
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(6, 7.2), width: 10, height: 8),
          _fill(c.orange),
        );
        canvas.drawLine(
          const Offset(6, 3.5),
          const Offset(6, 1.5),
          _stroke(c.green, 1.5),
        );
      case DayMark.flame:
        canvas.drawPath(
          Path()
            ..moveTo(6, 11.5)
            ..cubicTo(1.5, 10, 2, 5, 5, 1)
            ..cubicTo(5, 4, 7, 4, 7.5, 3)
            ..cubicTo(9, 5, 10.5, 7, 9.6, 9)
            ..cubicTo(9, 10.6, 7.6, 11.4, 6, 11.5)
            ..close(),
          _fill(c.orange),
        );
      case DayMark.spark:
        _burst(canvas, const Offset(6, 6), 5.5, c.pink);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.mark != mark || old.c != c;
}

/// El dibujo del mes, o nulo si el usuario apagó los calendarios temáticos
/// (013, RF-11).
Widget? monthDecorOf(BuildContext context, int year, int month) =>
    CalendarDecorScope.enabled(context)
    ? MonthDecor(theme: monthTheme(year, month))
    : null;

/// Los detalles de los días, o nulo si están apagados (013, RF-11).
DayMark? Function(DateTime)? dayMarksOf(BuildContext context) =>
    CalendarDecorScope.enabled(context) ? dayMark : null;

/// Título del mes con su dibujo al lado; el texto se encoge si no cabe.
class DecoratedMonthTitle extends StatelessWidget {
  const DecoratedMonthTitle({
    super.key,
    required this.year,
    required this.month,
    required this.title,
  });

  final int year;
  final int month;
  final Widget title;

  @override
  Widget build(BuildContext context) {
    final decor = monthDecorOf(context, year, month);
    if (decor == null) return title;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: title),
        const SizedBox(width: 6),
        decor,
      ],
    );
  }
}
