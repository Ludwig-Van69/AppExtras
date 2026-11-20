import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/ui/theme/app_theme.dart';

/// Envuelve una pieza con el tema de la app para probarla.
Widget testApp(
  Widget child, {
  Brightness brightness = Brightness.light,
  bool reduceMotion = false,
  double textScale = 1,
}) {
  return MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

/// Desactiva las animaciones como lo haría el ajuste del móvil. Se usa en
/// las pruebas de pantallas completas, donde el agua se mece sin parar.
void calmAnimations(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}
