// Genera el icono de la app a partir del dibujo icono_fuente.png (reloj con
// olas y un «+», sobre un cuadrado redondeado con margen transparente).
//
//   flutter test test/_icono/generar_icono_test.dart --dart-define=ICONO=true
//
// Escribe los PNG de Android (icono adaptable y el clásico) en
// android/app/src/main/res. Sin la variable no hace nada.
//
// Cómo se adapta el dibujo: se recorta el cuadrado (sin el margen ni los
// restos de color del borde), se rellenan sus esquinas redondeadas con el
// color de al lado y se coloca en la zona visible del icono adaptable
// (los 72 dp centrales de 108). El móvil pone luego su propia forma.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _run = bool.fromEnvironment('ICONO');
const _fuente = 'test/_icono/icono_fuente.png';

/// Píxeles que se quitan de cada borde del cuadrado, para no arrastrar el
/// borde suavizado ni los restos de color que trae el dibujo.
const _recorte = 14;

/// Tamaño (en dp, sobre 108) que ocupa el cuadrado dentro del icono adaptable.
/// Menos que la zona visible (72) para que el «+» quepa en los móviles que
/// recortan en redondo; alrededor se alarga el color del borde.
const _lado = 62.0;

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

/// Recorta el cuadrado del dibujo y rellena sus esquinas transparentes con el
/// primer color opaco que hay yendo hacia el centro.
Future<ui.Image> _cuadrado() async {
  final src = await _decode(File(_fuente).readAsBytesSync());
  final w = src.width, h = src.height;
  final px = (await src.toByteData())!.buffer.asUint8List();
  int a(int x, int y) => px[(y * w + x) * 4 + 3];

  // Bordes del cuadrado: filas y columnas con mucho color opaco.
  bool col(int x) =>
      List.generate(h, (y) => a(x, y)).where((v) => v > 200).length > h / 4;
  bool fila(int y) =>
      List.generate(w, (x) => a(x, y)).where((v) => v > 200).length > w / 4;
  var x0 = 0, x1 = w - 1, y0 = 0, y1 = h - 1;
  while (!col(x0)) {
    x0++;
  }
  while (!col(x1)) {
    x1--;
  }
  while (!fila(y0)) {
    y0++;
  }
  while (!fila(y1)) {
    y1--;
  }
  x0 += _recorte;
  y0 += _recorte;
  x1 -= _recorte;
  y1 -= _recorte;
  final lado = (x1 - x0 < y1 - y0 ? x1 - x0 : y1 - y0) + 1;
  final cx = x0 + lado / 2, cy = y0 + lado / 2;

  final out = Uint8List(lado * lado * 4);
  for (var y = 0; y < lado; y++) {
    for (var x = 0; x < lado; x++) {
      var sx = (x0 + x).toDouble(), sy = (y0 + y).toDouble();
      // Camina hacia el centro hasta dar con un píxel opaco.
      final dx = cx - sx, dy = cy - sy;
      final pasos = (dx.abs() > dy.abs() ? dx.abs() : dy.abs()).ceil();
      for (var i = 0; i < pasos && a(sx.round(), sy.round()) < 250; i++) {
        sx += dx / pasos;
        sy += dy / pasos;
      }
      final s = (sy.round() * w + sx.round()) * 4, d = (y * lado + x) * 4;
      out[d] = px[s];
      out[d + 1] = px[s + 1];
      out[d + 2] = px[s + 2];
      out[d + 3] = 255;
    }
  }
  final hecho = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    out,
    lado,
    lado,
    ui.PixelFormat.rgba8888,
    hecho.complete,
  );
  return hecho.future;
}

/// Pinta el dibujo en un lienzo de 108 × 108 (dp del icono adaptable). Fuera
/// del cuadrado se alarga el color de su borde, para que no quede hueco.
void _foreground(Canvas c, ui.Image img) {
  const o = (108 - _lado) / 2;
  final k = _lado / img.width;
  final m = Matrix4.identity()
    ..translateByDouble(o, o, 0, 1)
    ..scaleByDouble(k, k, 1, 1);
  c.drawRect(
    const Rect.fromLTWH(0, 0, 108, 108),
    Paint()
      ..filterQuality = FilterQuality.high
      ..shader = ImageShader(
        img,
        TileMode.clamp,
        TileMode.clamp,
        m.storage,
        filterQuality: FilterQuality.high,
      ),
  );
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

/// Lo que se ve en el móvil: los 72 dp centrales, recortados con [forma].
void _visible(Canvas c, double s, ui.Image img, Path Function(double) forma) {
  c.clipPath(forma(s));
  c.scale(s / 72);
  c.translate(-18, -18);
  _foreground(c, img);
}

Path _redondo(double s) => Path()..addOval(Rect.fromLTWH(0, 0, s, s));
Path _squircle(double s) => Path()
  ..addRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s / 4)),
  );

void main() {
  test('genera el icono', skip: !_run, () async {
    final img = await _cuadrado();
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
          _foreground(c, img);
        },
      );
      // Icono clásico (Android 7 y anteriores): 48 dp, redondo.
      await _png(
        '$res/mipmap-$d/ic_launcher.png',
        (48 * k).round(),
        (c, s) => _visible(c, s, img, _redondo),
      );
    }
    // Vistas previas grandes para mirarlas en el ordenador.
    await _png(
      'build/icono-redondo.png',
      432,
      (c, s) => _visible(c, s, img, _redondo),
    );
    await _png(
      'build/icono-cuadrado.png',
      432,
      (c, s) => _visible(c, s, img, _squircle),
    );
  });
}
