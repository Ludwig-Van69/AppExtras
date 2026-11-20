import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/money.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/components/app_nav_bar.dart';
import 'package:horas_y_vacaciones/ui/money/money_controller.dart';

import '../../fakes/in_memory_day_entry_repository.dart';
import '../../fakes/in_memory_money_repository.dart';
import '../test_app.dart';

/// Miércoles 18 de noviembre de 2026. Todos los datos son inventados.
final _now = DateTime(2026, 11, 18, 10);

DayEntry _e(int y, int m, int d, int minutes, [DayKind k = DayKind.normal]) =>
    DayEntry(date: DateTime(y, m, d), minutes: minutes, kind: k);

final _rates = [
  Rate(DayKind.normal, DateTime(2020), 1500),
  Rate(DayKind.festive, DateTime(2020), 2000),
];

late MoneyController money;
var hidden = false;

Future<void> _open(
  WidgetTester tester,
  List<DayEntry> entries, {
  List<Rate>? rates,
  double width = 390,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  calmAnimations(tester);
  await tester.binding.setSurfaceSize(Size(width, 844));
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.platformDispatcher.clearAllTestValues();
  });
  final days = InMemoryDayEntryRepository(entries);
  final store = InMemoryMoneyRepository()..rateList.addAll(rates ?? _rates);
  hidden = false;
  money = MoneyController(
    days: days,
    money: store,
    clock: () => _now,
    loadHidden: () async => hidden,
    saveHidden: (v) async => hidden = v,
  );
  await money.load();
  await tester.pumpWidget(
    HoursAndVacationApp(repository: days, money: money, clock: () => _now),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(AppNavBar),
      matching: find.text('Métricas'),
    ),
  );
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

Finder _euroText() => find.byWidgetPredicate(
  (w) => w is Text && (w.data ?? '').contains(RegExp(r'\d €')),
);

/// La lista de la vista que se ve (la de las páginas va en horizontal).
Finder _vertical() => find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);

Future<void> _allYears(WidgetTester tester) async {
  await tester.tap(find.text('Todos los años'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('horas y euros a la vez, sin botón Horas/Euros (015, RF-2)', (
    tester,
  ) async {
    await _open(tester, [
      _e(2026, 11, 2, 120),
      _e(2026, 11, 7, 60, DayKind.festive),
    ]);
    expect(find.text('Euros'), findsNothing);
    expect(find.text('Últimos 12 meses'), findsNothing);
    expect(_text(tester, 'metricas-total'), '3 h');
    expect(_text(tester, 'metricas-total-euros'), '50,00 €');
    expect(find.text('Normales 2 h · 30,00 €'), findsOneWidget);
    expect(find.text('Festivas 1 h · 20,00 €'), findsOneWidget);
  });

  testWidgets('con «Ocultar importes», euros ocultos y horas visibles '
      '(015, RF-4)', (tester) async {
    await _open(tester, [_e(2026, 11, 2, 120)]);
    await money.toggleHideAmounts();
    await tester.pumpAndSettle();
    expect(_text(tester, 'metricas-total'), '2 h');
    expect(_text(tester, 'metricas-total-euros'), '•••• €');
    expect(_euroText(), findsNothing);
    await _allYears(tester);
    expect(_euroText(), findsNothing);
  });

  testWidgets('al tocar una barra: mes, horas, euros y el año anterior '
      '(015, RF-3)', (tester) async {
    await _open(tester, [_e(2026, 3, 10, 600), _e(2025, 3, 10, 480)]);
    expect(_text(tester, 'metricas-barra-elegida'), startsWith('Noviembre'));
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Marzo 2026')));
    await tester.pumpAndSettle();
    expect(
      _text(tester, 'metricas-barra-elegida'),
      'Marzo 2026 · 10 h · 150,00 € (2025: 8 h)',
    );
    expect(
      _text(tester, 'metricas-comparacion'),
      '+2 h · +30,00 € frente a 2025 a 18 de noviembre',
    );
  });

  testWidgets('horas antes de la primera tarifa: «aprox.» (015, RF-5)', (
    tester,
  ) async {
    await _open(
      tester,
      [_e(2023, 5, 4, 60), _e(2026, 5, 4, 60)],
      rates: [Rate(DayKind.normal, DateTime(2024), 1500)],
    );
    await _allYears(tester);
    expect(_text(tester, 'metricas-total-euros'), '30,00 € aprox.');
  });

  testWidgets('Todos los años: totales, récords, línea y lista; tocar un año '
      'abre su vista (015, RF-7 a RF-11)', (tester) async {
    await _open(tester, [
      _e(2024, 6, 3, 600),
      _e(2025, 3, 3, 1200),
      _e(2026, 2, 2, 480),
    ]);
    await _allYears(tester);
    expect(find.text('Total desde 2024'), findsOneWidget);
    expect(_text(tester, 'metricas-total'), '38 h');
    expect(find.byKey(const ValueKey('grafico-evolucion')), findsOneWidget);
    expect(_text(tester, 'evolucion-elegido'), startsWith('Noviembre 2026'));

    // Tocar el principio de la línea marca el primer mes.
    final chart = tester.getRect(
      find.byKey(const ValueKey('grafico-evolucion')),
    );
    await tester.tapAt(chart.centerLeft + const Offset(1, 0));
    await tester.pumpAndSettle();
    expect(_text(tester, 'evolucion-elegido'), 'Junio 2024 · 10 h · 150,00 €');

    await tester.scrollUntilVisible(
      find.text('Mes con más horas: Marzo 2025'),
      200,
      scrollable: _vertical(),
    );
    expect(find.text('Año con más horas: 2025'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.bySemanticsLabel(RegExp(r'^2025: ')),
      200,
      scrollable: _vertical(),
    );
    // Podio: 2025 oro, 2024 plata, 2026 bronce (018, RF-6, RF-7).
    expect(
      find.bySemanticsLabel(RegExp(r'^2025: .*primero en horas$')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^2024: .*segundo en horas$')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^2026: .*tercero en horas$')),
      findsOneWidget,
    );
    for (final place in [1, 2, 3]) {
      expect(find.byKey(ValueKey('trofeo-$place')), findsOneWidget);
    }
    await tester.tap(find.bySemanticsLabel(RegExp(r'^2025: ')));
    await tester.pumpAndSettle();
    expect(find.text('Total del año'), findsOneWidget);
    expect(_text(tester, 'metricas-total'), '20 h');
  });

  testWidgets('las flechas no pasan del año actual ni del primero y un año '
      'sin horas lo dice', (tester) async {
    await _open(tester, [_e(2024, 5, 6, 60)]);
    final next = find.ancestor(
      of: find.byTooltip('Año siguiente'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(next).onPressed, isNull);
    expect(find.text('Sin horas en este año'), findsOneWidget);
    await tester.tap(find.byTooltip('Año anterior'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Año anterior'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'metricas-total'), '1 h');
    final prev = find.ancestor(
      of: find.byTooltip('Año anterior'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(prev).onPressed, isNull);
  });

  testWidgets('la previsión dice «Estimación» (014, criterio 7)', (
    tester,
  ) async {
    await _open(tester, [_e(2026, 3, 10, 600)]);
    expect(find.text('Estimación de fin de año'), findsOneWidget);
  });

  testWidgets('deslizar pasa de Año a Todos los años y vuelve (017, RF-1)', (
    tester,
  ) async {
    await _open(tester, [_e(2025, 3, 3, 600), _e(2026, 3, 3, 120)]);
    expect(find.text('Total del año'), findsOneWidget);
    await tester.fling(find.text('Total del año'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Total desde 2025'), findsOneWidget);
    final segments = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );
    expect(segments.selected, {true});
    await tester.fling(
      find.text('Total desde 2025'),
      const Offset(300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('Total del año'), findsOneWidget);
  });

  testWidgets('deslizar sobre el gráfico recorre los meses, no cambia de '
      'vista (017, RF-2)', (tester) async {
    await _open(tester, [_e(2025, 3, 3, 600), _e(2026, 3, 3, 120)]);
    await _allYears(tester);
    final chart = find.byKey(const ValueKey('grafico-evolucion'));
    await tester.drag(chart, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Total desde 2025'), findsOneWidget);
    expect(_text(tester, 'evolucion-elegido'), startsWith('Marzo 2025'));
  });

  testWidgets('barras con media de 12 meses y su leyenda (017, RF-3 a '
      'RF-5)', (tester) async {
    await _open(tester, [
      for (var m = 1; m <= 11; m++) _e(2025, m, 3, 120),
      _e(2025, 12, 3, 240),
      _e(2026, 2, 2, 60),
    ]);
    await _allYears(tester);
    expect(find.byKey(const ValueKey('leyenda-media')), findsOneWidget);
    // Noviembre de 2026: media de diciembre de 2025 a noviembre de 2026.
    expect(_text(tester, 'evolucion-elegido'), 'Noviembre 2026 · 0 h · 0,00 €');
    expect(_text(tester, 'evolucion-media'), 'Media de 12 meses: 0,42 h');
  });

  testWidgets('con menos de 12 meses no hay media (017, RF-5)', (tester) async {
    await _open(tester, [_e(2026, 3, 3, 120)]);
    await _allYears(tester);
    expect(find.byKey(const ValueKey('leyenda-media')), findsNothing);
    expect(find.byKey(const ValueKey('evolucion-media')), findsNothing);
  });

  testWidgets('muchos años en la línea a 360 px no fallan', (tester) async {
    await _open(tester, [
      for (var y = 2014; y <= 2026; y++) _e(y, 3, 10, 120),
    ], width: 360);
    await _allYears(tester);
    expect(find.byKey(const ValueKey('grafico-evolucion')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 412.0]) {
    for (final b in Brightness.values) {
      testWidgets('sin desbordes a $width px, letra al 130 %, ${b.name}', (
        tester,
      ) async {
        await _open(
          tester,
          [
            // Cifras grandes (miles de euros) para probar los anchos.
            for (var d = 1; d <= 28; d++) _e(2026, 3, d, 900),
            for (var d = 1; d <= 28; d++) _e(2025, 3, d, 600),
            for (var d = 1; d <= 28; d++) _e(2023, 3, d, 600),
            _e(2026, 11, 7, 600, DayKind.festive),
          ],
          rates: [
            Rate(DayKind.normal, DateTime(2024), 1500),
            Rate(DayKind.festive, DateTime(2024), 2000),
          ],
          width: width,
          scale: 1.3,
          brightness: b,
        );
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView), const Offset(0, 2000));
        await tester.pumpAndSettle();
        await _allYears(tester);
        await tester.drag(find.byType(ListView), const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
