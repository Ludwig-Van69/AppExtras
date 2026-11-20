/// Medidas del sistema visual «Marea». Se definen una sola vez y todas las
/// piezas las usan desde aquí.
library;

import 'package:flutter/animation.dart';

/// Espaciados, en píxeles lógicos.
abstract final class Space {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Margen lateral de las pantallas.
  static const double gutter = 20;

  /// Hueco entre baldosas del Mosaico.
  static const double tileGap = 6;
}

/// Radios de esquina.
abstract final class Radii {
  static const double tiny = 4;
  static const double tile = 10;
  static const double small = 12;

  /// Botones, campos y selectores (pasada estética «unslop»).
  static const double control = 12;

  /// Tarjetas y paneles.
  static const double medium = 16;
  static const double large = 22;
  static const double sheet = 28;
}

/// Tamaños mínimos.
abstract final class Sizes {
  /// Lo mínimo que mide cualquier cosa que se puede tocar.
  static const double touch = 48;
  static const double presetHeight = 56;
  static const double field = 48;
  static const double navBar = 64;
  static const double tile = 42;
  static const double legendSwatch = 12;
  static const double stateIcon = 40;

  /// Hueco que se deja bajo los botones de horas para el aviso con
  /// «Deshacer».
  static const double undoReserve = 64;
}

/// Duraciones de las animaciones.
abstract final class Motion {
  /// Salida rápida y llegada suave: para lo que entra, sale o cambia en la
  /// pantalla. Nunca se usa una curva que empiece lenta.
  static const Curve easeOut = Cubic(0.23, 1, 0.32, 1);

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 240);
  static const Duration theme = Duration(milliseconds: 350);
  static const Duration tide = Duration(milliseconds: 750);

  /// Botón que se hunde al pulsar y vuelve al soltar.
  static const Duration pressIn = Duration(milliseconds: 90);
  static const Duration pressOut = Duration(milliseconds: 200);

  /// Cambio de la cifra grande, como un marcador.
  static const Duration roll = Duration(milliseconds: 280);

  /// Cambio de la fecha al elegir otro día.
  static const Duration slide = Duration(milliseconds: 260);

  /// Algo que se abre en su sitio (una tarjeta de año).
  static const Duration expand = Duration(milliseconds: 220);

  /// Aparición de algo poco frecuente (los trofeos).
  static const Duration appear = Duration(milliseconds: 250);

  /// Aparición del Mosaico en ola.
  static const Duration mosaicEntrance = Duration(milliseconds: 850);

  /// Un vaivén completo de la ola.
  static const Duration sway = Duration(seconds: 6);

  /// Subida de las burbujas.
  static const Duration bubbles = Duration(milliseconds: 900);

  /// Tiempo que se muestra el aviso con «Deshacer».
  static const Duration undo = Duration(seconds: 5);
}

/// Tamaños de letra.
abstract final class TextSizes {
  static const double hero = 112;
  static const double display = 40;
  static const double title = 22;
  static const double figure = 18;
  static const double body = 16;
  static const double label = 14;
  static const double caption = 12;
}
