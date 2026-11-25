import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/company.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/company/company_controller.dart';
import 'package:horas_y_vacaciones/ui/components/app_nav_bar.dart';
import 'package:horas_y_vacaciones/ui/money/money_controller.dart';

import '../../fakes/fake_backup_service.dart';
import '../../fakes/in_memory_company_repository.dart';
import '../../fakes/in_memory_day_entry_repository.dart';
import '../../fakes/in_memory_money_repository.dart';
import '../test_app.dart';

/// Miércoles 25 de noviembre de 2026. Todos los datos son inventados.
final _now = DateTime(2026, 11, 25, 10);
final _alta = DateTime(2020, 3, 2);

late InMemoryCompanyRepository repo;
late CompanyController company;
var changes = 0;

Future<void> _app(
  WidgetTester tester, {
  Company stored = Company.empty,
  double width = 390,
  double scale = 1,
  FakeBackupService? backup,
}) async {
  calmAnimations(tester);
  await tester.binding.setSurfaceSize(Size(width, 844));
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.platformDispatcher.clearAllTestValues();
  });
  final days = InMemoryDayEntryRepository();
  final money = MoneyController(
    days: days,
    money: InMemoryMoneyRepository(),
    clock: () => _now,
    loadHidden: () async => false,
    saveHidden: (_) async {},
  );
  await money.load();
  repo = InMemoryCompanyRepository(stored);
  changes = 0;
  company = CompanyController(
    repository: repo,
    clock: () => _now,
    onChanged: () async => changes++,
  );
  await company.load();
  await tester.pumpWidget(
    HoursAndVacationApp(
      repository: days,
      money: money,
      company: company,
      backup: backup,
      clock: () => _now,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openCompany(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Ajustes'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Empresa'));
  await tester.pumpAndSettle();
}

Future<void> _openMetrics(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppNavBar),
      matching: find.text('Métricas'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Ajustes › Empresa', () {
    testWidgets('sin nada: entrada en Ajustes y fecha sin poner (RF-1)', (
      tester,
    ) async {
      await _app(tester);
      await tester.tap(find.byTooltip('Ajustes'));
      await tester.pumpAndSettle();
      expect(find.text('Nombre y fecha de alta'), findsOneWidget);
      await tester.tap(find.text('Empresa'));
      await tester.pumpAndSettle();
      expect(find.text('Sin poner'), findsOneWidget);
      expect(find.textContaining('Hoy llevas'), findsNothing);
    });

    testWidgets('elegir la fecha la guarda y cuenta los días (RF-2, RF-9)', (
      tester,
    ) async {
      await _app(tester);
      await _openCompany(tester);
      await tester.tap(find.text('Fecha de alta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10'));
      await tester.tap(find.text('ACEPTAR'));
      await tester.pumpAndSettle();
      expect(repo.stored.start, DateTime(2026, 11, 10));
      expect(find.text('10 nov 2026'), findsOneWidget);
      expect(find.text('Hoy llevas 15 días'), findsOneWidget);
      expect(changes, 1);
    });

    testWidgets('el selector no ofrece días después de hoy (RF-7)', (
      tester,
    ) async {
      await _app(tester);
      await _openCompany(tester);
      await tester.tap(find.text('Fecha de alta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('28'));
      await tester.tap(find.text('ACEPTAR'));
      await tester.pumpAndSettle();
      expect(repo.stored.start, isNot(DateTime(2026, 11, 28)));
    });

    testWidgets('con fecha: días con miles; borrar y deshacer (RF-2, RF-6)', (
      tester,
    ) async {
      await _app(tester, stored: Company(start: _alta));
      await _openCompany(tester);
      expect(find.text('2 mar 2020'), findsOneWidget);
      expect(find.text('Hoy llevas 2.459 días'), findsOneWidget);

      await tester.tap(find.byTooltip('Borrar la fecha de alta'));
      await tester.pumpAndSettle();
      expect(repo.stored, Company.empty);
      expect(find.text('Sin poner'), findsOneWidget);
      expect(find.text('Fecha de alta borrada'), findsOneWidget);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(repo.stored.start, _alta);
      expect(find.text('Hoy llevas 2.459 días'), findsOneWidget);
    });

    testWidgets('el nombre se guarda sin espacios; borrar y deshacer '
        '(RF-6, RF-8)', (tester) async {
      await _app(tester);
      await _openCompany(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre'),
        '  Talleres Ejemplo ',
      );
      await tester.pumpAndSettle();
      expect(repo.stored.name, 'Talleres Ejemplo');

      await tester.tap(find.byTooltip('Borrar el nombre'));
      await tester.pumpAndSettle();
      expect(repo.stored.name, isNull);
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(repo.stored.name, 'Talleres Ejemplo');
      expect(
        find.widgetWithText(TextField, 'Talleres Ejemplo'),
        findsOneWidget,
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Talleres Ejemplo'), findsOneWidget);
    });

    testWidgets('el nombre no pasa de 60 caracteres (RF-8)', (tester) async {
      await _app(tester);
      await _openCompany(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre'),
        'a' * 70,
      );
      await tester.pumpAndSettle();
      expect(repo.stored.name, hasLength(60));
    });

    testWidgets('si no se puede guardar, lo dice', (tester) async {
      await _app(tester, stored: Company(start: _alta));
      repo.failWrites = true;
      await _openCompany(tester);
      await tester.tap(find.byTooltip('Borrar la fecha de alta'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No se ha podido guardar'), findsOneWidget);
      expect(find.text('Fecha de alta borrada'), findsNothing);
      expect(changes, 0);
    });

    testWidgets('sin desbordes a 360 px con letra al 130 %', (tester) async {
      await _app(
        tester,
        stored: Company(name: 'a' * 60, start: _alta),
        width: 360,
        scale: 1.3,
      );
      await _openCompany(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Métricas', () {
    testWidgets('con fecha, la línea de antigüedad arriba (RF-4)', (
      tester,
    ) async {
      await _app(
        tester,
        stored: Company(name: 'Talleres Ejemplo', start: _alta),
      );
      await _openMetrics(tester);
      expect(
        find.text(
          'Talleres Ejemplo · desde el 2 mar 2020 · '
          '6 años, 8 meses y 23 días · 2.459 días',
        ),
        findsOneWidget,
      );
    });

    testWidgets('sin nombre, y menos de un mes: sin repetir los días', (
      tester,
    ) async {
      await _app(tester, stored: Company(start: DateTime(2026, 11, 24)));
      await _openMetrics(tester);
      expect(find.text('desde el 24 nov 2026 · 1 día'), findsOneWidget);
    });

    testWidgets('sin fecha (aunque haya nombre), sin línea (RF-5)', (
      tester,
    ) async {
      await _app(tester, stored: Company(name: 'Talleres Ejemplo'));
      await _openMetrics(tester);
      expect(find.textContaining('desde el'), findsNothing);
    });

    testWidgets('sin desbordes a 360 px con letra al 130 %', (tester) async {
      await _app(
        tester,
        stored: Company(name: 'a' * 60, start: _alta),
        width: 360,
        scale: 1.3,
      );
      await _openMetrics(tester);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('al restaurar una copia se vuelve a leer la empresa (RF-9)', (
    tester,
  ) async {
    final backup = FakeBackupService();
    await _app(tester, backup: backup);
    repo.stored = Company(start: _alta);
    backup.restoredCount++;
    backup.notifyListeners();
    await tester.pumpAndSettle();
    await _openMetrics(tester);
    expect(find.textContaining('2.459 días'), findsOneWidget);
  });
}
