import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/month_theme.dart';

void main() {
  test('Pascua de varios años (fechas conocidas)', () {
    expect(easterSunday(2026), DateTime(2026, 4, 5));
    expect(easterSunday(2027), DateTime(2027, 3, 28));
    expect(easterSunday(2028), DateTime(2028, 4, 16));
    expect(easterSunday(2030), DateTime(2030, 4, 21));
    expect(easterSunday(2038), DateTime(2038, 4, 25));
  });

  test('martes de Carnaval: 47 días antes de Pascua', () {
    expect(carnivalTuesday(2027), DateTime(2027, 2, 9));
    expect(carnivalTuesday(2030), DateTime(2030, 3, 5));
  });

  test('tema de cada mes (013, RF-10)', () {
    expect(monthTheme(2026, 12), MonthTheme.christmas);
    expect(monthTheme(2027, 1), MonthTheme.kings);
    expect(monthTheme(2027, 2), MonthTheme.carnival);
    expect(monthTheme(2026, 10), MonthTheme.halloween);
    expect(monthTheme(2027, 6), MonthTheme.sanJuan);
    expect(monthTheme(2027, 7), MonthTheme.semanaGrande);
    expect(monthTheme(2027, 4), MonthTheme.spring);
    expect(monthTheme(2027, 8), MonthTheme.summer);
    expect(monthTheme(2026, 11), MonthTheme.autumn);
    expect(monthTheme(2026, 9), MonthTheme.autumn);
    // 2030: Carnaval en marzo; febrero es invierno y marzo, Carnaval.
    expect(monthTheme(2030, 2), MonthTheme.winter);
    expect(monthTheme(2030, 3), MonthTheme.carnival);
  });

  test('días señalados', () {
    expect(dayMark(DateTime(2026, 12, 24)), DayMark.star);
    expect(dayMark(DateTime(2026, 12, 25)), DayMark.star);
    expect(dayMark(DateTime(2026, 12, 31)), DayMark.star);
    expect(dayMark(DateTime(2026, 12, 26)), isNull);
    expect(dayMark(DateTime(2027, 1, 5)), DayMark.star);
    expect(dayMark(DateTime(2027, 1, 6)), DayMark.star);
    expect(dayMark(DateTime(2027, 1, 7)), isNull);
    expect(dayMark(DateTime(2026, 10, 31)), DayMark.pumpkin);
    expect(dayMark(DateTime(2027, 6, 23)), DayMark.flame);
    expect(dayMark(DateTime(2027, 6, 24)), DayMark.flame);
    expect(dayMark(DateTime(2027, 7, 25)), DayMark.spark);
    expect(dayMark(DateTime(2027, 4, 10)), isNull);
    // Carnaval 2027: de sábado 6 a martes 9 de febrero.
    expect(dayMark(DateTime(2027, 2, 5)), isNull);
    for (var d = 6; d <= 9; d++) {
      expect(dayMark(DateTime(2027, 2, d)), DayMark.confetti);
    }
    expect(dayMark(DateTime(2027, 2, 10)), isNull);
  });
}
