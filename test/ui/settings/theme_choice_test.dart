import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/prefs_store.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:path/path.dart' as p;

import '../../fakes/in_memory_day_entry_repository.dart';
import '../test_app.dart';

/// Preferencias en memoria: en las pruebas de pantalla los archivos no
/// terminan de escribirse con el reloj simulado.
class _MemoryPrefs extends PrefsStore {
  _MemoryPrefs() : super(File('sin-uso.json'));
  String? theme;

  @override
  Future<String?> loadTheme() async => theme;

  @override
  Future<void> saveTheme(String value) async => theme = value;

  bool decor = true;

  @override
  Future<bool> loadCalendarDecor() async => decor;

  @override
  Future<void> saveCalendarDecor(bool value) async => decor = value;
}

/// Datos inventados.
void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('prefs_test_');
    file = File(p.join(dir.path, prefsFileName));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('preferencias (009, RF-10)', () {
    test('sin archivo: Automático y sin ocultar', () async {
      final prefs = PrefsStore(file);
      expect(await prefs.loadTheme(), isNull);
      expect(await prefs.loadHideAmounts(), isFalse);
    });

    test('guardar una preferencia conserva la otra', () async {
      final prefs = PrefsStore(file);
      await prefs.saveHideAmounts(true);
      await prefs.saveTheme('dark');
      expect(await prefs.loadHideAmounts(), isTrue);
      expect(await prefs.loadTheme(), 'dark');
      await prefs.saveHideAmounts(false);
      expect(await prefs.loadTheme(), 'dark');
    });

    test('calendarios temáticos: activados de serie y se recuerdan '
        '(013, RF-11)', () async {
      final prefs = PrefsStore(file);
      expect(await prefs.loadCalendarDecor(), isTrue);
      await prefs.saveTheme('dark');
      await prefs.saveCalendarDecor(false);
      expect(await prefs.loadCalendarDecor(), isFalse);
      expect(await prefs.loadTheme(), 'dark');
    });

    test('un archivo dañado vale como vacío', () async {
      file.writeAsStringSync('{no es json');
      final prefs = PrefsStore(file);
      expect(await prefs.loadTheme(), isNull);
      await prefs.saveTheme('light');
      expect(await prefs.loadTheme(), 'light');
    });
  });

  Brightness shown(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(Scaffold).last)).brightness;

  Future<void> openApp(WidgetTester tester, _MemoryPrefs prefs) async {
    calmAnimations(tester);
    await tester.pumpWidget(
      HoursAndVacationApp(
        key: UniqueKey(),
        repository: InMemoryDayEntryRepository(),
        prefs: prefs,
        clock: () => DateTime(2026, 11, 18, 10),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Ajustes → Aspecto cambia al momento y se recuerda (RF-9)', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final prefs = _MemoryPrefs();
    await openApp(tester, prefs);
    expect(shown(tester), Brightness.light);

    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('Aspecto'), findsOneWidget);
    expect(find.text('Automático'), findsOneWidget);
    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();
    expect(shown(tester), Brightness.dark);
    expect(prefs.theme, 'dark');

    // Al volver a abrir la app, sigue en oscuro.
    await openApp(tester, prefs);
    expect(shown(tester), Brightness.dark);
  });

  testWidgets('Automático sigue al móvil', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await openApp(tester, _MemoryPrefs());
    expect(shown(tester), Brightness.dark);
  });

  testWidgets('calendarios temáticos: se ven en diciembre y se pueden '
      'apagar (013, RF-9 a RF-11)', (tester) async {
    final prefs = _MemoryPrefs();
    Future<void> open() async {
      calmAnimations(tester);
      await tester.pumpWidget(
        HoursAndVacationApp(
          key: UniqueKey(),
          repository: InMemoryDayEntryRepository(),
          prefs: prefs,
          clock: () => DateTime(2026, 12, 28, 10),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Otro día'));
      await tester.pumpAndSettle();
    }

    await open();
    expect(find.byKey(const ValueKey('decor-christmas')), findsOneWidget);
    // 24 y 25 llevan estrellita (el 31 aún no ha llegado, pero también).
    expect(find.byKey(const ValueKey('marca-star')), findsNWidgets(3));
    await tester.tapAt(const Offset(10, 10)); // cierra el calendario
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendarios temáticos'));
    await tester.pumpAndSettle();
    expect(prefs.decor, isFalse);

    // Al volver a abrir la app, siguen apagados.
    await open();
    expect(find.byKey(const ValueKey('decor-christmas')), findsNothing);
    expect(find.byKey(const ValueKey('marca-star')), findsNothing);
  });
}
