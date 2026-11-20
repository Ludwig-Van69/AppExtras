import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/ui/components/motion_bits.dart';
import 'package:horas_y_vacaciones/ui/theme/tokens.dart';

Widget _app(Widget child, {bool reduced = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(body: Center(child: child)),
  ),
);

double _opacity(WidgetTester t) =>
    t.widget<Opacity>(find.byType(Opacity).first).opacity;

double _scale(WidgetTester t) => t
    .widget<Transform>(
      find.descendant(
        of: find.byType(AppearOnce),
        matching: find.byType(Transform),
      ),
    )
    .transform
    .storage[0];

void main() {
  testWidgets('AppearOnce: sale de 0,9 y transparente, nunca de cero, '
      'y espera su turno (bloque G)', (tester) async {
    await tester.pumpWidget(
      _app(
        const AppearOnce(
          delay: Duration(milliseconds: 120),
          child: Text('trofeo'),
        ),
      ),
    );
    expect(_opacity(tester), 0);
    expect(_scale(tester), closeTo(0.9, 0.001));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_opacity(tester), 0, reason: 'aún en su espera');
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    expect(_scale(tester), 1);
    // Toda la aparición cabe en el presupuesto: espera + 250 ms.
    expect(Motion.appear, lessThanOrEqualTo(const Duration(milliseconds: 300)));
  });

  testWidgets('AppearOnce con animaciones reducidas: solo fundido, sin '
      'espera ni crecimiento', (tester) async {
    await tester.pumpWidget(
      _app(
        const AppearOnce(
          delay: Duration(milliseconds: 120),
          child: Text('trofeo'),
        ),
        reduced: true,
      ),
    );
    expect(_scale(tester), 1);
    await tester.pump(const Duration(milliseconds: 80));
    expect(_opacity(tester), greaterThan(0));
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
  });

  testWidgets('FadeSwap funde el contenido al cambiar y deja solo el nuevo', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const FadeSwap(value: 1, child: Text('Entregado'))),
    );
    await tester.pumpWidget(
      _app(const FadeSwap(value: 2, child: Text('Cobrado'))),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Entregado'), findsOneWidget);
    expect(find.text('Cobrado'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Entregado'), findsNothing);
    expect(find.text('Cobrado'), findsOneWidget);
  });
}
