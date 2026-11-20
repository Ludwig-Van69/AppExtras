import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_settings.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/help_screen.dart';

import '../../fakes/fake_backup_service.dart';
import '../../fakes/in_memory_day_entry_repository.dart';
import '../test_app.dart';

final _now = DateTime(2026, 11, 6, 18);

Future<FakeBackupService> _open(
  WidgetTester tester, {
  BackupSettings settings = const BackupSettings(),
  double width = 360,
  double scale = 1,
}) async {
  final backup = FakeBackupService(settings: settings);
  calmAnimations(tester);
  await tester.binding.setSurfaceSize(Size(width, 780));
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.platformDispatcher.clearAllTestValues();
  });
  await tester.pumpWidget(
    HoursAndVacationApp(
      repository: InMemoryDayEntryRepository(),
      backup: backup,
      clock: () => _now,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Ajustes'));
  await tester.pumpAndSettle();
  return backup;
}

void main() {
  testWidgets('sin copias ni festivos solo hay Ayuda (el catálogo no sale)', (
    tester,
  ) async {
    calmAnimations(tester);
    await tester.pumpWidget(
      HoursAndVacationApp(
        repository: InMemoryDayEntryRepository(),
        clock: () => _now,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('Copias y exportación'), findsNothing);
    expect(find.text('Festivos'), findsNothing);
    expect(find.text('Ayuda'), findsOneWidget);
    expect(find.text('Catálogo de piezas'), findsNothing);
  });

  testWidgets('la entrada de copias resume su estado', (tester) async {
    await _open(tester);
    expect(find.text('Aún sin carpeta'), findsOneWidget);
  });

  testWidgets('con la última copia buena la enseña', (tester) async {
    await _open(
      tester,
      settings: BackupSettings(
        folder: 'content://x/tree/primary%3ADocuments',
        lastSuccess: DateTime(2026, 11, 6, 9, 5),
      ),
    );
    expect(find.text('Última copia: hoy, 09:05'), findsOneWidget);
  });

  testWidgets('si la última copia falló, lo dice', (tester) async {
    await _open(
      tester,
      settings: const BackupSettings(
        folder: 'content://x/tree/primary%3ADocuments',
        lastError: 'Sin espacio',
      ),
    );
    expect(find.text('La última copia falló'), findsOneWidget);
  });

  testWidgets('se puede volver a Apuntar y a Ajustes sin perder nada', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.text('Ayuda'));
    await tester.pumpAndSettle();
    expect(find.byType(HelpScreen), findsOneWidget);
  });

  for (final width in [360.0, 412.0]) {
    testWidgets('cabe a ${width.toInt()} px con letra al 130 %', (
      tester,
    ) async {
      await _open(tester, width: width, scale: 1.3);
      expect(tester.takeException(), isNull);
      expect(find.text('Ajustes'), findsOneWidget); // el título
    });
  }
}
