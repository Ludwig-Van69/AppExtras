import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/workday.dart';

void main() {
  test('de lunes a jueves 8 h, viernes 7 h y fin de semana nada (020)', () {
    // Del lunes 16 al domingo 22 de noviembre de 2026.
    final week = [for (var d = 16; d <= 22; d++) DateTime(2026, 11, d)];
    expect(week.map(workdayMinutes), [480, 480, 480, 480, 420, 0, 0]);
    expect(week.map(workdayMinutes).reduce((a, b) => a + b), 39 * 60);
  });
}
