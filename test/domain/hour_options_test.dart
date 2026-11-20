import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/hour_options.dart';

void main() {
  test('nueve botones de 1 a 5 h en medias horas (RF-6)', () {
    expect(presetMinutes, [60, 90, 120, 150, 180, 210, 240, 270, 300]);
  });

  test('«Otra» ofrece de 0,5 a 24 h en medias horas (RF-8)', () {
    expect(otherMinutes.first, 30);
    expect(otherMinutes.last, 1440);
    expect(otherMinutes.length, 48);
    expect(otherMinutes.every((m) => m % 30 == 0), isTrue);
  });

  test('solo se aceptan medias horas entre 0,5 y 24 h', () {
    expect(isValidChoice(30), isTrue);
    expect(isValidChoice(1440), isTrue);
    expect(isValidChoice(0), isFalse);
    expect(isValidChoice(45), isFalse);
    expect(isValidChoice(1470), isFalse);
  });

  test('qué botón queda marcado (RF-9)', () {
    expect(selectedPreset(150), 150);
    expect(selectedPreset(360), isNull); // se marca «Otra»
    expect(selectedPreset(0), isNull); // sin horas, nada marcado
    expect(isOtherSelected(360), isTrue);
    expect(isOtherSelected(150), isFalse);
    expect(isOtherSelected(0), isFalse);
  });
}
