import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/money.dart';
import 'package:horas_y_vacaciones/domain/saved_hours.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/money/money_controller.dart';
import 'package:horas_y_vacaciones/ui/extras/extras_controller.dart';
import 'package:horas_y_vacaciones/ui/extras/extras_screen.dart';

import '../../fakes/in_memory_day_entry_repository.dart';
import '../../fakes/in_memory_extras_repository.dart';
import '../../fakes/in_memory_money_repository.dart';
import '../../fakes/in_memory_saved_hours_repository.dart';
import '../test_app.dart';

/// Apuntar y borrar piden dos toques seguidos (013, RF-1 a RF-3).
Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// Miércoles 18 de noviembre de 2026. Todos los datos son inventados.
final _now = DateTime(2026, 11, 18, 10);

late InMemorySavedHoursRepository saved;
late InMemoryDayEntryRepository days;
late MoneyController money;

SavedMove _before(SavedBox box, int hours, {int? id}) => SavedMove(
  id: id,
  box: box,
  kind: SavedMoveKind.before,
  date: DateTime(2025, 1, 1),
  minutes: hours * 60,
);

Future<void> _makeMoney({
  List<SavedMove> moves = const [],
  List<DayEntry> entries = const [],
  bool withRate = true,
}) async {
  saved = InMemorySavedHoursRepository(moves);
  days = InMemoryDayEntryRepository(entries);
  var hidden = false;
  money = MoneyController(
    days: days,
    money: InMemoryMoneyRepository()
      ..rateList.addAll([
        if (withRate) Rate(DayKind.normal, DateTime(2020), 1500),
      ]),
    saved: saved,
    clock: () => _now,
    loadHidden: () async => hidden,
    saveHidden: (v) async => hidden = v,
  );
  await money.load();
}

Future<void> _open(
  WidgetTester tester, {
  List<SavedMove> moves = const [],
  List<DayEntry> entries = const [],
  bool withRate = true,
  double width = 390,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  calmAnimations(tester);
  await tester.binding.setSurfaceSize(Size(width, 800));
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.platformDispatcher.clearAllTestValues();
  });
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  await _makeMoney(moves: moves, entries: entries, withRate: withRate);
  final extras = ExtrasController(
    repository: InMemoryExtrasRepository(),
    clock: () => _now,
  );
  await extras.load();
  await tester.pumpWidget(
    HoursAndVacationApp(
      repository: days,
      money: money,
      extras: extras,
      clock: () => _now,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Extra'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Horas guardadas'));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextField, label), text);
  await tester.pumpAndSettle();
}

Future<void> _tapAdd(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Añadir');
  await tester.scrollUntilVisible(
    button,
    200,
    scrollable: find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  // Que se vea entero: si asoma solo un poco, el toque no le llega.
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
}

void main() {
  testWidgets('sin movimientos lo dice y ofrece «Añadir»', (tester) async {
    await _open(tester);
    expect(find.text('Extra'), findsWidgets);
    expect(find.textContaining('Aún no hay movimientos'), findsOneWidget);
    expect(find.byIcon(Icons.business_outlined), findsOneWidget);
    expect(find.byIcon(Icons.savings_outlined), findsOneWidget);
    expect(find.textContaining('Posible'), findsNothing);
    expect(find.textContaining('posible'), findsNothing);
    expect(find.text('0 h'), findsNWidgets(2));
  });

  testWidgets('se pasa de pestaña deslizando el dedo (009, RF-1)', (
    tester,
  ) async {
    await _open(tester, moves: [_before(SavedBox.own, 39)]);
    expect(find.text('39 h'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.textContaining('Aún no hay multas ni extras'), findsOneWidget);
    expect(find.text('39 h'), findsNothing);
    final segments = tester.widget<SegmentedButton<ExtraTab>>(
      find.byType(SegmentedButton<ExtraTab>),
    );
    expect(segments.selected, {ExtraTab.extras});
    // «Añadir» abre ahora una multa o un extra.
    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo apunte'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('39 h'), findsOneWidget);
  });

  testWidgets('saldos con su valor, lo que ya salió y la lista (RF-13)', (
    tester,
  ) async {
    await _open(
      tester,
      moves: [
        _before(SavedBox.company, 16),
        _before(SavedBox.own, 41),
        SavedMove(
          box: SavedBox.own,
          kind: SavedMoveKind.paid,
          date: DateTime(2026, 11, 2),
          minutes: 120,
          cents: 3000,
          note: 'Adelanto',
        ),
      ],
    );
    expect(find.text('16 h'), findsOneWidget);
    expect(find.text('39 h'), findsOneWidget);
    expect(find.text('240,00 €'), findsOneWidget);
    expect(find.text('585,00 €'), findsOneWidget);
    expect(
      find.text('Compensadas: 0 h · Cobradas: 2 h · 30,00 €'),
      findsOneWidget,
    );
    expect(find.text('Cobrar · Mi reserva'), findsOneWidget);
    expect(find.text('2 nov 2026 · Adelanto · 30,00 €'), findsOneWidget);
    expect(find.text('−2 h'), findsOneWidget);
    expect(find.text('+16 h'), findsOneWidget);
  });

  testWidgets('sin tarifa: horas sí, «Falta la tarifa» (RF-16)', (
    tester,
  ) async {
    await _open(tester, moves: [_before(SavedBox.own, 39)], withRate: false);
    expect(find.text('39 h'), findsOneWidget);
    expect(find.text('Falta la tarifa'), findsNWidgets(2));
  });

  testWidgets('ocultar importes oculta estos euros (RF-17)', (tester) async {
    await _open(tester, moves: [_before(SavedBox.own, 39)]);
    expect(find.text('585,00 €'), findsOneWidget);
    await tester.tap(find.byTooltip('Ocultar importes'));
    await tester.pumpAndSettle();
    expect(find.text('585,00 €'), findsNothing);
    expect(find.text('•••• €'), findsWidgets);
    expect(money.hideAmounts, isTrue);
  });

  testWidgets('añadir «Horas de antes» (RF-14)', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo movimiento'), findsOneWidget);
    await tester.tap(find.text('Horas de antes'));
    await tester.tap(find.text('Bolsa de empresa').last);
    await _type(tester, 'Horas', '16');
    await _type(tester, 'Nota (opcional)', 'De otros años');
    await _tapAdd(tester);
    await tester.pumpAndSettle();
    expect(find.text('Nuevo movimiento'), findsNothing);
    final m = saved.byId.values.single;
    expect(m.kind, SavedMoveKind.before);
    expect(m.box, SavedBox.company);
    expect(m.minutes, 960);
    expect(m.note, 'De otros años');
    expect(m.date, DateTime(2026, 11, 18));
    expect(find.text('16 h'), findsOneWidget);
  });

  testWidgets('horas que no son medias horas no se guardan (RF-3)', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    await _type(tester, 'Horas', '2,3');
    await _tapAdd(tester);
    await tester.pumpAndSettle();
    expect(find.text(SavedProblem.hours.message), findsOneWidget);
    expect(saved.byId, isEmpty);
  });

  testWidgets('sacar más de lo que hay se rechaza (RF-4)', (tester) async {
    await _open(tester, moves: [_before(SavedBox.own, 39)]);
    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiempo libre'));
    await _type(tester, 'Horas', '40');
    await _tapAdd(tester);
    await tester.pumpAndSettle();
    expect(
      find.text('Solo hay 39 h en Mi reserva a esa fecha.'),
      findsOneWidget,
    );
    expect(saved.byId, hasLength(1));
  });

  testWidgets('tiempo libre: jornada y «Día completo» (020)', (tester) async {
    await _open(tester, moves: [_before(SavedBox.own, 39)]);
    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    // Con otro movimiento no salen (criterio 3).
    expect(find.byKey(const ValueKey('dia-completo')), findsNothing);
    await tester.tap(find.text('Tiempo libre'));
    await tester.pumpAndSettle();
    expect(
      find.text('Jornada de 39 h: de lunes a jueves 8 h, viernes 7 h.'),
      findsOneWidget,
    );
    // Hoy es miércoles: 8 h, y se puede seguir cambiando a mano.
    await tester.tap(find.text('Día completo · 8 h'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Horas'))
          .controller!
          .text,
      '8',
    );
    await _tapAdd(tester);
    await tester.pumpAndSettle();
    expect(
      saved.byId.values
          .where((m) => m.kind == SavedMoveKind.timeOff)
          .single
          .minutes,
      480,
    );
  });

  testWidgets('día completo: viernes 7 h y fin de semana desactivado (020)', (
    tester,
  ) async {
    SavedMove off(int id, int day) => SavedMove(
      id: id,
      box: SavedBox.own,
      kind: SavedMoveKind.timeOff,
      date: DateTime(2026, 11, day),
      minutes: 60,
      note: 'Día $day',
    );
    await _open(
      tester,
      moves: [_before(SavedBox.own, 39, id: 1), off(2, 13), off(3, 14)],
    );
    await tester.tap(find.textContaining('Día 13'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Día completo · 7 h'));
    await tester.pumpAndSettle();
    expect(saved.byId[2]!.minutes, 420);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Día 14'));
    await tester.pumpAndSettle();
    final button = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('dia-completo')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Fin de semana: sin jornada'), findsOneWidget);
  });

  testWidgets('cobrar congela el importe y lo anuncia (RF-9)', (tester) async {
    await _open(tester, moves: [_before(SavedBox.own, 39)]);
    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cobrar'));
    await _type(tester, 'Horas', '3');
    expect(find.textContaining('A 15,00 €/h: 45,00 €'), findsOneWidget);
    await _tapAdd(tester);
    await tester.pumpAndSettle();
    final paid = saved.byId.values.firstWhere(
      (m) => m.kind == SavedMoveKind.paid,
    );
    expect(paid.cents, 4500);
    expect(find.text('36 h'), findsOneWidget);
  });

  testWidgets('cobrar sin tarifa se rechaza (RF-10)', (tester) async {
    await _open(tester, moves: [_before(SavedBox.own, 39)], withRate: false);
    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cobrar'));
    await _type(tester, 'Horas', '3');
    await _tapAdd(tester);
    await tester.pumpAndSettle();
    expect(
      find.text('Falta la tarifa normal en esa fecha.'),
      findsAtLeastNWidgets(1),
    );
    expect(saved.byId, hasLength(1));
  });

  testWidgets('apartar resta del mes y sube el cajón (RF-5)', (tester) async {
    await _open(
      tester,
      entries: [
        DayEntry(
          date: DateTime(2026, 11, 3),
          minutes: 600,
          kind: DayKind.normal,
        ),
      ],
    );
    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    await _type(tester, 'Horas', '3'); // Apartar y Mi reserva por defecto
    await _tapAdd(tester);
    await tester.pumpAndSettle();
    expect(find.text('3 h'), findsOneWidget);
    expect(money.overview.toCollectMinutes, 420);
    expect(money.overview.toCollectCents, 10500);
  });

  testWidgets('editar se guarda solo; un cambio que no cabe no se guarda', (
    tester,
  ) async {
    await _open(
      tester,
      moves: [
        _before(SavedBox.own, 39, id: 1),
        SavedMove(
          id: 2,
          box: SavedBox.own,
          kind: SavedMoveKind.timeOff,
          date: DateTime(2026, 11, 2),
          minutes: 120,
        ),
      ],
    );
    await tester.tap(find.text('Tiempo libre · Mi reserva'));
    await tester.pumpAndSettle();
    await _type(tester, 'Horas', '4');
    expect(saved.byId[2]!.minutes, 240);
    await _type(tester, 'Horas', '50');
    // Con «Tiempo libre» la ficha es más larga (020): el aviso queda abajo.
    const refused =
        'Solo hay 39 h en Mi reserva a esa fecha. Hasta entonces no se '
        'guarda.';
    await tester.scrollUntilVisible(
      find.text(refused),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text(refused), findsOneWidget);
    expect(saved.byId[2]!.minutes, 240);
  });

  testWidgets('borrar con Deshacer (RF-15)', (tester) async {
    await _open(tester, moves: [_before(SavedBox.own, 39, id: 1)]);
    await tester.tap(find.text('Horas de antes · Mi reserva'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Borrar'));
    await tester.pumpAndSettle();
    expect(saved.byId, isEmpty);
    expect(find.text('Borrado: Horas de antes, 39 h'), findsOneWidget);
    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(saved.byId[1]!.minutes, 39 * 60);
  });

  testWidgets('borrar una entrada ya gastada se rechaza (RF-4)', (
    tester,
  ) async {
    await _open(
      tester,
      moves: [
        _before(SavedBox.own, 39, id: 1),
        SavedMove(
          id: 2,
          box: SavedBox.own,
          kind: SavedMoveKind.timeOff,
          date: DateTime(2026, 11, 2),
          minutes: 120,
        ),
      ],
    );
    await tester.tap(find.text('Horas de antes · Mi reserva'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Borrar'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Esas horas de Mi reserva ya han salido. Quita antes la salida.',
      ),
      findsOneWidget,
    );
    expect(saved.byId, hasLength(2));
  });

  testWidgets('Apuntar avisa si un mes baja de lo apartado (RF-8)', (
    tester,
  ) async {
    calmAnimations(tester);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _makeMoney(
      entries: [
        DayEntry(
          date: DateTime(2026, 11, 18),
          minutes: 300,
          kind: DayKind.normal,
        ),
      ],
      moves: [
        SavedMove(
          box: SavedBox.own,
          kind: SavedMoveKind.setAside,
          date: DateTime(2026, 11, 18),
          minutes: 240,
        ),
      ],
    );
    await tester.pumpWidget(
      HoursAndVacationApp(repository: days, money: money, clock: () => _now),
    );
    await tester.pumpAndSettle();
    await _doubleTap(tester, find.bySemanticsLabel('Apuntar 2 horas'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Has apartado 4 h de este mes a Mi reserva. Quita antes ese apartado.',
      ),
      findsOneWidget,
    );
    expect(days.days.values.single.minutes, 300);
  });

  group('tamaños sin desbordes', () {
    for (final width in [360.0, 412.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('$width px, letra al 130 %, ${brightness.name}', (
          tester,
        ) async {
          await _open(
            tester,
            width: width,
            scale: 1.3,
            brightness: brightness,
            moves: [_before(SavedBox.company, 16), _before(SavedBox.own, 999)],
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Añadir'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cobrar'));
          await _type(tester, 'Horas', '999');
          expect(tester.takeException(), isNull);
          // Con el recordatorio y el botón de la jornada (020).
          await tester.tap(find.text('Tiempo libre'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('dia-completo')),
            100,
            scrollable: find
                .descendant(
                  of: find.byType(ListView).last,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(find.byKey(const ValueKey('dia-completo')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('Resumen y Hoja del mes (RF-5, RF-12, RF-19)', () {
    Future<void> openSummary(WidgetTester tester) async {
      calmAnimations(tester);
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _makeMoney(
        entries: [
          DayEntry(
            date: DateTime(2026, 11, 3),
            minutes: 600,
            kind: DayKind.normal,
          ),
        ],
        moves: [
          _before(SavedBox.company, 16),
          _before(SavedBox.own, 36),
          SavedMove(
            box: SavedBox.own,
            kind: SavedMoveKind.setAside,
            date: DateTime(2026, 11, 10),
            minutes: 180,
          ),
        ],
      );
      final extras = ExtrasController(
        repository: InMemoryExtrasRepository(),
        clock: () => _now,
      );
      await extras.load();
      await tester.pumpWidget(
        HoursAndVacationApp(
          repository: days,
          money: money,
          extras: extras,
          clock: () => _now,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resumen'));
      await tester.pumpAndSettle();
    }

    testWidgets('tarjeta con los cajones; «A cobrar» sin lo guardado', (
      tester,
    ) async {
      await openSummary(tester);
      expect(find.text('55 h · 825,00 €'), findsOneWidget);
      expect(find.textContaining('Posible'), findsNothing);
      // 10 h − 3 apartadas = 7 h a 15 €: 105 €, sin sumar lo guardado.
      expect(find.text('105,00 €'), findsWidgets);
      expect(money.overview.toCollectCents, 10500);
      await tester.tap(find.text('55 h · 825,00 €'));
      await tester.pumpAndSettle();
      // Abre Extra en la pestaña «Horas guardadas» (009, RF-4).
      expect(find.text('Apartar · Mi reserva'), findsOneWidget);
      expect(find.text('16 h'), findsOneWidget);
      expect(find.text('39 h'), findsOneWidget);
      // Y la otra pestaña sigue ahí.
      await tester.tap(find.text('Multas y extras'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Aún no hay multas ni extras'),
        findsOneWidget,
      );
    });

    testWidgets('la Hoja del mes enseña lo apartado', (tester) async {
      await openSummary(tester);
      await tester.tap(find.text('Noviembre 2026'));
      await tester.pumpAndSettle();
      expect(find.text('Apartadas a Mi reserva: −3 h'), findsOneWidget);
      expect(find.text('−45,00 €'), findsOneWidget);
      expect(find.text('7 h'), findsOneWidget);
    });

    testWidgets('sin horas guardadas no hay tarjeta', (tester) async {
      calmAnimations(tester);
      final plain = MoneyController(
        days: InMemoryDayEntryRepository(),
        money: InMemoryMoneyRepository(),
        clock: () => _now,
      );
      await plain.load();
      await tester.pumpWidget(
        HoursAndVacationApp(
          repository: InMemoryDayEntryRepository(),
          money: plain,
          clock: () => _now,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resumen'));
      await tester.pumpAndSettle();
      expect(find.text('Horas guardadas'), findsNothing);
    });
  });

  group('dinero del mes en Apuntar (009, RF-6 a RF-8)', () {
    Finder line() => find.byKey(const ValueKey('dinero-del-mes'));
    String text(WidgetTester tester) =>
        tester.widget<Semantics>(line()).properties.label!;

    Future<void> openLog(
      WidgetTester tester, {
      bool withRate = true,
      bool apart = true,
    }) async {
      calmAnimations(tester);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _makeMoney(
        withRate: withRate,
        entries: [
          DayEntry(
            date: DateTime(2026, 11, 3),
            minutes: 600,
            kind: DayKind.normal,
          ),
        ],
        moves: [
          if (apart)
            SavedMove(
              box: SavedBox.own,
              kind: SavedMoveKind.setAside,
              date: DateTime(2026, 11, 10),
              minutes: 180,
            ),
        ],
      );
      await tester.pumpWidget(
        HoursAndVacationApp(repository: days, money: money, clock: () => _now),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('10 h a 15 € menos 3 apartadas: 105,00 €', (tester) async {
      await openLog(tester);
      expect(text(tester), 'A cobrar este mes · 3 h fuera: 105,00 €');
      expect(find.text('105,00 €'), findsOneWidget);
    });

    testWidgets('un apunte rechazado por lo apartado quita «✓ Apuntado» '
        '(012, RF-5)', (tester) async {
      await openLog(tester);
      await tester.tap(find.text('Otro día'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(RegExp('^3 nov: Normal')));
      await tester.pumpAndSettle();
      // 10 h → 1 h, por debajo de las 3 h apartadas: no se guarda.
      await _doubleTap(tester, find.bySemanticsLabel('Apuntar 1 hora'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Quita antes ese apartado'), findsOneWidget);
      expect(find.byKey(const ValueKey('marca-apuntado')), findsNothing);
      expect(days.days.values.single.minutes, 600);
      await tester.pumpAndSettle();
    });

    testWidgets('va debajo de los botones de horas (012, RF-6)', (
      tester,
    ) async {
      await openLog(tester);
      final money = tester.getTopLeft(line()).dy;
      final other = tester.getBottomLeft(find.text('Otra')).dy;
      expect(money, greaterThan(other));
    });

    testWidgets('se actualiza al apuntar y se oculta con el ojo', (
      tester,
    ) async {
      await openLog(tester);
      await _doubleTap(tester, find.bySemanticsLabel('Apuntar 2 horas'));
      await tester.pumpAndSettle();
      expect(text(tester), 'A cobrar este mes · 3 h fuera: 135,00 €');
      await money.toggleHideAmounts();
      await tester.pumpAndSettle();
      expect(text(tester), 'A cobrar este mes · 3 h fuera: •••• €');
    });

    testWidgets('sin tarifa lo avisa; un mes sin horas da 0,00 €', (
      tester,
    ) async {
      await openLog(tester, withRate: false, apart: false);
      expect(text(tester), 'A cobrar este mes: 0,00 € (falta tarifa)');
      await tester.tap(find.text('Otro día'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mes anterior'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').first);
      await tester.pumpAndSettle();
      expect(text(tester), 'A cobrar este mes: 0,00 €');
    });

    testWidgets('un mes cobrado dice «Cobrado este mes»', (tester) async {
      await openLog(tester);
      await money.setStatus(
        const YearMonth(2026, 11),
        MonthStatus.paid,
        date: DateTime(2026, 11, 18),
      );
      await tester.pumpAndSettle();
      expect(text(tester), 'Cobrado este mes · 3 h fuera: 105,00 €');
    });
  });

  group('cambio por libre (022)', () {
    final nov3 = DayEntry(
      date: DateTime(2026, 11, 3),
      minutes: 600,
      kind: DayKind.normal,
    );

    testWidgets('desde la Hoja del mes, sin cajón; Resumen lo dice '
        '(RF-7 a RF-10, RF-12)', (tester) async {
      calmAnimations(tester);
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _makeMoney(
        entries: [nov3],
        moves: [
          _before(SavedBox.own, 10),
          SavedMove(
            box: SavedBox.own,
            kind: SavedMoveKind.setAside,
            date: DateTime(2026, 11, 4),
            minutes: 120,
          ),
        ],
      );
      await tester.pumpWidget(
        HoursAndVacationApp(repository: days, money: money, clock: () => _now),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resumen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Noviembre 2026'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('cambiar-por-libre')));
      await tester.pumpAndSettle();
      expect(find.text('Cajón'), findsNothing);
      expect(find.text('Fecha: 18 de noviembre de 2026'), findsOneWidget);
      expect(find.text('Día libre (opcional)'), findsOneWidget);
      await _type(tester, 'Horas', '3');
      await _tapAdd(tester);
      await tester.pumpAndSettle();

      // De vuelta en la Hoja: las dos líneas y 10 − 2 − 3 = 5 h.
      expect(find.text('Apartadas a Mi reserva: −2 h'), findsOneWidget);
      expect(find.text('Cambiadas por tiempo libre: −3 h'), findsOneWidget);
      expect(find.text('−45,00 €'), findsOneWidget);
      expect(find.text('5 h'), findsOneWidget);
      // Los cajones no cambian y «Compensadas» lo cuenta.
      expect(money.savedSummary.balances[SavedBox.own], 12 * 60);
      expect(money.savedSummary.compensatedMinutes, 180);

      await tester.tap(find.byTooltip('Atrás'));
      await tester.pumpAndSettle();
      expect(
        find.text('5 h · 2 h apartadas · 3 h a tiempo libre'),
        findsOneWidget,
      );
    });

    testWidgets('un mes entregado no ofrece el botón', (tester) async {
      calmAnimations(tester);
      await _makeMoney(entries: [nov3]);
      await money.setStatus(const YearMonth(2026, 11), MonthStatus.delivered);
      await tester.pumpWidget(
        HoursAndVacationApp(repository: days, money: money, clock: () => _now),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resumen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Noviembre 2026'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cambiar-por-libre')), findsNothing);
    });

    testWidgets('en la lista: sin cajón y con su día libre (RF-12); el día '
        'libre se quita (RF-8)', (tester) async {
      await _open(
        tester,
        entries: [nov3],
        moves: [
          SavedMove(
            id: 1,
            kind: SavedMoveKind.swap,
            date: DateTime(2026, 11, 10),
            minutes: 180,
            dayOff: DateTime(2026, 12, 7),
          ),
        ],
      );
      expect(find.text('Cambio por libre'), findsOneWidget);
      expect(find.text('10 nov 2026 · libre el 7 dic 2026'), findsOneWidget);
      expect(find.text('−3 h'), findsOneWidget);
      await tester.tap(find.text('Cambio por libre'));
      await tester.pumpAndSettle();
      expect(find.text('Día libre: 7 de diciembre de 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Quitar el día libre'));
      await tester.pumpAndSettle();
      expect(money.savedMoves.single.dayOff, isNull);
    });
  });
}
