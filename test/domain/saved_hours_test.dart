import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/money.dart';
import 'package:horas_y_vacaciones/domain/saved_hours.dart';

/// Datos inventados.
SavedMove move(
  SavedBox box,
  SavedMoveKind kind,
  int hours, {
  DateTime? date,
  int? cents,
  int? id,
}) => SavedMove(
  id: id,
  box: box,
  kind: kind,
  date: date ?? DateTime(2026, 11, 2),
  minutes: hours * 60,
  cents: cents ?? (kind == SavedMoveKind.paid ? 0 : null),
);

void main() {
  final today = DateTime(2026, 11, 18, 9);
  final rates = [Rate(DayKind.normal, DateTime(2020), 1500)];

  group('borrar una tarifa con apartados (013, RF-15)', () {
    final a = Rate(DayKind.normal, DateTime(2025), 1500);
    final b = Rate(DayKind.normal, DateTime(2026), 1600);
    final f = Rate(DayKind.festive, DateTime(2025), 2000);
    final all = [a, b, f];
    final in2025 = move(
      SavedBox.own,
      SavedMoveKind.setAside,
      3,
      date: DateTime(2025, 3, 3),
    );
    final in2026 = move(
      SavedBox.own,
      SavedMoveKind.setAside,
      2,
      date: DateTime(2026, 3, 3),
    );

    test('no deja sin precio a un apartado', () {
      expect(setAsidesLeftUnpriced(a, all, [in2025, in2026]), [in2025]);
    });

    test('si otra tarifa lo cubre, se puede borrar', () {
      expect(setAsidesLeftUnpriced(b, all, [in2025, in2026]), isEmpty);
    });

    test('las tarifas festivas no ponen precio a los apartados', () {
      expect(setAsidesLeftUnpriced(f, all, [in2025, in2026]), isEmpty);
    });
  });

  group('validación (RF-3)', () {
    SavedProblem? check({int? minutes = 180, DateTime? date, String? note}) =>
        validateSavedMove(
          minutes: minutes,
          date: date ?? DateTime(2026, 11, 2),
          today: today,
          note: note,
        );

    test('acepta medias horas entre 0,5 y 999 h', () {
      expect(check(minutes: 30), isNull);
      expect(check(minutes: 999 * 60), isNull);
      expect(check(minutes: 90), isNull);
    });

    test('rechaza horas raras o fuera de rango', () {
      expect(check(minutes: null), SavedProblem.hours);
      expect(check(minutes: 0), SavedProblem.hours);
      expect(check(minutes: 45), SavedProblem.hours);
      expect(check(minutes: 999 * 60 + 30), SavedProblem.hours);
    });

    test('rechaza fechas antes de 2020 o futuras; hoy vale', () {
      expect(check(date: DateTime(2019, 12, 31)), SavedProblem.date);
      expect(check(date: DateTime(2026, 11, 19)), SavedProblem.date);
      expect(check(date: today), isNull);
    });

    test('nota de hasta 60 letras, sin contar espacios de los bordes', () {
      expect(check(note: '  ${'a' * 60}  '), isNull);
      expect(check(note: 'a' * 61), SavedProblem.note);
    });
  });

  group('movimiento', () {
    test('solo un cobro lleva importe', () {
      expect(
        () => move(SavedBox.own, SavedMoveKind.timeOff, 2, cents: 100),
        throwsArgumentError,
      );
      expect(
        () => SavedMove(
          box: SavedBox.own,
          kind: SavedMoveKind.paid,
          date: today,
          minutes: 60,
        ),
        throwsArgumentError,
      );
    });

    test('la nota vacía queda sin nota', () {
      final m = SavedMove(
        box: SavedBox.own,
        kind: SavedMoveKind.before,
        date: today,
        minutes: 60,
        note: '   ',
      );
      expect(m.note, isNull);
      expect(m.date, DateTime(2026, 11, 18));
    });

    test('las salidas restan', () {
      expect(move(SavedBox.own, SavedMoveKind.before, 3).signedMinutes, 180);
      expect(move(SavedBox.own, SavedMoveKind.setAside, 3).signedMinutes, 180);
      expect(move(SavedBox.own, SavedMoveKind.timeOff, 3).signedMinutes, -180);
      expect(move(SavedBox.own, SavedMoveKind.paid, 3).signedMinutes, -180);
    });
  });

  group('saldo sin negativos (RF-4)', () {
    final moves = [
      move(SavedBox.own, SavedMoveKind.before, 39, date: DateTime(2025, 1, 1)),
      move(SavedBox.company, SavedMoveKind.before, 16),
    ];

    test('40 h de un cajón con 39 no caben', () {
      expect(savedAvailable(moves, SavedBox.own, today), 39 * 60);
      final out = move(SavedBox.own, SavedMoveKind.paid, 40, date: today);
      expect(findSavedShortfall([...moves, out]), isNotNull);
      final ok = move(SavedBox.own, SavedMoveKind.paid, 39, date: today);
      expect(findSavedShortfall([...moves, ok]), isNull);
    });

    test('no se puede sacar antes de que entren las horas', () {
      expect(savedAvailable(moves, SavedBox.own, DateTime(2024, 6, 1)), 0);
      final early = move(
        SavedBox.own,
        SavedMoveKind.timeOff,
        1,
        date: DateTime(2024, 6, 1),
      );
      expect(
        findSavedShortfall([...moves, early]),
        SavedShortfall(SavedBox.own, DateTime(2024, 6, 1)),
      );
    });

    test('una salida antigua cuenta con las salidas posteriores', () {
      final later = move(
        SavedBox.own,
        SavedMoveKind.paid,
        30,
        date: DateTime(2026, 11, 10),
      );
      expect(savedAvailable([...moves, later], SavedBox.own, today), 9 * 60);
      expect(
        savedAvailable([...moves, later], SavedBox.own, DateTime(2026, 3, 1)),
        9 * 60,
      );
    });

    test('borrar una entrada ya gastada deja un cajón en negativo', () {
      final out = move(SavedBox.company, SavedMoveKind.timeOff, 10);
      expect(findSavedShortfall([moves[1], out]), isNull);
      expect(
        findSavedShortfall([out]),
        SavedShortfall(SavedBox.company, DateTime(2026, 11, 2)),
      );
    });

    test('entradas y salidas del mismo día se compensan', () {
      final same = [
        move(SavedBox.own, SavedMoveKind.timeOff, 2),
        move(SavedBox.own, SavedMoveKind.setAside, 2),
      ];
      expect(findSavedShortfall(same), isNull);
    });
  });

  group('cobro congelado (RF-9, RF-10)', () {
    test('55 h a 15 € son 825,00 €', () {
      expect(savedPaidCents(55 * 60, today, rates), 82500);
    });

    test('usa la tarifa del día del cobro', () {
      final two = [...rates, Rate(DayKind.normal, DateTime(2027), 1600)];
      expect(savedPaidCents(60, today, two), 1500);
      expect(savedPaidCents(60, DateTime(2027, 1, 2), two), 1600);
    });

    test('media hora a 15,25 € redondea la mitad hacia arriba', () {
      final r = [Rate(DayKind.normal, DateTime(2020), 1525)];
      expect(savedPaidCents(30, today, r), 763);
    });

    test('sin tarifa normal no hay importe; la festiva no vale', () {
      expect(savedPaidCents(60, today, const []), isNull);
      final festive = [Rate(DayKind.festive, DateTime(2020), 2000)];
      expect(savedPaidCents(60, today, festive), isNull);
    });
  });

  group('resumen (RF-12, RF-13, RF-16)', () {
    final moves = [
      move(SavedBox.company, SavedMoveKind.before, 16),
      move(SavedBox.own, SavedMoveKind.before, 45),
      move(SavedBox.own, SavedMoveKind.timeOff, 2),
      move(SavedBox.own, SavedMoveKind.paid, 4, cents: 6000),
    ];

    test('saldos, valor a la tarifa de hoy y lo que ya salió', () {
      final s = SavedSummary.of(moves, rates, today);
      expect(s.balances[SavedBox.company], 16 * 60);
      expect(s.balances[SavedBox.own], 39 * 60);
      expect(s.totalMinutes, 55 * 60);
      expect(s.values[SavedBox.company], 24000);
      expect(s.values[SavedBox.own], 58500);
      expect(s.totalValueCents, 82500);
      expect(s.compensatedMinutes, 120);
      expect(s.paidMinutes, 240);
      expect(s.paidCents, 6000);
    });

    test('el cobro no cambia aunque cambie la tarifa', () {
      final s = SavedSummary.of(moves, [
        ...rates,
        Rate(DayKind.normal, DateTime(2026, 11, 15), 1600),
      ], today);
      expect(s.paidCents, 6000);
      expect(s.totalValueCents, 88000);
    });

    test('sin tarifa de hoy, horas sí pero sin valor', () {
      final s = SavedSummary.of(moves, const [], today);
      expect(s.totalMinutes, 55 * 60);
      expect(s.values[SavedBox.own], isNull);
      expect(s.totalValueCents, isNull);
    });

    test('vacío', () {
      expect(SavedSummary.of(const [], rates, today).isEmpty, isTrue);
      expect(SavedSummary.of(moves, rates, today).isEmpty, isFalse);
    });
  });

  test('orden: más reciente primero y, a igual fecha, el último apuntado', () {
    final a = move(SavedBox.own, SavedMoveKind.before, 1, id: 1);
    final b = move(SavedBox.own, SavedMoveKind.before, 1, id: 2);
    final c = move(
      SavedBox.own,
      SavedMoveKind.before,
      1,
      id: 3,
      date: DateTime(2026, 1, 1),
    );
    expect(sortSavedMoves([c, a, b]), [b, a, c]);
  });

  group('¿se puede guardar o borrar? (RF-4, RF-7)', () {
    final entries = [
      DayEntry(date: DateTime(2026, 11, 3), minutes: 600, kind: DayKind.normal),
      DayEntry(date: DateTime(2026, 10, 3), minutes: 300, kind: DayKind.normal),
    ];
    final october = MonthRecord(
      const YearMonth(2026, 10),
      deliveredOn: DateTime(2026, 11, 2),
    );
    final base = move(
      SavedBox.own,
      SavedMoveKind.before,
      39,
      id: 1,
      date: DateTime(2025, 1, 1),
    );
    final octApart = SavedMove(
      id: 2,
      box: SavedBox.own,
      kind: SavedMoveKind.setAside,
      date: DateTime(2026, 10, 5),
      minutes: 120,
    );
    final all = [base, octApart];

    String? check(SavedMove? m, {SavedMove? old}) => checkSavedMove(
      move: m,
      old: old,
      all: all,
      entries: entries,
      rates: rates,
      records: [october],
    );

    test('sacar más de lo que hay: «Solo hay 41 h…»', () {
      expect(
        check(move(SavedBox.own, SavedMoveKind.paid, 42, cents: 0)),
        'Solo hay 41 h en Mi reserva a esa fecha.',
      );
      expect(
        check(move(SavedBox.own, SavedMoveKind.paid, 41, cents: 0)),
        isNull,
      );
      expect(
        check(move(SavedBox.company, SavedMoveKind.timeOff, 1)),
        'Solo hay 0 h en Bolsa de empresa a esa fecha.',
      );
    });

    test('borrar una entrada ya gastada no se puede', () {
      final spent = [
        ...all,
        move(SavedBox.own, SavedMoveKind.paid, 40, id: 3, cents: 0),
      ];
      expect(
        checkSavedMove(
          move: null,
          old: base,
          all: spent,
          entries: entries,
          rates: rates,
          records: [october],
        ),
        'Esas horas de Mi reserva ya han salido. Quita antes la salida.',
      );
    });

    test('apartar de noviembre (abierto) hasta sus horas normales', () {
      SavedMove nov(int h) => SavedMove(
        box: SavedBox.company,
        kind: SavedMoveKind.setAside,
        date: DateTime(2026, 11, 10),
        minutes: h * 60,
      );
      expect(check(nov(10)), isNull);
      expect(check(nov(11)), SetAsideProblem.tooMany.message);
    });

    test(
      'apartar de octubre (entregado) no; ni cambiar o borrar lo apartado',
      () {
        final more = SavedMove(
          box: SavedBox.own,
          kind: SavedMoveKind.setAside,
          date: DateTime(2026, 10, 20),
          minutes: 60,
        );
        expect(check(more), SetAsideProblem.notOpen.message);
        expect(check(null, old: octApart), SetAsideProblem.notOpen.message);
        final noted = SavedMove(
          id: 2,
          box: SavedBox.own,
          kind: SavedMoveKind.setAside,
          date: DateTime(2026, 10, 5),
          minutes: 120,
          note: 'Para Semana Santa',
        );
        expect(check(noted, old: octApart), isNull);
      },
    );

    test('al editar no cuenta dos veces el propio movimiento', () {
      final bigger = SavedMove(
        id: 1,
        box: SavedBox.own,
        kind: SavedMoveKind.before,
        date: DateTime(2025, 1, 1),
        minutes: 40 * 60,
      );
      expect(check(bigger, old: base), isNull);
    });
  });

  group('cambio por libre (022)', () {
    SavedMove swap(int hours, {DateTime? date, DateTime? dayOff, int? id}) =>
        SavedMove(
          id: id,
          kind: SavedMoveKind.swap,
          date: date ?? DateTime(2026, 11, 10),
          minutes: hours * 60,
          dayOff: dayOff,
        );

    test('no tiene cajón; los demás sí; solo él lleva día libre (RF-1)', () {
      expect(swap(3).box, isNull);
      expect(
        () => SavedMove(
          kind: SavedMoveKind.swap,
          box: SavedBox.own,
          date: DateTime(2026, 11, 10),
          minutes: 60,
        ),
        throwsArgumentError,
      );
      expect(
        () => SavedMove(
          kind: SavedMoveKind.setAside,
          date: DateTime(2026, 11, 10),
          minutes: 60,
        ),
        throwsArgumentError,
      );
      expect(
        () => SavedMove(
          kind: SavedMoveKind.timeOff,
          box: SavedBox.own,
          date: DateTime(2026, 11, 10),
          minutes: 60,
          dayOff: DateTime(2026, 11, 20),
        ),
        throwsArgumentError,
      );
      expect(SavedMoveKind.swap.takesFromMonth, isTrue);
      expect(SavedMoveKind.setAside.takesFromMonth, isTrue);
      expect(SavedMoveKind.timeOff.takesFromMonth, isFalse);
    });

    test('no toca los cajones y suma en «Compensadas» (RF-3)', () {
      final s = SavedSummary.of(
        [
          move(SavedBox.own, SavedMoveKind.before, 10),
          swap(3),
          move(SavedBox.own, SavedMoveKind.timeOff, 2),
        ],
        rates,
        today,
      );
      expect(s.balances[SavedBox.own], 8 * 60);
      expect(s.balances[SavedBox.company], 0);
      expect(s.compensatedMinutes, 5 * 60);
      expect(findSavedShortfall([swap(3)]), isNull);
    });

    test('el día libre va del 1-1-2020 al 31-12 del año siguiente (RF-4)', () {
      SavedProblem? check(DateTime d) => validateSavedMove(
        minutes: 60,
        date: DateTime(2026, 11, 10),
        today: today,
        dayOff: d,
      );
      expect(check(DateTime(2027, 12, 31)), isNull);
      expect(check(DateTime(2020)), isNull);
      expect(check(DateTime(2028)), SavedProblem.dayOff);
      expect(check(DateTime(2019, 12, 31)), SavedProblem.dayOff);
      expect(
        SavedProblem.dayOff.messageFor(today),
        'El día libre debe estar entre el 1-1-2020 y el 31-12-2027.',
      );
    });

    final entries = [
      DayEntry(date: DateTime(2026, 11, 3), minutes: 600, kind: DayKind.normal),
      DayEntry(date: DateTime(2026, 10, 3), minutes: 300, kind: DayKind.normal),
    ];
    final october = MonthRecord(
      const YearMonth(2026, 10),
      deliveredOn: DateTime(2026, 11, 2),
    );
    final apart = SavedMove(
      id: 1,
      box: SavedBox.own,
      kind: SavedMoveKind.setAside,
      date: DateTime(2026, 11, 4),
      minutes: 4 * 60,
    );
    String? check(SavedMove? m, {SavedMove? old, List<SavedMove>? all}) =>
        checkSavedMove(
          move: m,
          old: old,
          all: all ?? [apart],
          entries: entries,
          rates: rates,
          records: [october],
        );

    test('mismas reglas que un apartado y cuentan juntos (RF-2)', () {
      expect(check(swap(6)), isNull);
      expect(check(swap(7)), SetAsideProblem.tooMany.message);
      expect(
        check(swap(1, date: DateTime(2026, 10, 5))),
        SetAsideProblem.notOpen.message,
      );
      final old = swap(1, id: 2, date: DateTime(2026, 10, 5));
      expect(
        check(null, old: old, all: [apart, old]),
        SetAsideProblem.notOpen.message,
      );
    });

    test('cambiar solo el día libre o la nota siempre se puede (RF-5)', () {
      final old = swap(1, id: 2, date: DateTime(2026, 10, 5));
      final edited = swap(
        1,
        id: 2,
        date: DateTime(2026, 10, 5),
        dayOff: DateTime(2026, 12, 1),
      );
      expect(check(edited, old: old, all: [apart, old]), isNull);
    });

    test('resta del mes con su importe, como un apartado (RF-2, RF-10)', () {
      final o = MoneyOverview.compute(
        entries: entries,
        rates: rates,
        records: const [],
        savedMoves: [apart, swap(3)],
      );
      final nov = o.months.firstWhere(
        (l) => l.month == const YearMonth(2026, 11),
      );
      expect(nov.minutes, 3 * 60);
      expect(nov.amountCents, 4500);
      expect(nov.setAsideMinutes, 7 * 60);
      expect(nov.boxedMinutes, 4 * 60);
      expect(nov.swappedMinutes, 3 * 60);
      expect(monthsShortOfSetAside(entries, [swap(11)]), [
        const YearMonth(2026, 11),
      ]);
    });
  });
}
