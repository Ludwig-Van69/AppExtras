import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/company.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/extras.dart';
import 'package:horas_y_vacaciones/domain/vacations.dart';
import 'package:horas_y_vacaciones/ui/company/company_controller.dart';
import 'package:horas_y_vacaciones/ui/extras/extras_controller.dart';
import 'package:horas_y_vacaciones/ui/money/money_controller.dart';
import 'package:horas_y_vacaciones/ui/vacation/vacation_controller.dart';

import '../../fakes/in_memory_company_repository.dart';
import '../../fakes/in_memory_day_entry_repository.dart';
import '../../fakes/in_memory_extras_repository.dart';
import '../../fakes/in_memory_money_repository.dart';
import '../../fakes/in_memory_vacation_repository.dart';

/// Fallo corregido: cambiar algo que no son horas también deja «cambios sin
/// copiar», para que al salir se haga la copia automática (003, RF-4).
/// Datos inventados.
final _now = DateTime(2026, 11, 18, 10);

void main() {
  var changes = 0;
  Future<void> changed() async => changes++;
  setUp(() => changes = 0);

  test('vacaciones', () async {
    final repo = InMemoryVacationRepository();
    final c = VacationController(
      repository: repo,
      clock: () => _now,
      onChanged: changed,
    );
    await c.load();
    await c.saveSettings(VacationSettings(firstYear: 2021, firstHalfDays: 23));
    expect(changes, 1);
    repo.failWrites = true;
    await c.saveSettings(VacationSettings(firstYear: 2022, firstHalfDays: 20));
    expect(changes, 1);
  });

  test('multas y extras', () async {
    final repo = InMemoryExtrasRepository();
    final c = ExtrasController(
      repository: repo,
      clock: () => _now,
      onChanged: changed,
    );
    await c.load();
    final item = ExtraItem(
      type: ExtraType.fine,
      date: DateTime(2026, 11, 2),
      cents: 5000,
      concept: 'Multa inventada',
    );
    await c.save(item);
    expect(changes, 1);
    repo.failWrites = true;
    await c.save(item);
    expect(changes, 1);
  });

  test('tarifas, meses y horas guardadas', () async {
    final repo = InMemoryMoneyRepository();
    final c = MoneyController(
      days: InMemoryDayEntryRepository(),
      money: repo,
      clock: () => _now,
      onChanged: changed,
    );
    await c.load();
    await c.saveRate(DayKind.normal, 1500, DateTime(2020));
    expect(changes, 1);
    repo.failWrites = true;
    await c.saveRate(DayKind.normal, 1600, DateTime(2021));
    expect(changes, 1);
  });

  test('empresa', () async {
    final repo = InMemoryCompanyRepository();
    final c = CompanyController(
      repository: repo,
      clock: () => _now,
      onChanged: changed,
    );
    await c.save(Company(name: 'Talleres Ejemplo'));
    expect(changes, 1);
    repo.failWrites = true;
    await c.save(Company(name: 'Otra'));
    expect(changes, 1);
  });

  test('si avisar falla, lo guardado sigue bien guardado', () async {
    final c = CompanyController(
      repository: InMemoryCompanyRepository(),
      clock: () => _now,
      onChanged: () async => throw StateError('aviso fallido'),
    );
    expect(await c.save(Company(name: 'Talleres Ejemplo')), isTrue);
    expect(c.saveFailed, isFalse);
  });
}
