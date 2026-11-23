import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/saved_hours.dart';
import 'package:horas_y_vacaciones/ui/log/log_controller.dart';

import '../../fakes/in_memory_day_entry_repository.dart';

/// Viernes 6 de noviembre de 2026, por la tarde. Datos inventados.
DateTime _now = DateTime(2026, 11, 6, 18);

DayEntry _e(
  DateTime d,
  int m, {
  DayKind kind = DayKind.normal,
  String? reason,
}) => DayEntry(date: d, minutes: m, kind: kind, reason: reason);

void main() {
  late InMemoryDayEntryRepository repo;
  late LogController c;
  late int saveErrors;
  late int readErrors;

  Future<void> start([Iterable<DayEntry> initial = const []]) async {
    repo = InMemoryDayEntryRepository(initial);
    saveErrors = 0;
    readErrors = 0;
    c = LogController(repo, clock: () => _now)
      ..onSaveFailed = (() => saveErrors++)
      ..onReadFailed = (() => readErrors++);
    await c.load();
  }

  setUp(() => _now = DateTime(2026, 11, 6, 18));

  group('arranque y día (RF-1, RF-4, RF-5)', () {
    test('arranca en hoy, sin hora del reloj', () async {
      await start();
      expect(c.status, LogStatus.ready);
      expect(c.selectedDate, DateTime(2026, 11, 6));
      expect(c.dayOption, DayOption.today);
    });

    test('ayer, anteayer y otro día', () async {
      await start();
      await c.selectDate(DateTime(2026, 11, 5));
      expect(c.dayOption, DayOption.yesterday);
      await c.selectDate(DateTime(2026, 11, 4));
      expect(c.dayOption, DayOption.dayBefore);
      await c.selectDate(DateTime(2026, 10, 12));
      expect(c.dayOption, DayOption.other);
      expect(c.selectedDate, DateTime(2026, 10, 12));
    });

    test('no deja elegir días futuros ni anteriores a 2020', () async {
      await start();
      await c.selectDate(DateTime(2026, 11, 7));
      expect(c.selectedDate, DateTime(2026, 11, 6));
      await c.selectDate(DateTime(2019, 12, 31));
      expect(c.selectedDate, DateTime(2026, 11, 6));
      expect(c.firstSelectableDate, DateTime(2020));
    });

    test('ve las horas de otro mes al elegir un día de ese mes', () async {
      await start([_e(DateTime(2026, 9, 3), 120)]);
      await c.selectDate(DateTime(2026, 9, 3));
      expect(c.selectedMinutes, 120);
    });

    test('pasada la medianoche, vuelve a hoy con el día nuevo', () async {
      await start();
      await c.selectDate(DateTime(2026, 11, 4));
      _now = DateTime(2026, 11, 7, 0, 5);
      await c.refreshToday();
      expect(c.today, DateTime(2026, 11, 7));
      expect(c.selectedDate, DateTime(2026, 11, 7));
    });

    test('sin cambio de fecha, se queda en el día elegido', () async {
      await start();
      await c.selectDate(DateTime(2026, 11, 4));
      _now = DateTime(2026, 11, 6, 23, 59);
      await c.refreshToday();
      expect(c.selectedDate, DateTime(2026, 11, 4));
    });
  });

  group('apuntar (RF-7, RF-10)', () {
    test('guarda el total del día y se ve al momento', () async {
      await start();
      c.setMinutes(150);
      expect(c.selectedMinutes, 150); // antes de terminar de guardar
      await c.idle;
      expect(repo.days['2026-11-06']!.minutes, 150);
    });

    test('sustituye el total, no lo suma', () async {
      await start([_e(DateTime(2026, 11, 6), 60, reason: 'Taller')]);
      c.setMinutes(120);
      await c.idle;
      expect(
        repo.days['2026-11-06'],
        _e(DateTime(2026, 11, 6), 120, reason: 'Taller'),
      );
    });

    test('pulsar el total que ya tiene no hace nada', () async {
      await start([_e(DateTime(2026, 11, 6), 60)]);
      c.setMinutes(60);
      await c.idle;
      expect(repo.writes, 0);
    });

    test('rechaza valores que no son medias horas entre 0,5 y 24 h', () async {
      await start();
      expect(() => c.setMinutes(45), throwsArgumentError);
      expect(() => c.setMinutes(0), throwsArgumentError);
      expect(repo.writes, 0);
    });

    test('dos toques rápidos se guardan en orden y gana el último', () async {
      await start();
      repo.writeGate = Completer<void>();
      c.setMinutes(60);
      c.setMinutes(300);
      expect(c.selectedMinutes, 300);
      repo.writeGate!.complete();
      await c.idle;
      expect(repo.days['2026-11-06']!.minutes, 300);
      expect(c.selectedMinutes, 300);
    });
  });

  group('tipo (RF-11, RF-12, RF-13)', () {
    test('propone festivo el fin de semana y normal entre semana', () async {
      await start();
      expect(c.selectedKind, DayKind.normal);
      _now = DateTime(2026, 11, 8, 10); // domingo
      await c.refreshToday();
      expect(c.selectedKind, DayKind.festive);
    });

    test('el nuevo día se apunta con el tipo que se ve', () async {
      await start();
      c.toggleKind();
      c.setMinutes(120);
      await c.idle;
      expect(repo.days['2026-11-06']!.kind, DayKind.festive);
    });

    test('con horas, cambiar el tipo se guarda al momento', () async {
      await start([_e(DateTime(2026, 11, 6), 120)]);
      c.toggleKind();
      expect(c.selectedKind, DayKind.festive);
      await c.idle;
      expect(repo.days['2026-11-06']!.kind, DayKind.festive);
    });

    test(
      'sin horas, cambia el tipo sin guardar y al volver se propone otra vez',
      () async {
        await start();
        c.toggleKind();
        expect(c.selectedKind, DayKind.festive);
        await c.idle;
        expect(repo.writes, 0);
        await c.selectDate(DateTime(2026, 11, 5));
        await c.selectDate(DateTime(2026, 11, 6));
        expect(c.selectedKind, DayKind.normal);
      },
    );

    test('un día guardado conserva su tipo aunque se proponga otro', () async {
      await start([_e(DateTime(2026, 11, 7), 60)]); // sábado, normal
      _now = DateTime(2026, 11, 7, 12);
      await c.refreshToday();
      expect(c.selectedKind, DayKind.normal);
    });
  });

  group('motivo (RF-14, RF-16, RF-17)', () {
    test('se guarda limpio junto al día', () async {
      await start([_e(DateTime(2026, 11, 6), 60)]);
      c.setReason('  Taller Norte ');
      await c.idle;
      expect(repo.days['2026-11-06']!.reason, 'Taller Norte');
      expect(c.selectedReason, 'Taller Norte');
    });

    test('vacío, el día se queda sin motivo', () async {
      await start([_e(DateTime(2026, 11, 6), 60, reason: 'Taller')]);
      c.setReason('   ');
      await c.idle;
      expect(repo.days['2026-11-06']!.reason, isNull);
    });

    test('sin horas no se guarda nada', () async {
      await start();
      expect(c.canEditReason, isFalse);
      c.setReason('Taller');
      await c.idle;
      expect(repo.writes, 0);
    });

    test(
      'termina de guardar el motivo de un día tras cambiar a otro',
      () async {
        await start([
          _e(DateTime(2026, 11, 5), 60),
          _e(DateTime(2026, 11, 6), 90),
        ]);
        await c.selectDate(DateTime(2026, 11, 5));
        await c.selectDate(DateTime(2026, 11, 6));
        c.setReason('Inventario', date: DateTime(2026, 11, 5));
        await c.idle;
        expect(repo.days['2026-11-05']!.reason, 'Inventario');
        expect(repo.days['2026-11-06']!.reason, isNull);
      },
    );

    test('el mismo motivo no vuelve a guardar', () async {
      await start([_e(DateTime(2026, 11, 6), 60, reason: 'Taller')]);
      c.setReason('Taller ');
      await c.idle;
      expect(repo.writes, 0);
    });

    test('sugiere motivos ya usados, también los recién escritos', () async {
      await start([
        _e(DateTime(2026, 11, 2), 60, reason: 'Taller Norte'),
        _e(DateTime(2026, 11, 3), 60, reason: 'Taller Norte'),
        _e(DateTime(2026, 11, 4), 60, reason: 'Taller Sur'),
        _e(DateTime(2026, 11, 6), 60),
      ]);
      expect(c.suggestionsFor('tall'), ['Taller Norte', 'Taller Sur']);
      c.setReason('Talleres Este');
      await c.idle;
      expect(c.suggestionsFor('tall'), contains('Talleres Este'));
    });
  });

  group('borrar y deshacer (RF-18, RF-19, RF-20)', () {
    test('borra el día entero y deshacer lo devuelve igual', () async {
      final original = _e(
        DateTime(2026, 11, 6),
        150,
        kind: DayKind.festive,
        reason: 'Taller',
      );
      await start([original]);
      expect(c.deleteSelected(), original);
      expect(c.selectedMinutes, 0);
      await c.idle;
      expect(repo.days, isEmpty);
      await c.undoDelete();
      await c.idle;
      expect(repo.days['2026-11-06'], original);
      expect(c.selectedMinutes, 150);
      expect(c.selectedKind, DayKind.festive);
    });

    test('deshacer vuelve al día borrado aunque se cambie de día', () async {
      await start([_e(DateTime(2026, 11, 5), 60)]);
      await c.selectDate(DateTime(2026, 11, 5));
      c.deleteSelected();
      await c.selectDate(DateTime(2026, 11, 6));
      expect(c.canUndo, isTrue); // cambiar de día no es un cambio de datos
      await c.undoDelete();
      expect(c.selectedDate, DateTime(2026, 11, 5));
      expect(c.selectedMinutes, 60);
    });

    test('cualquier otro cambio quita la posibilidad de deshacer', () async {
      await start([_e(DateTime(2026, 11, 6), 60)]);
      c.deleteSelected();
      c.setMinutes(120);
      expect(c.canUndo, isFalse);
      await c.undoDelete();
      await c.idle;
      expect(repo.days['2026-11-06']!.minutes, 120);
    });

    test('borrar un día sin horas no hace nada', () async {
      await start();
      expect(c.deleteSelected(), isNull);
      expect(c.canUndo, isFalse);
    });
  });

  group('resumen del mes (RF-21, RF-22)', () {
    test('suma el mes del día elegido y se actualiza al momento', () async {
      await start([
        _e(DateTime(2026, 11, 1), 300, kind: DayKind.festive),
        _e(DateTime(2026, 11, 3), 90),
        _e(DateTime(2026, 10, 31), 600),
      ]);
      expect(c.monthSummary.totalMinutes, 390);
      c.setMinutes(60);
      expect(c.monthSummary.normalMinutes, 150);
      c.toggleKind();
      expect(c.monthSummary.festiveMinutes, 360);
      await c.selectDate(DateTime(2026, 10, 31));
      expect(c.monthSummary.totalMinutes, 600);
    });
  });

  group('errores (RF-25, RF-26)', () {
    test('si falla al guardar, vuelve a lo guardado y avisa', () async {
      await start([_e(DateTime(2026, 11, 6), 60)]);
      repo.failWrites = true;
      c.setMinutes(240);
      await c.idle;
      expect(c.selectedMinutes, 60);
      expect(saveErrors, 1);
    });

    test('si falla un borrado, el día sigue ahí', () async {
      await start([_e(DateTime(2026, 11, 6), 60)]);
      repo.failWrites = true;
      c.deleteSelected();
      await c.idle;
      expect(c.selectedMinutes, 60);
      expect(c.canUndo, isFalse);
      expect(saveErrors, 1);
    });

    test('un fallo seguido de un guardado bueno deja el bueno', () async {
      await start();
      final gate = Completer<void>();
      repo
        ..writeGate = gate
        ..failNextWrites = 1;
      c.setMinutes(60);
      c.setMinutes(90);
      // El primero falla; el segundo sale bien.
      repo.writeGate = null;
      gate.complete();
      await c.idle;
      expect(saveErrors, 1);
      expect(c.selectedMinutes, 90);
      expect(repo.days['2026-11-06']!.minutes, 90);
    });

    test(
      'si no se pueden leer los datos: error, nada se toca y se reintenta',
      () async {
        repo = InMemoryDayEntryRepository([_e(DateTime(2026, 11, 6), 60)])
          ..failReads = true;
        c = LogController(repo, clock: () => _now);
        await c.load();
        expect(c.status, LogStatus.error);
        expect(repo.writes, 0);
        repo.failReads = false;
        await c.load();
        expect(c.status, LogStatus.ready);
        expect(c.selectedMinutes, 60);
      },
    );

    test('si falla al leer otro mes, se queda en su día y avisa', () async {
      await start();
      repo.failReads = true;
      await c.selectDate(DateTime(2026, 8, 1));
      expect(c.selectedDate, DateTime(2026, 11, 6));
      expect(c.status, LogStatus.ready);
      expect(readErrors, 1);
    });
  });

  group('no bajar de lo apartado (008, RF-8)', () {
    late List<String> blocked;
    late List<SavedMove> moves;

    SavedMove apart(int hours, {SavedBox box = SavedBox.own, int day = 3}) =>
        SavedMove(
          box: box,
          kind: SavedMoveKind.setAside,
          date: DateTime(2026, 11, day),
          minutes: hours * 60,
        );

    Future<void> startWith(List<SavedMove> saved) async {
      repo = InMemoryDayEntryRepository([
        _e(DateTime(2026, 11, 3), 300),
        _e(DateTime(2026, 11, 6), 300),
        _e(DateTime(2026, 10, 30), 120),
      ]);
      moves = saved;
      blocked = [];
      saveErrors = 0;
      c = LogController(repo, clock: () => _now, savedMoves: () async => moves)
        ..onSaveFailed = (() => saveErrors++)
        ..onSetAsideBlocked = blocked.add;
      await c.load();
    }

    test('bajar hasta lo apartado sí se guarda', () async {
      await startWith([apart(7)]);
      c.setMinutes(120); // 5 + 2 = 7 h normales, lo mismo que lo apartado
      await c.idle;
      expect(blocked, isEmpty);
      expect(repo.days[dateKey(DateTime(2026, 11, 6))]!.minutes, 120);
    });

    test('bajar por debajo no se guarda, avisa y vuelve a lo guardado', () async {
      await startWith([apart(7)]);
      c.setMinutes(90);
      await c.idle;
      expect(blocked, [
        'Has apartado 7 h de este mes a Mi reserva. Quita antes ese apartado.',
      ]);
      expect(saveErrors, 0);
      expect(c.selectedMinutes, 300);
      expect(repo.days[dateKey(DateTime(2026, 11, 6))]!.minutes, 300);
    });

    test('borrar el día o pasarlo a festiva tampoco', () async {
      await startWith([apart(4), apart(2, box: SavedBox.company, day: 5)]);
      c.deleteSelected();
      await c.idle;
      expect(c.selectedMinutes, 300);
      expect(c.canUndo, isFalse);
      c.toggleKind();
      await c.idle;
      expect(c.selectedKind, DayKind.normal);
      expect(blocked, hasLength(2));
      expect(
        blocked.first,
        'Has apartado 6 h de este mes a Bolsa de empresa y Mi reserva. '
        'Quita antes ese apartado.',
      );
    });

    test('con cambios por libre, el aviso los nombra (022, RF-6)', () async {
      final swap = SavedMove(
        kind: SavedMoveKind.swap,
        date: DateTime(2026, 11, 4),
        minutes: 7 * 60,
      );
      await startWith([swap]);
      c.setMinutes(90);
      await c.idle;
      expect(blocked, [
        'Has cambiado 7 h de este mes por tiempo libre. Quita antes ese '
            'cambio.',
      ]);
      await startWith([apart(4), swap]);
      c.setMinutes(90);
      await c.idle;
      expect(blocked, [
        'Has sacado 11 h de este mes a Mi reserva y a tiempo libre. Quita '
            'antes esos movimientos.',
      ]);
    });

    test('subir horas o tocar otro mes no se frena', () async {
      await startWith([apart(10)]);
      c.setMinutes(360);
      await c.idle;
      await c.selectDate(DateTime(2026, 10, 30));
      c.deleteSelected();
      await c.idle;
      expect(blocked, isEmpty);
      expect(repo.days[dateKey(DateTime(2026, 11, 6))]!.minutes, 360);
      expect(repo.days[dateKey(DateTime(2026, 10, 30))], isNull);
    });

    test('el motivo se guarda aunque el mes esté justo', () async {
      await startWith([apart(10)]);
      c.setReason('Inventario');
      await c.idle;
      expect(blocked, isEmpty);
      expect(c.selectedReason, 'Inventario');
    });

    test(
      'si no se pueden leer las horas guardadas, es un fallo al guardar',
      () async {
        await startWith([apart(1)]);
        c = LogController(
          repo,
          clock: () => _now,
          savedMoves: () async => throw StateError('sin datos'),
        )..onSaveFailed = (() => saveErrors++);
        await c.load();
        c.setMinutes(60);
        await c.idle;
        expect(saveErrors, 1);
        expect(c.selectedMinutes, 300);
      },
    );
  });
}
