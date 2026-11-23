import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_settings.dart';
import 'package:horas_y_vacaciones/data/first_steps_store.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/data/holiday_store.dart';
import 'package:horas_y_vacaciones/domain/money.dart';
import 'package:horas_y_vacaciones/domain/vacations.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/first_steps/first_steps_controller.dart';
import 'package:horas_y_vacaciones/ui/holidays/holidays_controller.dart';
import 'package:horas_y_vacaciones/ui/money/money_controller.dart';
import 'package:horas_y_vacaciones/ui/vacation/vacation_controller.dart';
import 'package:path/path.dart' as p;

import '../../fakes/fake_backup_service.dart';
import '../../fakes/in_memory_day_entry_repository.dart';
import '../../fakes/in_memory_money_repository.dart';
import '../../fakes/in_memory_vacation_repository.dart';
import '../test_app.dart';

/// Viernes 6 de noviembre de 2026. Todos los datos son inventados.
final _now = DateTime(2026, 11, 6, 18);

late FirstStepsState saved;
late FirstStepsController steps;
late MoneyController money;
late InMemoryMoneyRepository moneyRepo;
late VacationController vacation;
late FakeBackupService backup;

Future<void> _open(
  WidgetTester tester, {
  FirstStepsState initial = const FirstStepsState(),
  bool rates = false,
  bool vacationSet = false,
  BackupSettings backupSettings = const BackupSettings(),
  double width = 390,
  double scale = 1,
}) async {
  saved = initial;
  steps = FirstStepsController(
    load: () async => saved,
    save: (s) async => saved = s,
  );
  await steps.load();
  moneyRepo = InMemoryMoneyRepository();
  if (rates) moneyRepo.rateList.add(Rate(DayKind.normal, DateTime(2020), 1500));
  money = MoneyController(
    days: InMemoryDayEntryRepository(),
    money: moneyRepo,
    clock: () => _now,
  );
  await money.load();
  vacation = VacationController(
    repository: InMemoryVacationRepository(
      stored: vacationSet
          ? VacationSettings(firstYear: 2025, firstHalfDays: 44)
          : null,
    ),
    clock: () => _now,
  );
  await vacation.load();
  var holidayData = const HolidayData();
  final holidays = HolidaysController(
    load: () async => holidayData,
    save: (d) async => holidayData = d,
  );
  await holidays.load();
  backup = FakeBackupService(settings: backupSettings);

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
      money: money,
      vacation: vacation,
      holidays: holidays,
      backup: backup,
      firstSteps: steps,
      clock: () => _now,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Resumen'));
  await tester.pumpAndSettle();
}

final _card = find.byKey(const ValueKey('primeros-pasos'));

/// La casilla de [label] está marcada.
bool _done(WidgetTester tester, String label) {
  final tile = find.ancestor(
    of: find.text(label),
    matching: find.byType(ListTile),
  );
  return find
      .descendant(of: tile, matching: find.byIcon(Icons.check_circle))
      .evaluate()
      .isNotEmpty;
}

void main() {
  group('archivo (RF-9, RF-10)', () {
    late Directory dir;
    late File file;
    late FirstStepsStore store;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('primeros_pasos_');
      file = File(p.join(dir.path, firstStepsFileName));
      store = FirstStepsStore(file);
    });
    tearDown(() => dir.delete(recursive: true));

    test('sin archivo, dañado o raro: estado inicial', () async {
      expect(await store.load(), const FirstStepsState());
      await file.writeAsString('{roto');
      expect(await store.load(), const FirstStepsState());
      await file.writeAsString('[1]');
      expect(await store.load(), const FirstStepsState());
      await file.writeAsString('{"closed": "sí"}');
      expect(await store.load(), const FirstStepsState());
    });

    test('guardar y leer; no deja temporales', () async {
      const s = FirstStepsState(holidaysSeen: true, closed: true);
      await store.save(s);
      expect(await store.load(), s);
      expect(dir.listSync().map((e) => p.basename(e.path)), [
        firstStepsFileName,
      ]);
    });

    test('si no se puede guardar, sigue con lo de memoria', () async {
      final c = FirstStepsController(
        load: () async => const FirstStepsState(),
        save: (_) async => throw const FileSystemException('lleno'),
      );
      await c.load();
      await c.close();
      expect(c.state.closed, isTrue);
    });
  });

  group('tarjeta en Resumen', () {
    testWidgets('sale con las cuatro casillas, en orden (RF-1)', (
      tester,
    ) async {
      await _open(tester);
      expect(_card, findsOneWidget);
      final labels = [
        'Pon tus tarifas',
        'Configura tus vacaciones',
        'Añade los festivos de tu zona',
        'Guarda una copia',
      ];
      final ys = [for (final l in labels) tester.getTopLeft(find.text(l)).dy];
      expect(ys, [...ys]..sort());
      for (final l in labels) {
        expect(_done(tester, l), isFalse, reason: l);
      }
      // Arriba del todo, antes de «A cobrar».
      expect(
        tester.getTopLeft(_card).dy,
        lessThan(tester.getTopLeft(find.text('A cobrar')).dy),
      );
    });

    testWidgets('se marcan solas según lo que hay (RF-2, RF-3, RF-5)', (
      tester,
    ) async {
      await _open(
        tester,
        rates: true,
        vacationSet: true,
        backupSettings: BackupSettings(lastShared: DateTime(2026, 11, 1)),
      );
      expect(_done(tester, 'Pon tus tarifas'), isTrue);
      expect(_done(tester, 'Configura tus vacaciones'), isTrue);
      expect(_done(tester, 'Guarda una copia'), isTrue);
      expect(_done(tester, 'Añade los festivos de tu zona'), isFalse);
    });

    testWidgets('con carpeta, la copia cuenta como hecha (RF-5)', (
      tester,
    ) async {
      await _open(
        tester,
        backupSettings: const BackupSettings(folder: 'content://inventada'),
      );
      expect(_done(tester, 'Guarda una copia'), isTrue);
    });

    testWidgets('cada línea abre su pantalla (RF-6)', (tester) async {
      await _open(tester);
      for (final (label, title) in [
        ('Pon tus tarifas', 'Tarifas'),
        ('Configura tus vacaciones', 'Vacaciones'),
        ('Guarda una copia', 'Copias y exportación'),
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppBar, title), findsOneWidget);
        await tester.tap(find.byTooltip('Atrás'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('abrir Festivos lo marca y se recuerda (RF-4, RF-6)', (
      tester,
    ) async {
      await _open(tester);
      await tester.tap(find.text('Añade los festivos de tu zona'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Festivos'), findsOneWidget);
      await tester.tap(find.byTooltip('Atrás'));
      await tester.pumpAndSettle();
      expect(_done(tester, 'Añade los festivos de tu zona'), isTrue);
      expect(saved.holidaysSeen, isTrue);
    });

    testWidgets('abrir Festivos desde Ajustes también cuenta (RF-4)', (
      tester,
    ) async {
      await _open(tester);
      await tester.tap(find.byTooltip('Ajustes').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Festivos'));
      await tester.pumpAndSettle();
      expect(saved.holidaysSeen, isTrue);
    });

    testWidgets('al volver de poner la copia, se actualiza (RF-6)', (
      tester,
    ) async {
      await _open(tester);
      await tester.tap(find.text('Guarda una copia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compartir copia'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Atrás'));
      await tester.pumpAndSettle();
      expect(_done(tester, 'Guarda una copia'), isTrue);
    });

    testWidgets('«Ocultar» la cierra para siempre (RF-8)', (tester) async {
      await _open(tester);
      await tester.tap(find.text('Ocultar'));
      await tester.pumpAndSettle();
      expect(_card, findsNothing);
      expect(saved.closed, isTrue);
    });

    testWidgets('cerrada, no sale', (tester) async {
      await _open(tester, initial: const FirstStepsState(closed: true));
      expect(_card, findsNothing);
    });

    testWidgets('al completar la cuarta se cierra y no vuelve (RF-7)', (
      tester,
    ) async {
      await _open(
        tester,
        initial: const FirstStepsState(holidaysSeen: true),
        rates: true,
        vacationSet: true,
      );
      expect(_card, findsOneWidget);
      backup.settings = const BackupSettings(folder: 'content://inventada');
      await tester.pumpAndSettle();
      expect(_card, findsNothing);
      expect(saved.closed, isTrue);
      // Aunque luego se quite la carpeta, sigue cerrada.
      backup.settings = const BackupSettings();
      await tester.pumpAndSettle();
      expect(_card, findsNothing);
    });

    testWidgets('sin el controlador, Resumen va sin tarjeta', (tester) async {
      final money = MoneyController(
        days: InMemoryDayEntryRepository(),
        money: InMemoryMoneyRepository(),
        clock: () => _now,
      );
      await money.load();
      calmAnimations(tester);
      await tester.pumpWidget(
        HoursAndVacationApp(
          repository: InMemoryDayEntryRepository(),
          money: money,
          clock: () => _now,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resumen'));
      await tester.pumpAndSettle();
      expect(_card, findsNothing);
    });

    for (final width in [360.0, 412.0]) {
      testWidgets('cabe a ${width.toInt()} px con letra al 130 %', (
        tester,
      ) async {
        await _open(tester, width: width, scale: 1.3);
        expect(tester.takeException(), isNull);
        expect(find.text('Añade los festivos de tu zona'), findsOneWidget);
      });
    }
  });
}
