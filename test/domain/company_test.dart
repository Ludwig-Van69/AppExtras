import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/company.dart';

/// Datos inventados.
Seniority _s(DateTime start, DateTime today) => Seniority.between(start, today);

Seniority _x(int total, int y, int m, int d) =>
    Seniority(totalDays: total, years: y, months: m, days: d);

void main() {
  group('Seniority (RF-3, RF-4)', () {
    test('cuenta los días naturales sin contar hoy, como la vida laboral', () {
      expect(
        _s(DateTime(2020, 3, 2), DateTime(2026, 11, 25, 18)),
        _x(2459, 6, 8, 23),
      );
    });

    test('alta hoy: cero; alta ayer: un día', () {
      final today = DateTime(2026, 11, 25);
      expect(_s(today, today), _x(0, 0, 0, 0));
      expect(_s(DateTime(2026, 11, 24), today), _x(1, 0, 0, 1));
    });

    test('alta en el futuro (reloj cambiado): cero', () {
      expect(_s(DateTime(2027, 1, 1), DateTime(2026, 11, 25)), _x(0, 0, 0, 0));
    });

    test('meses de calendario: un día antes del mes cumplido, aún no', () {
      expect(_s(DateTime(2021, 6, 10), DateTime(2021, 7, 9)), _x(29, 0, 0, 29));
      expect(_s(DateTime(2021, 6, 10), DateTime(2021, 7, 10)), _x(30, 0, 1, 0));
    });

    test('fin de mes: 31 de enero + 1 mes = último de febrero', () {
      expect(_s(DateTime(2023, 1, 31), DateTime(2023, 2, 28)), _x(28, 0, 1, 0));
      expect(
        _s(DateTime(2024, 1, 31), DateTime(2024, 2, 28)),
        _x(28, 0, 0, 28),
      );
      expect(_s(DateTime(2024, 1, 31), DateTime(2024, 2, 29)), _x(29, 0, 1, 0));
    });

    test('bisiestos: del 29 de febrero al 28 de febrero siguiente', () {
      expect(
        _s(DateTime(2024, 2, 29), DateTime(2025, 2, 28)),
        _x(365, 1, 0, 0),
      );
    });

    test('el cambio de hora no descuadra los días', () {
      expect(_s(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), _x(2, 0, 0, 2));
      expect(
        _s(DateTime(2026, 10, 24), DateTime(2026, 10, 26)),
        _x(2, 0, 0, 2),
      );
    });

    test('la frase omite las partes a cero y usa singulares', () {
      expect(_x(2459, 6, 8, 23).phrase, '6 años, 8 meses y 23 días');
      expect(_x(0, 1, 0, 1).phrase, '1 año y 1 día');
      expect(_x(0, 0, 1, 0).phrase, '1 mes');
      expect(_x(0, 2, 0, 0).phrase, '2 años');
      expect(_x(0, 0, 0, 0).phrase, '0 días');
    });
  });

  group('Company (RF-7, RF-8)', () {
    test('quita los espacios y vacío es sin nombre', () {
      expect(Company(name: '  Talleres Ejemplo ').name, 'Talleres Ejemplo');
      expect(Company(name: '   ').name, isNull);
      expect(Company(name: '').isEmpty, isTrue);
    });

    test('admite 60 caracteres y no 61', () {
      expect(Company(name: 'a' * 60).name, hasLength(60));
      expect(() => Company(name: 'a' * 61), throwsArgumentError);
    });

    test('la fecha se queda sin hora y no vale antes de 1950', () {
      expect(
        Company(start: DateTime(2020, 3, 2, 15, 30)).start,
        DateTime(2020, 3, 2),
      );
      expect(() => Company(start: DateTime(1949, 12, 31)), throwsArgumentError);
    });

    test('se cambia y se borra cada dato por separado', () {
      final c = Company(name: 'Ejemplo', start: DateTime(2020, 3, 2));
      expect(c.withName(null), Company(start: DateTime(2020, 3, 2)));
      expect(c.withStart(null), Company(name: 'Ejemplo'));
      expect(c.withName(null).withStart(null), Company.empty);
    });
  });
}
