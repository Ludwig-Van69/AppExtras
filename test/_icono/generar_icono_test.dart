// Genera el icono de la app («Extras»: reloj de agua con burbujas y un «+»).
//
//   flutter test test/_icono/generar_icono_test.dart --dart-define=ICONO=true
//
// Escribe los PNG de Android (icono adaptable y el clásico) en
// android/app/src/main/res. Sin la variable no hace nada.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _run = bool.fromEnvironment('ICONO');

const _background = Color(0xFFE6F4F3);
const _face = Color(0xFFFFFFFF);
const _ring = Color(0xFF0B6E78);
const _water = Color(0xFF62D8D1);
const _deep = Color(0x590B6E78); // 35 %
const _hands = Color(0xFF0F2A30);
const _centre = Color(0xFFB23C16);
const _plus = Color(0xFFFF7A4D);

/// Una ola desde [x0] hasta [x1] a la altura [y], con crestas de ±6 cada 15.
Path _wave(double x0, double x1, double y, double bottom) {
  final p = Path()..moveTo(x0, y);
  var up = true;
  for (var x = x0; x < x1; x += 15) {
    p.quadraticBezierTo(x + 7.5, up ? y - 6 : y + 6, x + 15, y);
    up = !up;
  }
  return p
    ..lineTo(x1, bottom)
    ..lineTo(x0, bottom)
    ..close();
}

/// Dibuja el primer plano en un lienzo de 108 × 108 (unidades dp del icono
/// adaptable de Android; lo visible es el círculo central de 66).
void _foreground(Canvas c) {
  const cx = 52.0, cy = 56.0, r = 21.0;
  c.drawCircle(const Offset(cx, cy), r, Paint()..color = _face);
  c.save();
  c.clipPath(
    Path()..addOval(Rect.fromCircle(center: const Offset(cx, cy), radius: 19)),
  );
  c.drawPath(_wave(22, 84, 58, 90), Paint()..color = _water);
  c.drawPath(_wave(22, 84, 66, 90), Paint()..color = _deep);
  final bubble = Paint()..color = _face;
  c.drawCircle(const Offset(43, 69), 2.4, bubble);
  c.drawCircle(const Offset(47, 63), 1.7, bubble);
  c.drawCircle(const Offset(62, 67), 2, bubble);
  c.restore();
  // Aro abierto arriba a la derecha (de la 1 y media a las 12).
  c.drawArc(
    Rect.fromCircle(center: const Offset(cx, cy), radius: r),
    -math.pi / 4,
    math.pi * 7 / 4,
    false,
    Paint()
      ..color = _ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round,
  );
  final plus = Paint()
    ..color = _plus
    ..strokeWidth = 5
    ..strokeCap = StrokeCap.round;
  c.drawLine(const Offset(71, 28), const Offset(71, 38), plus);
  c.drawLine(const Offset(66, 33), const Offset(76, 33), plus);
  final hand = Paint()
    ..color = _hands
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.round;
  c.drawLine(const Offset(cx, cy), const Offset(cx, 42), hand);
  c.drawLine(const Offset(cx, cy), const Offset(62, cy), hand);
  c.drawCircle(const Offset(cx, cy), 3.5, Paint()..color = _centre);
}

Future<void> _png(
  String path,
  int px,
  void Function(Canvas c, double size) paint,
) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  paint(canvas, px.toDouble());
  final image = await rec.endRecording().toImage(px, px);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  test('genera el icono', skip: !_run, () async {
    const res = 'android/app/src/main/res';
    const densities = {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    };
    for (final MapEntry(key: d, value: k) in densities.entries) {
      // Primer plano del icono adaptable: 108 dp.
      await _png(
        '$res/mipmap-$d/ic_launcher_foreground.png',
        (108 * k).round(),
        (c, s) {
          c.scale(s / 108);
          _foreground(c);
        },
      );
      // Icono clásico (Android 7 y anteriores): 48 dp, redondo, con el
      // centro de 72 dp del adaptable.
      await _png('$res/mipmap-$d/ic_launcher.png', (48 * k).round(), (c, s) {
        c.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, s, s)));
        c.drawColor(_background, BlendMode.src);
        c.scale(s / 72);
        c.translate(-18, -18);
        _foreground(c);
      });
    }
    // Vista previa grande para mirarla en el ordenador.
    await _png('build/icono-extras.png', 432, (c, s) {
      c.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, s, s)));
      c.drawColor(_background, BlendMode.src);
      c.scale(s / 72);
      c.translate(-18, -18);
      _foreground(c);
    });
  });
}
