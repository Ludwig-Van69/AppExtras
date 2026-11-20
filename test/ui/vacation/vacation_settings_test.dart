import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/vacations.dart';
import 'package:horas_y_vacaciones/ui/format.dart';
import 'package:horas_y_vacaciones/ui/vacation/vacation_controller.dart';
import 'package:horas_y_vacaciones/ui/vacation/vacation_settings_screen.dart';

import '../../fakes/in_memory_vacation_repository.dart';
import '../test_app.dart';

/// Miércoles 18 de noviembre de 2026. Datos inventados.
final _now = DateTime(2026, 11, 18, 10);

late InMemoryVacationRepository repo;
late VacationController vacation;

Future<void> _open(WidgetTester tester, {VacationSettings? settings}) async {
  calmAnimations(tester);
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  repo = InMemoryVacationRepository(stored: settings);
  vacation = VacationController(repository: repo, clock: () => _now);
  await vacation.load();
  await tester.pumpWidget(
    testApp(
      SizedBox(height: 1100, child: VacationSettingsScreen(vacation: vacation)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextField, label), text);
  await tester.pumpAndSettle();
}

void main() {
  test('medios días: leer y escribir', () {
    expect(parseHalfDays('11,5'), 23);
    expect(parseHalfDays('11.5'), 23);
    expect(parseHalfDays('22'), 44);
    expect(parseHalfDays('22,0'), 44);
    expect(parseHalfDays('11,3'), isNull);
    expect(parseHalfDays(''), isNull);
    expect(formatHalfDays(21), '10,5');
    expect(formatHalfDays(44), '22');
    expect(formatHalfDays(-11), '−5,5');
  });

  testWidgets('configurar por primera vez (RF-1)', (tester) async {
    await _open(tester);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2021').last);
    await tester.pumpAndSettle();
    await _type(tester, 'Días del primer año', '11,5');
    expect(repo.stored, isNull); // sin configurar se guarda con el botón
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(repo.stored, VacationSettings(firstYear: 2021, firstHalfDays: 23));
    expect(find.text('Días de cada año'), findsOneWidget);
  });

  testWidgets('un valor imposible no se guarda', (tester) async {
    await _open(tester);
    await _type(tester, 'Días del primer año', '61');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('entre 0 y 60'), findsOneWidget);
    expect(repo.stored, isNull);
  });

  testWidgets('ya configurado, se guarda solo', (tester) async {
    await _open(
      tester,
      settings: VacationSettings(firstYear: 2021, firstHalfDays: 23),
    );
    await _type(tester, 'Días al año', '23');
    expect(repo.stored!.yearlyHalfDays, 46);
  });

  testWidgets('corregir un año y quitar la corrección (RF-2)', (tester) async {
    await _open(
      tester,
      settings: VacationSettings(firstYear: 2021, firstHalfDays: 23),
    );
    await tester.tap(find.byKey(const ValueKey('anio-2024')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '20');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Guardar'));
    await tester.pumpAndSettle();
    expect(repo.stored!.overrides, {2024: 40});
    expect(find.text('Corregido a mano'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('anio-2024')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quitar corrección'));
    await tester.pumpAndSettle();
    expect(repo.stored!.overrides, isEmpty);
  });
}
