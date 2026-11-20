import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/holidays.dart';
import 'package:horas_y_vacaciones/domain/vacations.dart';
import 'package:horas_y_vacaciones/ui/vacation/vacation_controller.dart';

import '../../fakes/in_memory_vacation_repository.dart';

/// Miércoles 18 de noviembre de 2026. Datos inventados.
final _now = DateTime(2026, 11, 18, 10);
final _settings = VacationSettings(firstYear: 2021, firstHalfDays: 23);

void main() {
  late InMemoryVacationRepository repo;
  late VacationController c;

  Future<void> start({
    VacationSettings? settings,
    List<VacationDay> days = const [],
  }) async {
    repo = InMemoryVacationRepository(stored: settings, days: days);
    c = VacationController(
      repository: repo,
      clock: () => _now,
      calendar: HolidayCalendar.new,
    );
    await c.load();
  }

  test('sin configurar no hay saldo (RF-4)', () async {
    await start();
    expect(c.status, VacationStatus.ready);
    expect(c.isConfigured, isFalse);
    expect(c.overview, isNull);
    expect(await c.toggle(DateTime(2026, 11, 18)), VacationTap.outOfRange);
    expect(repo.byDate, isEmpty);
  });

  test('guardar ajustes (RF-1)', () async {
    await start();
    await c.saveSettings(_settings);
    expect(repo.stored, _settings);
    expect(c.overview!.leftHalfDays, 23 + 5 * 44);
  });

  test('marcar, desmarcar y deshacer con su año (RF-5)', () async {
    await start(settings: _settings);
    expect(await c.toggle(DateTime(2026, 1, 2)), VacationTap.marked);
    // 2025 tiene sus 22 días: el 2 de enero cuenta para 2025.
    expect(c.dayOn(DateTime(2026, 1, 2))!.year, 2025);
    expect(await c.toggle(DateTime(2026, 1, 2)), VacationTap.unmarked);
    expect(repo.byDate, isEmpty);
    await c.restore(c.lastRemoved!);
    expect(repo.byDate.values.single, VacationDay(DateTime(2026, 1, 2), 2025));
  });

  test(
    'sábados, festivos y fuera de rango no se marcan (RF-6, RF-7)',
    () async {
      await start(settings: _settings);
      expect(await c.toggle(DateTime(2026, 11, 21)), VacationTap.notWorkday);
      expect(await c.toggle(DateTime(2026, 12, 8)), VacationTap.notWorkday);
      expect(await c.toggle(DateTime(2020, 6, 1)), VacationTap.outOfRange);
      expect(await c.toggle(DateTime(2028, 1, 3)), VacationTap.outOfRange);
      expect(await c.toggle(DateTime(2027, 12, 31)), VacationTap.marked);
      expect(repo.byDate, hasLength(1));
    },
  );

  test(
    'pulsación larga: cambia de año, nunca antes del primero (RF-9)',
    () async {
      await start(
        settings: _settings,
        days: [
          VacationDay(DateTime(2026, 1, 2), 2025),
          VacationDay(DateTime(2021, 3, 1), 2021),
        ],
      );
      expect(await c.switchYear(DateTime(2026, 1, 2)), 2026);
      expect(await c.switchYear(DateTime(2026, 1, 2)), 2025);
      expect(await c.switchYear(DateTime(2021, 3, 1)), isNull);
      expect(await c.switchYear(DateTime(2026, 5, 4)), isNull); // no marcado
    },
  );

  test('medio día: se cambia y conserva el año (012, RF-9)', () async {
    await start(
      settings: _settings,
      days: [VacationDay(DateTime(2026, 1, 2), 2025)],
    );
    expect(await c.setHalf(DateTime(2026, 1, 2), true), isTrue);
    expect(
      repo.byDate[DateTime(2026, 1, 2)],
      VacationDay(DateTime(2026, 1, 2), 2025, half: true),
    );
    // Cambiar de año no pierde el medio día.
    expect(await c.switchYear(DateTime(2026, 1, 2)), 2026);
    expect(repo.byDate[DateTime(2026, 1, 2)]!.half, isTrue);
    expect(await c.setHalf(DateTime(2026, 5, 4), true), isFalse); // no marcado
  });

  test('un fallo al guardar no cambia nada y lo avisa', () async {
    await start(settings: _settings);
    repo.failWrites = true;
    expect(await c.toggle(DateTime(2026, 11, 18)), VacationTap.failed);
    expect(c.saveFailed, isTrue);
    expect(c.days, isEmpty);
  });
}
