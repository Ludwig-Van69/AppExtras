import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/device_identity.dart';

void main() {
  group('código del móvil (RF-1)', () {
    test('6 letras minúsculas o cifras, distinto cada vez', () {
      final a = newDeviceId(Random(1));
      final b = newDeviceId(Random(2));
      expect(isValidDeviceId(a), isTrue);
      expect(isValidDeviceId(b), isTrue);
      expect(a, isNot(b));
    });

    test('rechaza códigos mal formados', () {
      for (final bad in ['', 'abc', 'ABCDEF', 'abc_ef', 'abcdefg', 'ab de1']) {
        expect(isValidDeviceId(bad), isFalse, reason: bad);
      }
    });
  });

  group('nombre de serie (RF-1)', () {
    test('es el modelo', () {
      expect(defaultDeviceName('moto g75 5G'), 'moto g75 5G');
    });

    test('quita lo que no vale y recorta a 24', () {
      expect(defaultDeviceName('Pixel_7 (Pro)'), 'Pixel 7 Pro');
      expect(
        defaultDeviceName('Un modelo con un nombre larguísimo de verdad'),
        'Un modelo con un nombre',
      );
    });

    test('sin modelo, o sin nada aprovechable, «Móvil»', () {
      expect(defaultDeviceName(null), 'Móvil');
      expect(defaultDeviceName('___'), 'Móvil');
    });
  });

  group('nombre elegido (RF-3)', () {
    test('acepta letras con tilde, números, espacios y guiones', () {
      expect(
        cleanDeviceName('  Móvil  del   trabajo-2 '),
        'Móvil del trabajo-2',
      );
      expect(cleanDeviceName('Ñandú 1'), 'Ñandú 1');
    });

    test('rechaza vacío, más de 24 o caracteres raros', () {
      for (final bad in [
        '',
        '   ',
        'x' * 25,
        'móvil_1',
        'a/b',
        'a.b',
        'móvil @ casa',
      ]) {
        expect(cleanDeviceName(bad), isNull, reason: bad);
      }
      expect(cleanDeviceName('x' * 24), 'x' * 24);
    });
  });
}
