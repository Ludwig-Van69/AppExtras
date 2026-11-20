import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/components/app_nav_bar.dart';
import 'package:horas_y_vacaciones/ui/components/big_hours.dart';
import 'package:horas_y_vacaciones/ui/components/pressable.dart';
import 'package:horas_y_vacaciones/ui/help_screen.dart';

import '../../fakes/in_memory_day_entry_repository.dart';
import '../test_app.dart';

/// Apuntar y borrar piden dos toques seguidos (013, RF-1 a RF-3).
Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// Viernes 6 de noviembre de 2026. Todos los datos son inventados.
DateTime _now = DateTime(2026, 11, 6, 18);

DayEntry _e(int month, int day, int minutes, {String? reason, DayKind? kind}) =>
    DayEntry(
      date: DateTime(2026, month, day),
      minutes: minutes,
      kind: kind ?? DayKind.normal,
      reason: reason,
    );

late InMemoryDayEntryRepository repo;

Future<void> _open(
  WidgetTester tester, [
  Iterable<DayEntry> days = const [],
]) async {
  _now = DateTime(2026, 11, 6, 18);
  repo = InMemoryDayEntryRepository(days);
  calmAnimations(tester);
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    HoursAndVacationApp(repository: repo, clock: () => _now),
  );
  await tester.pumpAndSettle();
}

Finder _preset(String hours) => find.bySemanticsLabel('Apuntar $hours');

/// La cifra grande (sin contar la de los botones).
Finder _big(String text) =>
    find.descendant(of: find.byType(BigHours), matching: find.text(text));

Future<void> _openOtherDay(WidgetTester tester) async {
  await tester.tap(find.text('Otro día'));
  await tester.pumpAndSettle();
}

Finder _monthTitle(String text) => find.text(text, findRichText: true);

IconButton _arrow(WidgetTester tester, String tooltip) => tester.widget(
  find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton)),
);

/// Lo que dice la rueda de «Otra» al lector de pantalla.
String _wheelValue(WidgetTester tester) =>
    tester.getSemantics(find.bySemanticsLabel('Horas')).value;

/// Gira la rueda [steps] medias horas (negativo, hacia atrás).
Future<void> _turnWheel(WidgetTester tester, int steps) async {
  final wheel = find.byType(ListWheelScrollView);
  final extent = tester.widget<ListWheelScrollView>(wheel).itemExtent;
  await tester.drag(wheel, Offset(0, -steps * extent));
  await tester.pumpAndSettle();
}

void main() {
  group('arranque y día', () {
    testWidgets('abre en Hoy, sin barra de navegación (RF-1, RF-23)', (
      tester,
    ) async {
      await _open(tester);
      expect(find.text('Viernes, 6 de noviembre'), findsOneWidget);
      expect(find.text('Otro día'), findsOneWidget);
      // Sin más secciones que Apuntar no hace falta barra; Ajustes se abre
      // con el engranaje de la esquina (007, RF-16).
      expect(find.byType(AppNavBar), findsNothing);
      expect(find.byTooltip('Ajustes'), findsOneWidget);
    });

    testWidgets('Ayer y Anteayer muestran su fecha y sus horas (RF-2)', (
      tester,
    ) async {
      await _open(tester, [_e(11, 4, 90)]);
      await tester.tap(find.text('Ayer'));
      await tester.pumpAndSettle();
      expect(find.text('Jueves, 5 de noviembre'), findsOneWidget);
      await tester.tap(find.text('Anteayer'));
      await tester.pumpAndSettle();
      expect(find.text('Miércoles, 4 de noviembre'), findsOneWidget);
      expect(_big('1,5'), findsOneWidget);
    });

    testWidgets(
      'deslizar a la izquierda va a Ayer y a la derecha vuelve a Hoy (006, RF-4)',
      (tester) async {
        await _open(tester);
        Future<void> swipe(double dx) async {
          await tester.fling(find.byType(BigHours), Offset(dx, 0), 1000);
          await tester.pumpAndSettle();
        }

        await swipe(300); // en Hoy, hacia la derecha no hace nada
        expect(find.text('Viernes, 6 de noviembre'), findsOneWidget);
        await swipe(-300);
        expect(find.text('Jueves, 5 de noviembre'), findsOneWidget);
        await swipe(-300);
        expect(find.text('Miércoles, 4 de noviembre'), findsOneWidget);
        await swipe(-300); // Anteayer es el tope
        expect(find.text('Miércoles, 4 de noviembre'), findsOneWidget);
        await swipe(300);
        expect(find.text('Jueves, 5 de noviembre'), findsOneWidget);
        // También desde los botones de abajo.
        await tester.fling(_preset('1 hora'), const Offset(300, 0), 1000);
        await tester.pumpAndSettle();
        expect(find.text('Viernes, 6 de noviembre'), findsOneWidget);
        expect(repo.days, isEmpty); // deslizar no apunta horas
      },
    );

    testWidgets('deslizar también funciona sobre el motivo (013, RF-17)', (
      tester,
    ) async {
      await _open(tester);
      await tester.fling(find.byType(TextField), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Jueves, 5 de noviembre'), findsOneWidget);
    });

    testWidgets('cambiar de día quita «✓ Apuntado» al momento (013, RF-13)', (
      tester,
    ) async {
      await _open(tester);
      await _doubleTap(tester, _preset('2 horas'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('marca-apuntado')), findsOneWidget);
      await tester.tap(find.text('Ayer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('marca-apuntado')), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('Otro día abre el Mosaico con las horas de cada día '
        '(RF-3, RF-4, RF-28, RF-29)', (tester) async {
      await _open(tester, [
        _e(10, 12, 120),
        _e(10, 17, 300, kind: DayKind.festive),
      ]);
      await _openOtherDay(tester);
      expect(find.text('Elige el día'), findsOneWidget);
      // Abre en el mes del día elegido; no se puede pasar del mes actual.
      expect(_monthTitle('Noviembre de 2026 · 0 h'), findsOneWidget);
      expect(_arrow(tester, 'Mes siguiente').onPressed, isNull);
      await tester.tap(find.byTooltip('Mes anterior'));
      await tester.pumpAndSettle();
      expect(_monthTitle('Octubre de 2026 · 7 h'), findsOneWidget);
      expect(find.bySemanticsLabel('12 oct: Normal, 2 horas'), findsOneWidget);
      expect(find.bySemanticsLabel('17 oct: Festiva, 5 horas'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('12 oct: Normal, 2 horas'));
      await tester.pumpAndSettle();
      expect(find.text('Elige el día'), findsNothing);
      expect(find.text('Lunes, 12 de octubre'), findsOneWidget);
      expect(_big('2'), findsOneWidget);
    });

    testWidgets('el título del mes abre el selector de mes y año '
        '(012, RF-1)', (tester) async {
      await _open(tester);
      await _openOtherDay(tester);
      await tester.tap(find.byKey(const ValueKey('elegir-mes')));
      await tester.pumpAndSettle();
      // Diciembre de 2026 aún no ha llegado: no se puede elegir.
      final december = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Diciembre'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(december.onPressed, isNull);
      await tester.tap(find.byTooltip('Año anterior'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marzo'));
      await tester.pumpAndSettle();
      expect(_monthTitle('Marzo de 2025 · 0 h'), findsOneWidget);
      expect(find.text('Elige el día'), findsOneWidget);
    });

    testWidgets(
      'en el calendario, los días futuros no se pueden tocar (RF-29)',
      (tester) async {
        await _open(tester);
        await _openOtherDay(tester);
        await tester.tap(find.bySemanticsLabel('20 nov: aún no ha llegado'));
        await tester.pumpAndSettle();
        expect(find.text('Elige el día'), findsOneWidget);
      },
    );

    testWidgets('no se puede ir antes de enero de 2020', (tester) async {
      await _open(tester);
      await _openOtherDay(tester);
      for (var i = 0; i < 82; i++) {
        final back = _arrow(tester, 'Mes anterior');
        if (back.onPressed == null) break;
        back.onPressed!();
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(_monthTitle('Enero de 2020 · 0 h'), findsOneWidget);
      expect(_arrow(tester, 'Mes anterior').onPressed, isNull);
    });

    testWidgets('si no se pueden leer las horas del mes, lo dice', (
      tester,
    ) async {
      await _open(tester);
      repo.failReads = true;
      await _openOtherDay(tester);
      await tester.tap(find.byTooltip('Mes anterior'));
      await tester.pumpAndSettle();
      expect(
        find.text('No se han podido leer las horas de este mes.'),
        findsOneWidget,
      );
    });

    testWidgets('al volver a la app otro día, elige el nuevo Hoy (RF-5)', (
      tester,
    ) async {
      await _open(tester);
      await tester.tap(find.text('Ayer'));
      await tester.pumpAndSettle();
      _now = DateTime(2026, 11, 7, 8);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Sábado, 7 de noviembre'), findsOneWidget);
      expect(find.text('Festiva'), findsOneWidget);
    });

    testWidgets('Ajustes abre la Ayuda; el catálogo de piezas no sale', (
      tester,
    ) async {
      await _open(tester);
      await tester.tap(find.byTooltip('Ajustes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ayuda'));
      await tester.pumpAndSettle();
      expect(find.byType(HelpScreen), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      // Solo sirve para los tests: el usuario no lo ve (bloque E).
      expect(find.text('Catálogo de piezas'), findsNothing);
    });
  });

  group('apuntar', () {
    testWidgets('diez botones, iguales en normal y festiva (RF-6)', (
      tester,
    ) async {
      await _open(tester);
      for (final h in [
        '1 hora',
        '1,5 horas',
        '3 horas',
        '4,5 horas',
        '5 horas',
      ]) {
        expect(_preset(h), findsOneWidget);
      }
      expect(find.text('Otra'), findsOneWidget);
      await tester.tap(find.text('Normal'));
      await tester.pumpAndSettle();
      expect(_preset('1 hora'), findsOneWidget);
      expect(_preset('5 horas'), findsOneWidget);
    });

    testWidgets(
      'dos toques guardan y se ve al momento; otro sustituye (RF-7)',
      (tester) async {
        await _open(tester);
        await _doubleTap(tester, _preset('2,5 horas'));
        await tester.pump();
        expect(_big('2,5'), findsOneWidget);
        await tester.pumpAndSettle();
        await _doubleTap(tester, _preset('1 hora'));
        await tester.pumpAndSettle();
        expect(repo.days['2026-11-06']!.minutes, 60);
      },
    );

    testWidgets('«Otra» es una rueda que empieza en 5,5 h (RF-8, RF-9)', (
      tester,
    ) async {
      await _open(tester);
      await tester.tap(find.text('Otra'));
      await tester.pumpAndSettle();
      expect(find.text('¿Cuántas horas?'), findsOneWidget);
      expect(_wheelValue(tester), '5,5 horas');
      await _turnWheel(tester, 3); // 3 medias horas más
      expect(_wheelValue(tester), '7 horas');
      await tester.tap(find.widgetWithText(FilledButton, 'Apuntar'));
      await tester.pumpAndSettle();
      expect(repo.days['2026-11-06']!.minutes, 420);
      expect(
        find.descendant(
          of: find.bySemanticsLabel('Apuntar otra cantidad'),
          matching: find.text('7 h'),
        ),
        findsOneWidget,
      );
      expect(find.text('Otra'), findsNothing);
    });

    testWidgets('la rueda empieza en el total del día', (tester) async {
      await _open(tester, [_e(11, 6, 600)]);
      await tester.tap(find.bySemanticsLabel('Apuntar otra cantidad'));
      await tester.pumpAndSettle();
      expect(_wheelValue(tester), '10 horas');
    });

    testWidgets('«Otra» con un valor de botón marca ese botón (RF-9)', (
      tester,
    ) async {
      await _open(tester);
      await tester.tap(find.text('Otra'));
      await tester.pumpAndSettle();
      await _turnWheel(tester, -7); // de 5,5 a 2 h
      expect(_wheelValue(tester), '2 horas');
      await tester.tap(find.widgetWithText(FilledButton, 'Apuntar'));
      await tester.pumpAndSettle();
      expect(find.text('Otra'), findsOneWidget);
      expect(
        tester.getSemantics(_preset('2 horas')),
        isSemantics(isSelected: true),
      );
    });

    testWidgets('la rueda no pasa de 24 h ni baja de 0,5 h', (tester) async {
      await _open(tester);
      await tester.tap(find.text('Otra'));
      await tester.pumpAndSettle();
      await _turnWheel(tester, 60);
      expect(_wheelValue(tester), '24 horas');
      await _turnWheel(tester, -60);
      expect(_wheelValue(tester), '0,5 horas');
    });

    testWidgets('cancelar «Otra» no cambia nada', (tester) async {
      await _open(tester);
      await tester.tap(find.text('Otra'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.writes, 0);
    });
  });

  group('tipo, motivo y resumen', () {
    testWidgets('el tipo se cambia con un toque y tiene su ⓘ (RF-12)', (
      tester,
    ) async {
      await _open(tester, [_e(11, 6, 60)]);
      await tester.tap(find.text('Normal'));
      await tester.pumpAndSettle();
      expect(find.text('Festiva'), findsOneWidget);
      expect(repo.days['2026-11-06']!.kind, DayKind.festive);
      expect(
        find.byTooltip('Más información: Normal o festiva'),
        findsOneWidget,
      );
    });

    testWidgets('sin horas, el motivo está desactivado (RF-15)', (
      tester,
    ) async {
      await _open(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
      expect(find.text('Apunta primero las horas'), findsOneWidget);
    });

    testWidgets('el motivo se guarda tras 1 s sin escribir (RF-14)', (
      tester,
    ) async {
      await _open(tester, [_e(11, 6, 60)]);
      await tester.enterText(find.byType(TextField), 'Inventario anual');
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo.days['2026-11-06']!.reason, isNull);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(repo.days['2026-11-06']!.reason, 'Inventario anual');
    });

    testWidgets('al guardarse el motivo se ve ✓ «Guardado» (006, RF-5)', (
      tester,
    ) async {
      await _open(tester, [_e(11, 6, 60)]);
      final check = find.byKey(const ValueKey('motivo-guardado'));
      expect(check, findsNothing);
      await tester.enterText(find.byType(TextField), 'Inventario anual');
      await tester.pump(const Duration(milliseconds: 500));
      expect(check, findsNothing); // aún escribiendo
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(check, findsOneWidget);
      expect(find.text('Guardado'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Guardado'), findsNothing);
      expect(check, findsOneWidget); // el ✓ se queda
      await tester.enterText(find.byType(TextField), 'Inventario anual 2');
      await tester.pump();
      expect(check, findsNothing); // lo visible ya no es lo guardado
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });

    testWidgets('un motivo ya guardado se abre con su ✓', (tester) async {
      await _open(tester, [_e(11, 6, 60, reason: 'Montaje')]);
      expect(find.byKey(const ValueKey('motivo-guardado')), findsOneWidget);
      expect(find.text('Guardado'), findsNothing);
    });

    testWidgets('el motivo se guarda al pasar la app a segundo plano', (
      tester,
    ) async {
      await _open(tester, [_e(11, 6, 60)]);
      await tester.enterText(find.byType(TextField), 'Montaje');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(repo.days['2026-11-06']!.reason, 'Montaje');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('el motivo escrito se queda en su día al cambiar de día', (
      tester,
    ) async {
      await _open(tester, [_e(11, 6, 60), _e(11, 5, 90)]);
      await tester.enterText(find.byType(TextField), 'Montaje');
      await tester.tap(find.text('Ayer'));
      await tester.pumpAndSettle();
      expect(repo.days['2026-11-06']!.reason, 'Montaje');
      expect(repo.days['2026-11-05']!.reason, isNull);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('sugiere motivos usados y se elige con un toque (RF-16)', (
      tester,
    ) async {
      await _open(tester, [
        _e(11, 2, 60, reason: 'Taller Norte'),
        _e(11, 3, 60, reason: 'Revisión camión'),
        _e(11, 6, 60),
      ]);
      await tester.enterText(find.byType(TextField), 'camion');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revisión camión').last);
      await tester.pumpAndSettle();
      expect(repo.days['2026-11-06']!.reason, 'Revisión camión');
    });

    testWidgets('resumen del mes por tipos, al momento (RF-21, RF-22)', (
      tester,
    ) async {
      await _open(tester, [
        _e(11, 1, 300, kind: DayKind.festive),
        _e(11, 3, 90),
        _e(10, 30, 600),
      ]);
      expect(find.text('6,5 h'), findsOneWidget); // este mes
      expect(find.text('1,5 h'), findsOneWidget); // normales
      expect(find.text('5 h'), findsOneWidget); // festivas
      await _doubleTap(tester, _preset('1 hora'));
      await tester.pumpAndSettle();
      expect(find.text('7,5 h'), findsOneWidget);
      expect(find.text('2,5 h'), findsOneWidget);
    });
  });

  group('doble toque (013, RF-1 a RF-5)', () {
    Finder hint() => find.byKey(const ValueKey('aviso-doble-toque'));

    testWidgets('un toque marca sin guardar; el segundo guarda', (
      tester,
    ) async {
      await _open(tester);
      await tester.tap(_preset('2 horas'));
      await tester.pump();
      expect(repo.days['2026-11-06'], isNull);
      expect(find.text('Toca otra vez para apuntar'), findsOneWidget);
      expect(
        tester.getSemantics(_preset('2 horas')).hint,
        'Toca otra vez para apuntar',
      );
      await tester.tap(_preset('2 horas'));
      await tester.pumpAndSettle();
      expect(repo.days['2026-11-06']!.minutes, 120);
      expect(hint(), findsNothing);
    });

    testWidgets('tocar otra cifra la marca a ella, sin guardar nada', (
      tester,
    ) async {
      await _open(tester);
      await tester.tap(_preset('2 horas'));
      await tester.pump();
      await tester.tap(_preset('3 horas'));
      await tester.pump();
      expect(repo.days['2026-11-06'], isNull);
      expect(tester.getSemantics(_preset('2 horas')).hint, isEmpty);
      expect(
        tester.getSemantics(_preset('3 horas')).hint,
        'Toca otra vez para apuntar',
      );
    });

    testWidgets('la marca se quita sola a los 3 s', (tester) async {
      await _open(tester);
      await tester.tap(_preset('2 horas'));
      await tester.pump();
      expect(hint(), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(hint(), findsNothing);
      // Tras quitarse, un toque vuelve a marcar, no guarda.
      await tester.tap(_preset('2 horas'));
      await tester.pump();
      expect(repo.days['2026-11-06'], isNull);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('con horas apuntadas, un toque no borra; el segundo sí', (
      tester,
    ) async {
      await _open(tester, [_e(11, 6, 120)]);
      await tester.tap(_preset('2 horas'));
      await tester.pump();
      expect(repo.days['2026-11-06']!.minutes, 120);
      expect(find.text('Toca otra vez para borrar'), findsOneWidget);
      await tester.tap(_preset('2 horas'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.days['2026-11-06'], isNull);
      expect(find.text('Deshacer'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('cambiar de día quita la marca', (tester) async {
      await _open(tester);
      await tester.tap(_preset('2 horas'));
      await tester.pump();
      await tester.tap(find.text('Ayer'));
      await tester.pumpAndSettle();
      expect(hint(), findsNothing);
      await tester.tap(_preset('2 horas'));
      await tester.pump();
      expect(repo.days['2026-11-05'], isNull);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('«✓ Apuntado» (012, RF-5)', () {
    Finder mark() => find.byKey(const ValueKey('marca-apuntado'));

    testWidgets('aparece al apuntar y se va sola', (tester) async {
      await _open(tester);
      expect(mark(), findsNothing);
      await _doubleTap(tester, _preset('3 horas'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(mark(), findsOneWidget);
      expect(find.text('Apuntado'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(mark(), findsNothing);
    });

    testWidgets('también con «Otra»', (tester) async {
      await _open(tester);
      await tester.tap(find.text('Otra'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apuntar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(mark(), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('no aparece al borrar ni al cambiar de día', (tester) async {
      await _open(tester, [_e(11, 6, 150)]);
      await _doubleTap(tester, _preset('2,5 horas'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(mark(), findsNothing);
      await tester.tap(find.text('Ayer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(mark(), findsNothing);
      await tester.pumpAndSettle();
    });
  });

  group('borrar y deshacer', () {
    testWidgets('«Borrar» en la ventana de «Otra» borra el día (012, RF-3)', (
      tester,
    ) async {
      await _open(tester, [_e(11, 6, 600)]);
      await tester.tap(find.bySemanticsLabel('Apuntar otra cantidad'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Borrar'));
      await tester.pumpAndSettle();
      expect(repo.days, isEmpty);
      expect(find.text('10 h borradas de hoy'), findsOneWidget);
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(repo.days['2026-11-06']!.minutes, 600);
    });

    testWidgets('sin horas, «Otra» no ofrece «Borrar» (012, RF-3)', (
      tester,
    ) async {
      await _open(tester);
      await tester.tap(find.text('Otra'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Borrar'), findsNothing);
    });

    testWidgets('borra el día y Deshacer lo devuelve igual (RF-18, RF-19)', (
      tester,
    ) async {
      final day = _e(11, 6, 150, reason: 'Taller', kind: DayKind.festive);
      await _open(tester, [day]);
      expect(find.byTooltip('Borrar las horas del día'), findsNothing);
      // Volver a tocar el botón resaltado borra el día (012, RF-2, RF-4).
      await _doubleTap(tester, _preset('2,5 horas'));
      await tester.pumpAndSettle();
      expect(find.text('2,5 h borradas de hoy'), findsOneWidget);
      expect(repo.days, isEmpty);
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(repo.days['2026-11-06'], day);
      expect(_big('2,5'), findsOneWidget);
    });

    testWidgets('el aviso nombra el día borrado si es antiguo', (tester) async {
      await _open(tester, [_e(10, 12, 60)]);
      await _openOtherDay(tester);
      await tester.tap(find.byTooltip('Mes anterior'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('12 oct: Normal, 1 hora'));
      await tester.pumpAndSettle();
      await _doubleTap(tester, _preset('1 hora'));
      await tester.pumpAndSettle();
      expect(find.text('1 h borradas del 12 de octubre'), findsOneWidget);
    });

    testWidgets('otro cambio quita el aviso de Deshacer (RF-20)', (
      tester,
    ) async {
      await _open(tester, [_e(11, 6, 150)]);
      await _doubleTap(tester, _preset('2,5 horas'));
      await tester.pumpAndSettle();
      await _doubleTap(tester, _preset('1 hora'));
      await tester.pumpAndSettle();
      expect(find.text('Deshacer'), findsNothing);
    });
  });

  group('errores', () {
    testWidgets('si no se guarda, vuelve a lo guardado y lo dice (RF-25)', (
      tester,
    ) async {
      await _open(tester, [_e(11, 6, 60)]);
      repo.failWrites = true;
      await _doubleTap(tester, _preset('3 horas'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No se ha podido guardar. Vuelve a intentarlo; si sigue '
          'fallando, reinicia la app.',
        ),
        findsOneWidget,
      );
      expect(_big('1'), findsOneWidget);
    });

    testWidgets('si no se pueden leer los datos, error y Reintentar (RF-26)', (
      tester,
    ) async {
      calmAnimations(tester);
      repo = InMemoryDayEntryRepository([_e(11, 6, 60)])..failReads = true;
      await tester.pumpWidget(
        HoursAndVacationApp(repository: repo, clock: () => _now),
      );
      await tester.pumpAndSettle();
      expect(find.text('No se pueden abrir tus datos'), findsOneWidget);
      expect(repo.days, hasLength(1));
      repo.failReads = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(_big('1'), findsOneWidget);
    });
  });

  group('tamaños sin desbordes', () {
    for (final width in [360.0, 390.0, 412.0]) {
      for (final scale in [1.0, 1.3]) {
        for (final brightness in Brightness.values) {
          testWidgets(
            '${width.toInt()} px, letra al ${(scale * 100).toInt()} %, '
            '${brightness.name}',
            (tester) async {
              await tester.binding.setSurfaceSize(Size(width, 780));
              addTearDown(() => tester.binding.setSurfaceSize(null));
              tester.platformDispatcher.platformBrightnessTestValue =
                  brightness;
              tester.platformDispatcher.textScaleFactorTestValue = scale;
              addTearDown(tester.platformDispatcher.clearAllTestValues);
              calmAnimations(tester);
              repo = InMemoryDayEntryRepository([
                _e(11, 6, 1290, reason: 'M' * 60), // 21,5 h y motivo máximo
              ]);
              await tester.pumpWidget(
                HoursAndVacationApp(repository: repo, clock: () => _now),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expect(find.text('21,5 h'), findsWidgets);
              await tester.tap(find.text('Anteayer'));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              // Lo que se toca mide al menos 48 × 48.
              final targets = [
                find.descendant(
                  of: _preset('4,5 horas'),
                  matching: find.byType(InkWell),
                ),
                // El botón entero (con su borde), no solo su interior.
                find.ancestor(
                  of: find.text('Otro día'),
                  matching: find.byType(Pressable),
                ),
              ];
              for (final f in targets) {
                final box = tester.getSize(f.first);
                expect(box.width, greaterThanOrEqualTo(48));
                expect(box.height, greaterThanOrEqualTo(48));
              }

              // El calendario: sin desbordes y cada día se toca bien.
              await _openOtherDay(tester);
              expect(tester.takeException(), isNull);
              final dayBox = tester.getSize(
                find
                    .ancestor(
                      of: find.bySemanticsLabel('6 nov: Normal, 21,5 horas'),
                      matching: find.byType(GestureDetector),
                    )
                    .first,
              );
              expect(dayBox.width, greaterThanOrEqualTo(48));
              expect(dayBox.height, greaterThanOrEqualTo(48));
              tester.state<NavigatorState>(find.byType(Navigator)).pop();
              await tester.pumpAndSettle();

              // La rueda de «Otra», en el valor más ancho.
              await tester.tap(find.bySemanticsLabel('Apuntar otra cantidad'));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expect(find.text('21,5 h'), findsWidgets);
            },
          );
        }
      }
    }
  });
}
