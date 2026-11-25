import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/ui/help_screen.dart';
import 'package:horas_y_vacaciones/ui/theme/app_theme.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 20000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const HelpScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('explica cómo usar la app en dos móviles (025, RF-19)', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Dos móviles'), findsOneWidget);
    final text = find.textContaining('Puedes usar la app en dos móviles');
    expect(text, findsOneWidget);
    final body = tester.widget<Text>(text).data!;
    for (final part in [
      'misma carpeta',
      '«Enviar y recibir» en ambos',
      '«Hay cambios de…»',
      '«Ver»',
      'por turnos',
      '«antes de restaurar»',
    ]) {
      expect(body, contains(part), reason: part);
    }
  });

  testWidgets('Syncthing: «Solo enviar» con un móvil, «Enviar y recibir» con '
      'dos (025, RF-19)', (tester) async {
    await open(tester);
    final body = tester
        .widget<Text>(find.textContaining('Syncthing es una app gratuita'))
        .data!;
    expect(body, contains('«Solo enviar»'));
    expect(body, contains('«Enviar y recibir»'));
    expect(body, contains('«Solo recibir»'));
  });

  testWidgets('Copias y Restaurar hablan del móvil de cada copia (025)', (
    tester,
  ) async {
    await open(tester);
    expect(
      find.textContaining('Guarda las 10 más recientes de este móvil'),
      findsOneWidget,
    );
    expect(find.textContaining('de qué móvil es'), findsOneWidget);
  });
}
