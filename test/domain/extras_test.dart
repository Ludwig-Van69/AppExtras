import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/extras.dart';

/// Datos inventados.
ExtraItem item(
  ExtraType type,
  int cents, {
  ExtraStatus status = ExtraStatus.pending,
  DateTime? date,
  int? id,
}) => ExtraItem(
  id: id,
  type: type,
  date: date ?? DateTime(2026, 11, 2),
  cents: cents,
  concept: type == ExtraType.fine ? 'Multa aparcamiento' : 'Dieta viaje',
  status: status,
  closedOn: status == ExtraStatus.closed ? DateTime(2026, 11, 10) : null,
);

void main() {
  final today = DateTime(2026, 11, 16, 9);

  group('validación (RF-3)', () {
    ExtraProblem? check({
      int? cents = 5000,
      String concept = 'Dieta viaje',
      DateTime? date,
    }) => validateExtra(
      cents: cents,
      concept: concept,
      date: date ?? DateTime(2026, 11, 2),
      today: today,
    );

    test('un apunte correcto no tiene problemas', () {
      expect(check(), isNull);
      expect(check(cents: 1), isNull);
      expect(check(cents: maxExtraCents), isNull);
      expect(check(date: DateTime(2020)), isNull);
      expect(check(date: today), isNull);
    });

    test('importe fuera de rango o mal escrito (nulo)', () {
      expect(check(cents: 0), ExtraProblem.amount);
      expect(check(cents: maxExtraCents + 1), ExtraProblem.amount);
      expect(check(cents: null), ExtraProblem.amount);
    });

    test('concepto vacío o demasiado largo', () {
      expect(check(concept: '   '), ExtraProblem.concept);
      expect(check(concept: 'x' * 61), ExtraProblem.concept);
      expect(check(concept: 'x' * 60), isNull);
    });

    test('fecha antes de 2020 o en el futuro', () {
      expect(check(date: DateTime(2019, 12, 31)), ExtraProblem.date);
      expect(check(date: DateTime(2026, 11, 17)), ExtraProblem.date);
    });

    test('cada problema tiene su mensaje', () {
      for (final p in ExtraProblem.values) {
        expect(p.message, isNotEmpty);
      }
    });
  });

  group('apunte', () {
    test('el concepto se guarda limpio y la fecha sin hora', () {
      final e = ExtraItem(
        type: ExtraType.bonus,
        date: DateTime(2026, 11, 2, 15, 30),
        cents: 5000,
        concept: '  Plus nocturno  ',
      );
      expect(e.concept, 'Plus nocturno');
      expect(e.date, DateTime(2026, 11, 2));
      expect(e.status, ExtraStatus.pending);
    });

    test('las reglas imposibles se rechazan', () {
      expect(() => item(ExtraType.fine, 0), throwsArgumentError);
      expect(
        () => item(ExtraType.fine, maxExtraCents + 1),
        throwsArgumentError,
      );
      expect(
        () => ExtraItem(
          type: ExtraType.fine,
          date: DateTime(2026, 11, 2),
          cents: 100,
          concept: '',
        ),
        throwsArgumentError,
      );
      // Cerrada sin fecha de cierre, o con fecha sin estar cerrada.
      expect(
        () => ExtraItem(
          type: ExtraType.fine,
          date: DateTime(2026, 11, 2),
          cents: 100,
          concept: 'Multa',
          status: ExtraStatus.closed,
        ),
        throwsArgumentError,
      );
      expect(
        () => ExtraItem(
          type: ExtraType.fine,
          date: DateTime(2026, 11, 2),
          cents: 100,
          concept: 'Multa',
          closedOn: DateTime(2026, 11, 3),
        ),
        throwsArgumentError,
      );
    });

    test('las multas restan y los extras suman', () {
      expect(item(ExtraType.fine, 10000).signedCents, -10000);
      expect(item(ExtraType.bonus, 5000).signedCents, 5000);
    });

    test('cambiar el estado pone o quita la fecha de cierre', () {
      final e = item(ExtraType.fine, 100, id: 3);
      final closed = e.withStatus(
        ExtraStatus.closed,
        on: DateTime(2026, 11, 9),
      );
      expect(closed.closedOn, DateTime(2026, 11, 9));
      expect(closed.id, 3);
      expect(closed.withStatus(ExtraStatus.cancelled).closedOn, isNull);
      expect(closed.withStatus(ExtraStatus.pending).closedOn, isNull);
    });
  });

  group('totales (RF-7, RF-9)', () {
    test('570 + 50 − 100 = 520; solo cuentan las pendientes', () {
      final items = [
        item(ExtraType.bonus, 5000),
        item(ExtraType.fine, 10000),
        item(ExtraType.fine, 9900, status: ExtraStatus.cancelled),
        item(ExtraType.bonus, 2000, status: ExtraStatus.closed),
      ];
      final t = ExtrasTotals.of(items);
      expect(t.pendingBonusCents, 5000);
      expect(t.pendingFineCents, 10000);
      expect(t.withHours(57000), 52000);
    });

    test('anular la multa sube el total', () {
      final t = ExtrasTotals.of([
        item(ExtraType.bonus, 5000),
        item(ExtraType.fine, 10000, status: ExtraStatus.cancelled),
      ]);
      expect(t.withHours(57000), 62000);
    });

    test('puede salir negativo', () {
      final t = ExtrasTotals.of([item(ExtraType.fine, 30000)]);
      expect(t.withHours(10000), -20000);
    });

    test('sin apuntes, igual que las horas', () {
      expect(ExtrasTotals.of(const []).withHours(57000), 57000);
      expect(ExtrasTotals.of(const []).isEmpty, isTrue);
    });
  });

  group('pronto pago y la paga la empresa (019)', () {
    ExtraItem fine(int cents, {bool early = false, bool company = false}) =>
        item(
          ExtraType.fine,
          cents,
        ).copyWith(earlyPayment: early, companyPays: company);

    test('pronto pago cuenta la mitad, el medio céntimo hacia arriba '
        '(RF-2)', () {
      expect(fine(15000, early: true).dueCents, 7500);
      expect(fine(7501, early: true).dueCents, 3751);
      expect(fine(1, early: true).dueCents, 1);
      expect(fine(15000).dueCents, 15000);
    });

    test('la que paga la empresa no resta (RF-4)', () {
      final t = ExtrasTotals.of([
        fine(15000, company: true),
        fine(10000, early: true),
        item(ExtraType.bonus, 2000),
      ]);
      expect(t.pendingFineCents, 5000);
      expect(t.withHours(10000), 10000 + 2000 - 5000);
    });

    test('un extra no puede llevarlos', () {
      expect(
        () => ExtraItem(
          type: ExtraType.bonus,
          date: DateTime(2026, 1, 1),
          cents: 100,
          concept: 'Dieta',
          earlyPayment: true,
        ),
        throwsArgumentError,
      );
      // Al pasar una multa a extra se apagan.
      final b = fine(100, early: true).copyWith(type: ExtraType.bonus);
      expect(b.earlyPayment, isFalse);
    });

    test('cambiar de estado los conserva', () {
      final f = fine(100, early: true, company: true);
      final closed = f.withStatus(ExtraStatus.closed, on: DateTime(2026, 12));
      expect(closed.earlyPayment, isTrue);
      expect(closed.companyPays, isTrue);
    });

    test('primera multa de cada año, sin contar las anuladas (RF-3)', () {
      final items = [
        item(ExtraType.fine, 100, id: 1, date: DateTime(2026, 5, 1)),
        item(ExtraType.fine, 100, id: 2, date: DateTime(2026, 2, 1)),
        item(
          ExtraType.fine,
          100,
          id: 3,
          date: DateTime(2026, 1, 1),
          status: ExtraStatus.cancelled,
        ),
        item(ExtraType.bonus, 100, id: 4, date: DateTime(2026, 1, 1)),
        item(ExtraType.fine, 100, id: 5, date: DateTime(2025, 7, 1)),
        item(ExtraType.fine, 100, id: 6, date: DateTime(2025, 7, 1)),
      ];
      expect(firstFinesOfYear(items), {2, 5});
      // Si se anula la primera, pasa a serlo la siguiente.
      items[1] = items[1].withStatus(ExtraStatus.cancelled);
      expect(firstFinesOfYear(items), {1, 5});
    });
  });

  group('orden de la lista (RF-6)', () {
    test('pendientes primero; en cada grupo, la más reciente arriba', () {
      final a = item(ExtraType.fine, 100, date: DateTime(2026, 10, 1), id: 1);
      final b = item(ExtraType.bonus, 100, date: DateTime(2026, 11, 1), id: 2);
      final c = item(
        ExtraType.fine,
        100,
        date: DateTime(2026, 11, 5),
        status: ExtraStatus.cancelled,
        id: 3,
      );
      final d = item(
        ExtraType.bonus,
        100,
        date: DateTime(2026, 9, 1),
        status: ExtraStatus.closed,
        id: 4,
      );
      expect(sortExtras([c, a, d, b]).map((e) => e.id), [2, 1, 3, 4]);
    });
  });
}
