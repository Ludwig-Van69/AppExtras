import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/ui/components/big_hours.dart';
import 'package:horas_y_vacaciones/ui/components/confirm_dialog.dart';
import 'package:horas_y_vacaciones/ui/components/info_button.dart';
import 'package:horas_y_vacaciones/ui/components/state_message.dart';
import 'package:horas_y_vacaciones/ui/components/undo.dart';

import '../test_app.dart';

/// Pantalla mínima con el sistema de edición: borrar las horas y deshacer.
class _Day extends StatefulWidget {
  const _Day();

  @override
  State<_Day> createState() => _DayState();
}

class _DayState extends State<_Day> {
  int minutes = 150;

  @override
  Widget build(BuildContext context) {
    return BigHours(
      minutes: minutes,
      onDelete: () {
        final previous = minutes;
        setState(() => minutes = 0);
        showUndo(
          context,
          message: 'Horas borradas',
          onUndo: () => setState(() => minutes = previous),
        );
      },
    );
  }
}

void main() {
  testWidgets('Borrar deja el día a 0 sin confirmar y avisa (RF-22)', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(const _Day()));
    await tester.tap(find.byTooltip('Borrar las horas del día'));
    // La cifra cuenta hasta 0 antes de quedarse quieta (RF-28).
    await tester.pumpAndSettle();
    expect(find.text('0'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Horas borradas'), findsOneWidget);
    expect(find.text('Deshacer'), findsOneWidget);
  });

  testWidgets('Deshacer recupera el valor y oculta el aviso (RF-21)', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(const _Day()));
    await tester.tap(find.byTooltip('Borrar las horas del día'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(find.text('2,5'), findsOneWidget);
    expect(find.text('Horas borradas'), findsNothing);
  });

  testWidgets('El aviso se va solo a los 5 segundos (RF-20)', (tester) async {
    await tester.pumpWidget(testApp(const _Day()));
    await tester.tap(find.byTooltip('Borrar las horas del día'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Horas borradas'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Horas borradas'), findsNothing);
  });

  group('Confirmación de borrado (RF-23)', () {
    bool? result;

    Future<void> open(WidgetTester tester) async {
      result = null;
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await confirmDelete(
                context,
                title: '¿Borrar la copia del 3 de noviembre?',
                message:
                    'Se borrará el archivo de copia. No se puede deshacer.',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(
        find.text('Se borrará el archivo de copia. No se puede deshacer.'),
        findsOneWidget,
      );
    }

    testWidgets('Borrar confirma', (tester) async {
      await open(tester);
      await tester.tap(find.text('Borrar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(result, isTrue);
    });

    testWidgets('Cancelar no borra', (tester) async {
      await open(tester);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(result, isFalse);
    });
  });

  testWidgets('El botón ⓘ abre su explicación', (tester) async {
    await tester.pumpWidget(
      testApp(
        const InfoButton(
          title: 'Horas en la bolsa',
          text: 'Son horas guardadas para tiempo libre o para cobrar más adelante.',
        ),
      ),
    );
    await tester.tap(find.byTooltip('Más información: Horas en la bolsa'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Son horas guardadas para tiempo libre o para cobrar más adelante.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('un ⓘ largo con letra grande se desplaza sin cortarse', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearAllTestValues();
    });
    await tester.pumpWidget(
      testApp(
        InfoButton(title: 'Largo', text: 'Texto de ayuda muy largo. ' * 40),
      ),
    );
    await tester.tap(find.byTooltip('Más información: Largo'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Estados vacío, cargando y error con texto de qué hacer (RF-19)',
    (tester) async {
      var retried = false;
      await tester.pumpWidget(
        testApp(
          Column(
            children: [
              const StateMessage.empty(
                title: 'Aún no hay horas',
                message: 'Toca unas horas abajo para apuntar las de hoy.',
              ),
              const StateMessage.loading(message: 'Cargando tus horas…'),
              StateMessage.error(
                title: 'No se ha podido leer la copia',
                message: 'Elige otra carpeta o vuelve a intentarlo.',
                actionLabel: 'Reintentar',
                onAction: () => retried = true,
              ),
            ],
          ),
        ),
      );
      expect(
        find.text('Toca unas horas abajo para apuntar las de hoy.'),
        findsOneWidget,
      );
      // «Cargando» solo sale si tarda: un instante no parpadea.
      expect(find.text('Cargando tus horas…'), findsNothing);
      await tester.pump(loadingDelay);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Cargando tus horas…'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      expect(retried, isTrue);
    },
  );
}
