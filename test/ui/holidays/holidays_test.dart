import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/holiday_store.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/holidays.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/holidays/holidays_controller.dart';

import '../../fakes/in_memory_day_entry_repository.dart';
import '../test_app.dart';

/// Jueves 31 de diciembre de 2026: mañana es Año Nuevo. Datos inventados.
final _now = DateTime(2026, 12, 31, 18);

late HolidayData saved;
late HolidaysController holidays;
var failSave = false;

HolidaysController _controller([HolidayData initial = const HolidayData()]) {
  saved = initial;
  failSave = false;
  return HolidaysController(
    load: () async => saved,
    save: (d) async {
      if (failSave) throw StateError('fallo simulado');
      saved = d;
    },
  );
}

Future<void> _open(
  WidgetTester tester, {
  DateTime? now,
  double width = 390,
  double scale = 1,
}) async {
  holidays = _controller();
  await holidays.load();
  calmAnimations(tester);
  await tester.binding.setSurfaceSize(Size(width, 800));
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.platformDispatcher.clearAllTestValues();
  });
  await tester.pumpWidget(
    HoursAndVacationApp(
      repository: InMemoryDayEntryRepository(),
      holidays: holidays,
      clock: () => now ?? _now,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openHolidays(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Ajustes'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Festivos'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '«Otro día»: sábados y festivos sin horas, con contorno coral (013, RF-6)',
    (tester) async {
      await _open(tester);
      await tester.tap(find.text('Otro día'));
      await tester.pumpAndSettle();
      // 8-12-2026, martes: Inmaculada. 5-12-2026: sábado. 9-12: laborable.
      expect(find.bySemanticsLabel('8 dic: no laborable'), findsOneWidget);
      expect(find.bySemanticsLabel('5 dic: no laborable'), findsOneWidget);
      expect(find.bySemanticsLabel('9 dic: sin datos'), findsOneWidget);
    },
  );

  group('controlador', () {
    test('desactivar y reactivar un festivo de serie', () async {
      final c = _controller();
      await c.load();
      final reyes = builtInHolidays.firstWhere((h) => h.id == 'nat-reyes');
      await c.setEnabled(reyes, false);
      expect(c.calendar.holidayOn(DateTime(2026, 1, 6)), isNull);
      expect(saved.disabled, {'nat-reyes'});
      await c.setEnabled(reyes, true);
      expect(c.calendar.holidayOn(DateTime(2026, 1, 6)), isNotNull);
      expect(saved.disabled, isEmpty);
    });

    test('añadir un festivo propio limpia el nombre y lo guarda', () async {
      final c = _controller();
      await c.load();
      expect(
        await c.addCustom('  Mi fiesta  ', DateTime(2026, 6, 29), yearly: true),
        isTrue,
      );
      expect(saved.custom.single.name, 'Mi fiesta');
      expect(c.calendar.holidayOn(DateTime(2030, 6, 29)), isNotNull);
    });

    test('un nombre vacío no se añade y uno largo se corta', () async {
      final c = _controller();
      await c.load();
      expect(
        await c.addCustom('   ', DateTime(2026, 6, 29), yearly: true),
        isFalse,
      );
      expect(saved.custom, isEmpty);
      await c.addCustom('x' * 80, DateTime(2026, 6, 29), yearly: false);
      expect(saved.custom.single.name.length, maxHolidayNameLength);
    });

    test('borrar un festivo propio', () async {
      final c = _controller();
      await c.load();
      await c.addCustom('A', DateTime(2026, 6, 29), yearly: false);
      await c.removeCustom(saved.custom.single);
      expect(saved.custom, isEmpty);
      expect(c.calendar.holidayOn(DateTime(2026, 6, 29)), isNull);
    });

    test('si falla el guardado, el cambio vale y se avisa', () async {
      final c = _controller();
      await c.load();
      failSave = true;
      await c.addCustom('A', DateTime(2026, 6, 29), yearly: false);
      expect(c.saveFailed, isTrue);
      expect(c.calendar.holidayOn(DateTime(2026, 6, 29)), isNotNull);
    });

    test('si no se pueden leer, valen los de serie', () async {
      final c = HolidaysController(
        load: () async => throw StateError('x'),
        save: (_) async {},
      );
      await c.load();
      expect(c.calendar.holidayOn(DateTime(2026, 1, 1)), isNotNull);
    });
  });

  group('pantalla de apuntar', () {
    testWidgets(
      'un festivo entre semana se propone Festiva y se nombra (RF-1, RF-7)',
      (tester) async {
        await _open(tester, now: DateTime(2026, 1, 1, 12)); // jueves, Año Nuevo
        expect(find.text('Festiva'), findsOneWidget);
        expect(find.text('Festivo: Año Nuevo'), findsOneWidget);
      },
    );

    testWidgets('un día normal se propone Normal, sin aviso de festivo', (
      tester,
    ) async {
      await _open(tester, now: DateTime(2026, 11, 3, 12));
      expect(find.text('Normal'), findsOneWidget);
      expect(find.textContaining('Festivo:'), findsNothing);
    });

    testWidgets('desactivarlo hace que se proponga Normal', (tester) async {
      await _open(tester, now: DateTime(2026, 1, 1, 12));
      await _openHolidays(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Año Nuevo'));
      await tester.pumpAndSettle();
      // Festivos → Ajustes → Apuntar (Ajustes ya no es una sección).
      await tester.tap(find.byTooltip('Atrás'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Atrás'));
      await tester.pumpAndSettle();
      expect(find.text('Normal'), findsOneWidget);
      expect(find.textContaining('Festivo:'), findsNothing);
    });
  });

  group('pantalla de festivos', () {
    testWidgets('lista los de serie por grupos con su fecha (RF-3)', (
      tester,
    ) async {
      await _open(tester);
      await _openHolidays(tester);
      expect(find.text('Nacionales'), findsOneWidget);
      expect(find.text('Año Nuevo'), findsOneWidget);
      expect(find.text('1 de enero'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Los míos'), 200);
      expect(find.text('Regionales y locales'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Viernes Santo'), -200);
      expect(
        find.text('Cambia cada año · en 2026: 3 de abril'),
        findsOneWidget,
      );
    });

    testWidgets('añadir y borrar un festivo propio (RF-4)', (tester) async {
      await _open(tester);
      await _openHolidays(tester);
      await tester.scrollUntilVisible(find.text('Añadir festivo'), 200);
      await tester.tap(find.text('Añadir festivo'));
      await tester.pumpAndSettle();
      // Sin nombre, no se puede añadir.
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Añadir'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'San Pedro');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Añadir'));
      await tester.pumpAndSettle();
      expect(find.text('San Pedro'), findsOneWidget);
      expect(find.text('31 de diciembre · cada año'), findsOneWidget);
      expect(saved.custom.single.name, 'San Pedro');

      await tester.tap(find.byTooltip('Borrar San Pedro'));
      await tester.pumpAndSettle();
      expect(find.text('San Pedro'), findsNothing);
      expect(saved.custom, isEmpty);
    });

    testWidgets('avisa si no se puede guardar', (tester) async {
      await _open(tester);
      await _openHolidays(tester);
      failSave = true;
      await tester.tap(find.widgetWithText(SwitchListTile, 'Año Nuevo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No se han podido guardar'), findsOneWidget);
    });

    for (final width in [360.0, 412.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
          'cabe a ${width.toInt()} px con letra al ${(scale * 100).toInt()} %',
          (tester) async {
            await _open(
              tester,
              width: width,
              scale: scale,
              now: DateTime(2026, 12, 7),
            );
            expect(
              find.textContaining('Festivo: Constitución (trasladada)'),
              findsOneWidget,
            );
            await _openHolidays(tester);
            await tester.scrollUntilVisible(find.text('Añadir festivo'), 300);
            await tester.drag(find.byType(ListView), const Offset(0, -300));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Añadir festivo'));
            await tester.pumpAndSettle();
            await tester.enterText(find.byType(TextField), 'N' * 40);
            await tester.pump();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  test('suggestedKindFor sin calendario sigue siendo solo fin de semana', () {
    expect(suggestedKindFor(DateTime(2026, 1, 1)), DayKind.normal);
  });

  test('HolidayStore real se puede crear sin tocar el disco', () {
    expect(HolidayStore.inAppFolder, returnsNormally);
  });
}
