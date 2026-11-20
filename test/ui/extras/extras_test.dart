import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/extras.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/extras/extras_controller.dart';
import 'package:horas_y_vacaciones/ui/money/money_controller.dart';

import '../../fakes/in_memory_day_entry_repository.dart';
import '../../fakes/in_memory_extras_repository.dart';
import '../../fakes/in_memory_money_repository.dart';
import '../test_app.dart';

/// Lunes 16 de noviembre de 2026. Todos los datos son inventados.
final _now = DateTime(2026, 11, 16, 10);

late InMemoryExtrasRepository repo;
late ExtrasController extras;
late MoneyController money;

ExtraItem _item(
  ExtraType t,
  int cents,
  String concept, {
  int day = 2,
  ExtraStatus status = ExtraStatus.pending,
}) => ExtraItem(
  type: t,
  date: DateTime(2026, 11, day),
  cents: cents,
  concept: concept,
  status: status,
  closedOn: status == ExtraStatus.closed ? DateTime(2026, 11, 10) : null,
);

Future<void> _open(
  WidgetTester tester, {
  List<ExtraItem> items = const [],
  double width = 390,
  double scale = 1,
}) async {
  calmAnimations(tester);
  await tester.binding.setSurfaceSize(Size(width, 800));
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.platformDispatcher.clearAllTestValues();
  });
  repo = InMemoryExtrasRepository(items);
  extras = ExtrasController(repository: repo, clock: () => _now);
  await extras.load();
  var hidden = false;
  money = MoneyController(
    days: InMemoryDayEntryRepository(),
    money: InMemoryMoneyRepository(),
    clock: () => _now,
    loadHidden: () async => hidden,
    saveHidden: (v) async => hidden = v,
  );
  await money.load();
  await tester.pumpWidget(
    HoursAndVacationApp(
      repository: InMemoryDayEntryRepository(),
      money: money,
      extras: extras,
      clock: () => _now,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Extra'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sin apuntes lo dice y ofrece «Añadir» (RF-1)', (tester) async {
    await _open(tester);
    expect(find.text('Multas y extras'), findsOneWidget);
    expect(find.textContaining('Aún no hay multas ni extras'), findsOneWidget);
    expect(find.text('Añadir'), findsOneWidget);
  });

  testWidgets('añadir una multa: Multa y hoy por defecto (RF-2, RF-3)', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    expect(find.text('Fecha: 16 de noviembre de 2026'), findsOneWidget);

    // Sin importe ni concepto no se guarda y dice qué falta.
    await tester.tap(find.widgetWithText(FilledButton, 'Añadir'));
    await tester.pumpAndSettle();
    expect(find.text(ExtraProblem.amount.message), findsOneWidget);
    expect(repo.byId, isEmpty);

    await tester.enterText(find.widgetWithText(TextField, 'Importe'), '100');
    await tester.tap(find.widgetWithText(FilledButton, 'Añadir'));
    await tester.pumpAndSettle();
    expect(find.text(ExtraProblem.concept.message), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Concepto'),
      'Multa velocidad',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Añadir'));
    await tester.pumpAndSettle();
    final saved = repo.byId.values.single;
    expect(saved.type, ExtraType.fine);
    expect(saved.cents, 10000);
    expect(saved.date, DateTime(2026, 11, 16));
    expect(saved.status, ExtraStatus.pending);
    expect(find.text('Multa velocidad'), findsOneWidget);
    expect(find.text('−100,00 €'), findsNWidgets(2)); // total y fila
  });

  testWidgets('añadir un extra con céntimos', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extra').last);
    await tester.enterText(find.widgetWithText(TextField, 'Importe'), '12,5');
    await tester.enterText(
      find.widgetWithText(TextField, 'Concepto'),
      'Dieta viaje',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Añadir'));
    await tester.pumpAndSettle();
    expect(repo.byId.values.single.type, ExtraType.bonus);
    expect(repo.byId.values.single.cents, 1250);
    expect(find.text('+12,50 €'), findsNWidgets(2));
  });

  testWidgets('totales pendientes y orden de la lista (RF-6, RF-7)', (
    tester,
  ) async {
    await _open(
      tester,
      items: [
        _item(ExtraType.fine, 10000, 'Multa velocidad', day: 1),
        _item(ExtraType.bonus, 5000, 'Dieta viaje', day: 3),
        _item(
          ExtraType.fine,
          9900,
          'Multa anulada',
          day: 9,
          status: ExtraStatus.cancelled,
        ),
        _item(
          ExtraType.bonus,
          2000,
          'Plus cobrado',
          day: 5,
          status: ExtraStatus.closed,
        ),
      ],
    );
    expect(find.text('+50,00 €'), findsNWidgets(2));
    expect(find.text('−100,00 €'), findsNWidgets(2));
    final order = [
      'Dieta viaje',
      'Multa velocidad',
      'Multa anulada',
      'Plus cobrado',
    ].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
    expect(order, [...order]..sort());
    expect(find.textContaining('Anulada'), findsOneWidget);
    expect(find.textContaining('Cobrado'), findsOneWidget);
  });

  testWidgets('editar se guarda solo; cambiar de estado pide la fecha '
      '(RF-4, RF-5)', (tester) async {
    await _open(
      tester,
      items: [_item(ExtraType.fine, 10000, 'Multa velocidad')],
    );
    await tester.tap(find.text('Multa velocidad'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Importe'), '80');
    await tester.pump();
    expect(repo.byId.values.single.cents, 8000);

    // Un importe vacío no se guarda: se queda el último bueno.
    await tester.enterText(find.widgetWithText(TextField, 'Importe'), '');
    await tester.pump();
    expect(repo.byId.values.single.cents, 8000);
    expect(find.textContaining('Hasta entonces no se guarda'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Importe'), '80');
    await tester.pump();

    await tester.tap(find.text('Descontada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ACEPTAR'));
    await tester.pumpAndSettle();
    final e = repo.byId.values.single;
    expect(e.status, ExtraStatus.closed);
    expect(e.closedOn, DateTime(2026, 11, 16));
    expect(find.text('Descontada el 16 nov 2026'), findsOneWidget);

    await tester.tap(find.text('Anulada'));
    await tester.pumpAndSettle();
    expect(repo.byId.values.single.status, ExtraStatus.cancelled);
    expect(repo.byId.values.single.closedOn, isNull);
  });

  testWidgets('borrar con Deshacer (RF-5)', (tester) async {
    await _open(tester, items: [_item(ExtraType.bonus, 5000, 'Dieta viaje')]);
    await tester.tap(find.text('Dieta viaje'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Borrar'));
    await tester.pumpAndSettle();
    expect(repo.byId, isEmpty);
    expect(find.text('Extra borrado: Dieta viaje'), findsOneWidget);
    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(repo.byId.values.single.concept, 'Dieta viaje');
    expect(find.text('Dieta viaje'), findsOneWidget);
  });

  testWidgets('ocultar importes tapa todos los euros (RF-8)', (tester) async {
    await _open(
      tester,
      items: [_item(ExtraType.fine, 10000, 'Multa velocidad')],
    );
    await tester.tap(find.byTooltip('Ocultar importes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('100,00'), findsNothing);
    expect(find.text('−•••• €'), findsNWidgets(2));
    expect(money.hideAmounts, isTrue);
  });

  testWidgets('si falla el guardado, lo dice', (tester) async {
    await _open(
      tester,
      items: [_item(ExtraType.fine, 10000, 'Multa velocidad')],
    );
    repo.failWrites = true;
    await tester.tap(find.text('Multa velocidad'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Borrar'));
    await tester.pumpAndSettle();
    expect(repo.byId, hasLength(1));
    // La ficha sigue abierta, lo dice y no ofrece deshacer un borrado que
    // no ha ocurrido.
    expect(find.byTooltip('Borrar'), findsOneWidget);
    expect(find.textContaining('No se ha podido guardar'), findsOneWidget);
    expect(find.text('Deshacer'), findsNothing);
  });

  testWidgets('pronto pago, la paga la empresa y primera del año (019)', (
    tester,
  ) async {
    await _open(
      tester,
      items: [
        _item(ExtraType.fine, 15000, 'Multa aparcamiento', day: 2),
        _item(ExtraType.fine, 10000, 'Multa velocidad', day: 9),
      ],
    );
    // La primera del año lleva su marca; la otra, no (RF-3).
    expect(
      find.byKey(const ValueKey('marca-Primera del año-1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('marca-Primera del año-2')), findsNothing);
    expect(find.text('−250,00 €'), findsOneWidget);

    // Pronto pago: cuenta la mitad y se ve el completo tachado (RF-1, RF-2).
    await tester.tap(find.text('Multa velocidad'));
    await tester.pumpAndSettle();
    expect(find.text('Pagada en plazo: cuenta la mitad.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pronto-pago')));
    await tester.pumpAndSettle();
    expect(repo.byId[2]!.earlyPayment, isTrue);
    expect(find.text('Cuenta 50,00 €.'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tachado-2')), findsOneWidget);
    expect(find.text('−50,00 €'), findsOneWidget);
    expect(find.text('−200,00 €'), findsOneWidget); // 150 + 50

    // La paga la empresa: deja de restar (RF-4).
    await tester.tap(find.text('Multa aparcamiento'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paga-empresa')));
    await tester.pumpAndSettle();
    expect(repo.byId[1]!.companyPays, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('marca-La paga la empresa-1')),
      findsOneWidget,
    );
    expect(find.text('−50,00 €'), findsNWidgets(2)); // total y la multa

    // Ya descontada, los interruptores no se pueden cambiar (RF-5).
    await tester.tap(find.text('Multa velocidad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descontada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ACEPTAR'));
    await tester.pumpAndSettle();
    final sw = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('pronto-pago')),
    );
    expect(sw.onChanged, isNull);
  });

  testWidgets('un extra no tiene los interruptores', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Añadir'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pronto-pago')), findsOneWidget);
    await tester.tap(find.text('Extra').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pronto-pago')), findsNothing);
    expect(find.byKey(const ValueKey('paga-empresa')), findsNothing);
  });

  for (final width in [360.0, 412.0]) {
    testWidgets('cabe a ${width.toInt()} px con letra al 130 %', (
      tester,
    ) async {
      await _open(
        tester,
        width: width,
        scale: 1.3,
        items: [
          // Con todas las marcas y el importe tachado (019).
          _item(
            ExtraType.fine,
            maxExtraCents,
            'x' * 60,
          ).copyWith(earlyPayment: true, companyPays: true),
          _item(
            ExtraType.fine,
            maxExtraCents - 1,
            'y' * 60,
            day: 3,
          ).copyWith(earlyPayment: true),
          _item(
            ExtraType.bonus,
            maxExtraCents,
            'Dieta',
            status: ExtraStatus.closed,
          ),
        ],
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('x' * 60),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('x' * 60));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
