import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/holidays.dart';

void main() {
  test('Domingo de Pascua de varios años', () {
    expect(easterSunday(2024), DateTime(2024, 3, 31));
    expect(easterSunday(2025), DateTime(2025, 4, 20));
    expect(easterSunday(2026), DateTime(2026, 4, 5));
    expect(easterSunday(2027), DateTime(2027, 3, 28));
  });

  group('calendario de serie', () {
    final cal = HolidayCalendar();

    test('fechas fijas', () {
      for (final d in [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 6),
        DateTime(2026, 5, 1),
        DateTime(2026, 8, 15),
        DateTime(2026, 10, 12),
        DateTime(2026, 11, 1),
        DateTime(2026, 12, 6),
        DateTime(2026, 12, 8),
        DateTime(2026, 12, 25),
      ]) {
        expect(cal.holidayOn(d), isNotNull, reason: '$d');
      }
    });

    test('Semana Santa se calcula cada año', () {
      expect(cal.holidayOn(DateTime(2026, 4, 3))!.name, 'Viernes Santo');
      expect(cal.holidayOn(DateTime(2027, 3, 26))!.name, 'Viernes Santo');
      expect(cal.holidayOn(DateTime(2026, 4, 6)), isNull); // lunes de Pascua
    });

    test('un día normal no es festivo y la hora del reloj no importa', () {
      expect(cal.holidayOn(DateTime(2026, 11, 3)), isNull);
      expect(cal.holidayOn(DateTime(2026, 1, 1, 23, 59))!.name, 'Año Nuevo');
    });

    test('traslados de un solo año', () {
      expect(
        cal.holidayOn(DateTime(2026, 12, 7))!.name,
        startsWith('Constitución'),
      );
      expect(cal.holidayOn(DateTime(2027, 12, 7)), isNull);
    });

    test('los ids no se repiten', () {
      final ids = builtInHolidays.map((h) => h.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('cambios del usuario', () {
    test('un festivo de serie desactivado deja de serlo', () {
      final cal = HolidayCalendar(disabled: {'nat-reyes'});
      expect(cal.holidayOn(DateTime(2026, 1, 6)), isNull);
      expect(cal.holidayOn(DateTime(2026, 1, 1)), isNotNull);
    });

    test('un festivo propio de un solo año', () {
      final cal = HolidayCalendar(
        custom: [Holiday.once('c1', 'Local', DateTime(2026, 6, 29))],
      );
      expect(cal.holidayOn(DateTime(2026, 6, 29))!.name, 'Local');
      expect(cal.holidayOn(DateTime(2027, 6, 29)), isNull);
    });

    test('un festivo propio que se repite cada año', () {
      final cal = HolidayCalendar(
        custom: [const Holiday.fixed('c2', 'Mío', HolidayGroup.custom, 6, 29)],
      );
      expect(cal.holidayOn(DateTime(2026, 6, 29)), isNotNull);
      expect(cal.holidayOn(DateTime(2031, 6, 29)), isNotNull);
    });

    test('un 29 de febrero solo existe los años bisiestos', () {
      const h = Holiday.fixed('c3', 'Bisiesto', HolidayGroup.custom, 2, 29);
      expect(h.dateIn(2028), DateTime(2028, 2, 29));
      expect(h.dateIn(2027), isNull);
    });
  });

  group('tipo propuesto', () {
    final cal = HolidayCalendar();

    test('fin de semana, festivo entre semana y día normal', () {
      expect(suggestedKindFor(DateTime(2026, 11, 7)), DayKind.festive);
      expect(suggestedKindFor(DateTime(2026, 1, 1)), DayKind.normal);
      expect(
        suggestedKindFor(DateTime(2026, 1, 1), calendar: cal),
        DayKind.festive,
      );
      expect(
        suggestedKindFor(DateTime(2026, 11, 3), calendar: cal),
        DayKind.normal,
      );
    });
  });
}
