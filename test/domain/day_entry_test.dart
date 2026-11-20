import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';

void main() {
  group('tipo propuesto (RF-11)', () {
    test('sábado y domingo se proponen como festivos', () {
      expect(suggestedKindFor(DateTime(2026, 11, 7)), DayKind.festive);
      expect(suggestedKindFor(DateTime(2026, 11, 8)), DayKind.festive);
    });

    test('de lunes a viernes se proponen como normales', () {
      for (var d = 2; d <= 6; d++) {
        expect(suggestedKindFor(DateTime(2026, 11, d)), DayKind.normal);
      }
    });
  });

  group('día apuntado (RF-27)', () {
    test('guarda solo la fecha, sin la hora del reloj', () {
      final e = DayEntry(
        date: DateTime(2026, 11, 6, 18, 30),
        minutes: 150,
        kind: DayKind.normal,
      );
      expect(e.date, DateTime(2026, 11, 6));
    });

    test('rechaza minutos fuera de 1 a 1440', () {
      DayEntry make(int m) => DayEntry(
        date: DateTime(2026, 1, 1),
        minutes: m,
        kind: DayKind.normal,
      );
      expect(() => make(0), throwsArgumentError);
      expect(() => make(-30), throwsArgumentError);
      expect(() => make(1441), throwsArgumentError);
      expect(make(1440).minutes, 1440);
    });

    test('la clave de fecha tiene formato AAAA-MM-DD', () {
      expect(dateKey(DateTime(2026, 3, 5)), '2026-03-05');
      expect(parseDateKey('2026-03-05'), DateTime(2026, 3, 5));
    });

    test('una clave de fecha mal formada da error', () {
      expect(() => parseDateKey('2026-13-40'), throwsFormatException);
      expect(() => parseDateKey('ayer'), throwsFormatException);
    });

    test('dos días iguales son iguales', () {
      final a = DayEntry(
        date: DateTime(2026, 1, 1),
        minutes: 60,
        kind: DayKind.festive,
        reason: 'Taller',
      );
      final b = DayEntry(
        date: DateTime(2026, 1, 1),
        minutes: 60,
        kind: DayKind.festive,
        reason: 'Taller',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('motivo (RF-14, RF-17)', () {
    test('quita los espacios de sobra al principio y al final', () {
      expect(normalizeReason('  Taller Norte  '), 'Taller Norte');
    });

    test('un motivo vacío o solo con espacios queda sin motivo', () {
      expect(normalizeReason(''), isNull);
      expect(normalizeReason('   '), isNull);
      expect(normalizeReason(null), isNull);
    });

    test('se corta a 60 caracteres', () {
      final long = 'a' * 75;
      expect(normalizeReason(long)!.length, maxReasonLength);
      expect(maxReasonLength, 60);
    });

    test('el día guarda el motivo ya limpio', () {
      final e = DayEntry(
        date: DateTime(2026, 1, 1),
        minutes: 60,
        kind: DayKind.normal,
        reason: '  ',
      );
      expect(e.reason, isNull);
    });
  });
}
