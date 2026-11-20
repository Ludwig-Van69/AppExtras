import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_settings.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/backup/backup_notice.dart';

import '../../fakes/fake_backup_service.dart';
import '../../fakes/in_memory_day_entry_repository.dart';
import '../test_app.dart';

/// Apuntar y borrar piden dos toques seguidos (013, RF-1 a RF-3).
Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// Viernes 6 de noviembre de 2026. Todos los datos son inventados.
final _now = DateTime(2026, 11, 6, 18);
const _folder =
    'content://com.android.externalstorage.documents/tree/'
    'primary%3ADocuments%2FHoras';

late FakeBackupService backup;
late InMemoryDayEntryRepository repo;

Future<void> _open(
  WidgetTester tester, {
  BackupSettings settings = const BackupSettings(),
  Iterable<DayEntry> days = const [],
  double width = 390,
  double scale = 1,
}) async {
  backup = FakeBackupService(settings: settings);
  repo = InMemoryDayEntryRepository(days);
  calmAnimations(tester);
  await tester.binding.setSurfaceSize(Size(width, 780));
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.platformDispatcher.clearAllTestValues();
  });
  await tester.pumpWidget(
    HoursAndVacationApp(repository: repo, backup: backup, clock: () => _now),
  );
  await tester.pumpAndSettle();
}

DayEntry _entry(int minutes) => DayEntry(
  date: DateTime(2026, 11, 6),
  minutes: minutes,
  kind: DayKind.normal,
);

const _good = BackupSettings(folder: _folder, dirty: false);

void main() {
  group('avisos bajo el motivo', () {
    testWidgets('sin carpeta: aviso con «Elegir carpeta» (RF-3)', (
      tester,
    ) async {
      await _open(tester);
      expect(find.text('Tus horas aún no tienen copia'), findsOneWidget);
      await tester.tap(find.text('Elegir carpeta'));
      await tester.pumpAndSettle();
      expect(backup.calls, ['chooseFolder']);
      // Al resolverse, desaparece.
      expect(find.text('Tus horas aún no tienen copia'), findsNothing);
      expect(find.byType(BackupNotice), findsOneWidget);
    });

    testWidgets('si elegir carpeta se cancela, el aviso sigue', (tester) async {
      await _open(tester);
      backup.folderToPick = null;
      await tester.tap(find.text('Elegir carpeta'));
      await tester.pumpAndSettle();
      expect(find.text('Tus horas aún no tienen copia'), findsOneWidget);
    });

    testWidgets(
      'copia fallida: aviso con «Revisar» que lleva a copias (RF-8)',
      (tester) async {
        await _open(
          tester,
          settings: _good.copyWith(lastError: () => 'Sin espacio.'),
        );
        expect(find.text('No se ha podido hacer la copia'), findsOneWidget);
        await tester.tap(find.text('Revisar'));
        await tester.pumpAndSettle();
        expect(find.text('Copias y exportación'), findsOneWidget);
        expect(
          find.text('La última copia falló. Sin espacio.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('con todo en orden no hay aviso', (tester) async {
      await _open(tester, settings: _good);
      expect(find.text('Tus horas aún no tienen copia'), findsNothing);
      expect(find.text('No se ha podido hacer la copia'), findsNothing);
      expect(find.text('Elegir carpeta'), findsNothing);
      expect(find.text('Revisar'), findsNothing);
    });

    testWidgets('el aviso desaparece al resolverse el fallo', (tester) async {
      await _open(
        tester,
        settings: _good.copyWith(lastError: () => 'Sin espacio.'),
      );
      backup.settings = backup.settings.copyWith(lastError: () => null);
      await tester.pump();
      expect(find.text('No se ha podido hacer la copia'), findsNothing);
    });

    for (final width in [360.0, 412.0]) {
      testWidgets('cabe a ${width.toInt()} px con letra al 130 %', (
        tester,
      ) async {
        await _open(tester, width: width, scale: 1.3);
        expect(tester.takeException(), isNull);
        expect(find.text('Elegir carpeta'), findsOneWidget);
      });
    }
  });

  group('menú y ciclo de vida', () {
    testWidgets('Ajustes lleva a «Copias y exportación»', (tester) async {
      await _open(tester);
      await tester.tap(find.byTooltip('Ajustes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copias y exportación'));
      await tester.pumpAndSettle();
      expect(find.text('Hacer copia ahora'), findsOneWidget);
    });

    testWidgets('guardar un día avisa a las copias (RF-4)', (tester) async {
      await _open(tester, settings: _good);
      await _doubleTap(tester, find.bySemanticsLabel('Apuntar 2 horas'));
      await tester.pumpAndSettle();
      expect(backup.calls, contains('markChanged'));
    });

    testWidgets('al pasar a segundo plano, pide la copia (RF-4)', (
      tester,
    ) async {
      await _open(tester, settings: _good);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(backup.calls, ['onLeavingApp']);
    });

    testWidgets('al volver a primer plano no copia', (tester) async {
      await _open(tester, settings: _good);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(backup.calls, isEmpty);
    });

    testWidgets(
      'tras restaurar, la pantalla muestra los datos restaurados (RF-14)',
      (tester) async {
        await _open(tester, settings: _good, days: [_entry(60)]);
        expect(find.text('1 h'), findsWidgets);
        // Se simula una restauración: cambian los datos y sube el contador.
        backup.onRestored = () => repo.days['2026-11-06'] = _entry(150);
        backup.listing = [listing(DateTime(2026, 11, 3, 9, 5), 1)];
        await tester.tap(find.byTooltip('Ajustes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copias y exportación'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restaurar una copia'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('El 3 de noviembre, 09:05'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restaurar').last);
        await tester.pumpAndSettle();

        expect(find.text('Viernes, 6 de noviembre'), findsOneWidget);
        expect(find.text('2,5 h'), findsWidgets);
      },
    );
  });
}
