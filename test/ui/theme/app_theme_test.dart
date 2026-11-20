import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/theme/app_colors.dart';
import 'package:horas_y_vacaciones/ui/theme/app_theme.dart';

/// Pantalla de prueba que muestra el fondo del tema y permite cambiarlo.
class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) {
    final controller = ThemeScope.of(context);
    return Scaffold(
      body: Column(
        children: [
          Text('fondo ${context.colors.background.toARGB32()}'),
          for (final choice in ThemeChoice.values)
            TextButton(
              onPressed: () => controller.value = choice,
              child: Text(choice.label),
            ),
        ],
      ),
    );
  }
}

Color _background(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(_Probe)))
        .extension<AppColors>()!
        .background;

void main() {
  testWidgets('Según el móvil sigue el modo oscuro del sistema (RF-2)', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const HoursAndVacationApp(home: _Probe()));
    await tester.pumpAndSettle();
    expect(_background(tester), AppColors.dark.background);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(_background(tester), AppColors.light.background);
  });

  testWidgets('Claro y Oscuro se imponen al móvil (RF-3)', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const HoursAndVacationApp(home: _Probe()));
    await tester.tap(find.text('Claro'));
    await tester.pumpAndSettle();
    expect(_background(tester), AppColors.light.background);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();
    expect(_background(tester), AppColors.dark.background);
  });

  test('Los dos temas llevan su paleta (RF-1)', () {
    expect(AppTheme.light().extension<AppColors>(), AppColors.light);
    expect(AppTheme.dark().extension<AppColors>(), AppColors.dark);
  });

  test(
    'Cifras y títulos en Bricolage Grotesque y textos en Figtree (RF-7)',
    () {
      for (final s in [
        AppText.hero,
        AppText.display,
        AppText.title,
        AppText.figure,
      ]) {
        expect(s.fontFamily, Fonts.display);
      }
      for (final s in [
        AppText.body,
        AppText.bodyStrong,
        AppText.label,
        AppText.caption,
      ]) {
        expect(s.fontFamily, Fonts.body);
      }
      expect(AppTheme.light().textTheme.bodyLarge!.fontFamily, Fonts.body);
    },
  );

  test('Todas las cifras usan números de ancho fijo (RF-9)', () {
    for (final s in [
      AppText.hero,
      AppText.display,
      AppText.title,
      AppText.figure,
      AppText.body,
      AppText.label,
      AppText.caption,
    ]) {
      expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
    }
  });
}
