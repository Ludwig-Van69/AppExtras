import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_settings.dart';
import 'package:horas_y_vacaciones/data/backup_diff.dart';
import 'package:horas_y_vacaciones/domain/backup_names.dart';
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/extras.dart';
import 'package:horas_y_vacaciones/ui/theme/app_theme.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/backup/backup_controller.dart';
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
    testWidgets('sin carpeta ni copia compartida: «Hacer copia» lleva a '
        'Copias (023, RF-6)', (tester) async {
      await _open(tester);
      expect(find.text('Tus horas aún no tienen copia'), findsOneWidget);
      await tester.tap(find.text('Hacer copia'));
      await tester.pumpAndSettle();
      expect(find.text('Copias y exportación'), findsOneWidget);
      expect(find.text('Compartir copia'), findsOneWidget);
      // Al compartir desde allí, el aviso desaparece.
      await tester.tap(find.text('Compartir copia'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Atrás'));
      await tester.pumpAndSettle();
      expect(find.text('Tus horas aún no tienen copia'), findsNothing);
      expect(find.byType(BackupNotice), findsOneWidget);
    });

    testWidgets('compartida hace menos de 15 días: sin aviso (RF-8)', (
      tester,
    ) async {
      await _open(
        tester,
        settings: BackupSettings(lastShared: DateTime(2026, 10, 23, 19)),
      );
      expect(find.text('Tus horas aún no tienen copia'), findsNothing);
      expect(find.textContaining('que no guardas una copia'), findsNothing);
    });

    testWidgets('compartida hace 15 días o más: recuerda y comparte '
        '(RF-7)', (tester) async {
      await _open(
        tester,
        settings: BackupSettings(lastShared: DateTime(2026, 10, 22, 18)),
      );
      expect(
        find.text('Hace más de 15 días que no guardas una copia'),
        findsOneWidget,
      );
      await tester.tap(find.text('Compartir copia'));
      await tester.pumpAndSettle();
      expect(backup.calls, contains('shareBackup'));
      expect(find.textContaining('que no guardas una copia'), findsNothing);
    });

    testWidgets('si compartir falla, lo dice y el aviso sigue', (tester) async {
      await _open(
        tester,
        settings: BackupSettings(lastShared: DateTime(2026, 10, 1)),
      );
      backup.shareResult = const BackupOutcome.fail('No se ha podido.');
      await tester.tap(find.text('Compartir copia'));
      await tester.pumpAndSettle();
      expect(find.text('No se ha podido.'), findsOneWidget);
      expect(find.textContaining('que no guardas una copia'), findsOneWidget);
    });

    testWidgets('con carpeta no recuerda compartir (RF-9)', (tester) async {
      await _open(
        tester,
        settings: _good.copyWith(lastShared: () => DateTime(2025)),
      );
      expect(find.textContaining('que no guardas una copia'), findsNothing);
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
      expect(find.text('Hacer copia'), findsNothing);
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
        expect(find.text('Hacer copia'), findsOneWidget);
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

    testWidgets('al volver a primer plano no copia, pero mira si hay algo '
        'de otro móvil (025, RF-9)', (tester) async {
      await _open(tester, settings: _good);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(backup.calls, ['checkOtherDevices']);
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

  group('cambios de otro móvil (025)', () {
    DayEntry day(int d, int minutes, {DayKind kind = DayKind.normal}) =>
        DayEntry(date: DateTime(2026, 11, d), minutes: minutes, kind: kind);
    ExtraItem fine(int cents) => ExtraItem(
      id: 1,
      type: ExtraType.fine,
      date: DateTime(2026, 11, 2),
      cents: cents,
      concept: 'Multa inventada',
    );
    BackupDiff sample({int extraDays = 0}) => BackupDiff(
      days: [
        DiffPair(day(3, 120), day(3, 180)),
        DiffPair(null, day(4, 90, kind: DayKind.festive)),
        DiffPair(day(5, 60), null),
        for (var i = 0; i < extraDays; i++) DiffPair(null, day(6 + i, 30)),
      ],
      items: [DiffPair(fine(5000), fine(2500))],
    );

    OtherDeviceOffer offer({
      bool tooNew = false,
      bool local = false,
      BackupDiff? diff,
    }) => OtherDeviceOffer(
      BackupInfo(
        'horas-copia-2026-11-06_17-30-00_x7b2m1_Trabajo.db',
        BackupKind.automatic,
        DateTime(2026, 11, 6, 17, 30),
        1,
        deviceId: 'x7b2m1',
        deviceName: 'Trabajo',
      ),
      diff: tooNew ? null : (diff ?? sample()),
      localChanges: local,
      tooNew: tooNew,
    );

    testWidgets('aviso con «Ver» y diálogo con el resumen (RF-11, RF-12)', (
      tester,
    ) async {
      await _open(tester, settings: _good);
      backup.offer = offer();
      await tester.pumpAndSettle();
      expect(find.text('Hay cambios de Trabajo · hoy, 17:30'), findsOneWidget);
      await tester.tap(find.text('Ver'));
      await tester.pumpAndSettle();
      expect(find.text('Cambios de Trabajo'), findsOneWidget);
      expect(find.text('Copia hecha hoy, 17:30'), findsOneWidget);
      expect(find.text('3 distintos'), findsOneWidget);
      expect(find.text('1 distinto'), findsOneWidget);
      expect(find.text('igual'), findsNWidgets(5));
      expect(find.textContaining('cambios sin copia'), findsNothing);
    });

    testWidgets('«Cargar» espera, carga y lo dice (RF-14)', (tester) async {
      await _open(tester, settings: _good);
      backup.offer = offer();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cargar'));
      await tester.pumpAndSettle();
      expect(backup.calls, contains('loadOffer'));
      expect(find.text('Cargados los cambios de Trabajo'), findsOneWidget);
      expect(find.textContaining('Hay cambios de'), findsNothing);
    });

    testWidgets('si falla al cargar, dice por qué', (tester) async {
      await _open(tester, settings: _good);
      backup.loadResult = const BackupOutcome.fail('No se ha podido.');
      backup.offer = offer();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cargar'));
      await tester.pumpAndSettle();
      expect(find.text('No se ha podido.'), findsOneWidget);
    });

    testWidgets('«Ahora no» y cerrar el diálogo lo descartan (RF-15)', (
      tester,
    ) async {
      await _open(tester, settings: _good);
      backup.offer = offer();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();
      expect(backup.calls, contains('dismissOffer'));
      expect(backup.calls, isNot(contains('loadOffer')));
      expect(find.textContaining('Hay cambios de'), findsNothing);

      backup.offer = offer();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5)); // fuera del diálogo
      await tester.pumpAndSettle();
      expect(backup.calls.where((c) => c == 'dismissOffer'), hasLength(2));
    });

    testWidgets('con cambios sin copia en este móvil, lo avisa (RF-13)', (
      tester,
    ) async {
      await _open(tester, settings: _good);
      backup.offer = offer(local: true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Este móvil tiene cambios sin copia. Se guardarán en la copia '
          'previa antes de cargar.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('versión más nueva: aviso para actualizar, sin botón (RF-17)', (
      tester,
    ) async {
      await _open(tester, settings: _good);
      backup.offer = offer(tooNew: true);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Trabajo tiene una versión más nueva de la app. Actualiza esta para '
          'ver sus cambios',
        ),
        findsOneWidget,
      );
      expect(find.text('Ver'), findsNothing);
    });

    testWidgets('la copia fallida va primero (RF-18)', (tester) async {
      await _open(
        tester,
        settings: const BackupSettings(
          folder: _folder,
          dirty: false,
          lastError: 'Sin espacio',
        ),
      );
      backup.offer = offer();
      await tester.pumpAndSettle();
      expect(find.text('No se ha podido hacer la copia'), findsOneWidget);
      expect(find.textContaining('Hay cambios de'), findsNothing);
    });

    testWidgets('sin desbordes a 360 px con letra al 130 %', (tester) async {
      await _open(tester, settings: _good, width: 360, scale: 1.3);
      backup.offer = offer(local: true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull); // el aviso
      await tester.tap(find.text('Ver'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull); // el diálogo
    });

    Future<void> openDialog(WidgetTester tester, OtherDeviceOffer o) async {
      backup.offer = o;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver'));
      await tester.pumpAndSettle();
    }

    testWidgets('tocar un apartado despliega aquí → allí, y se vuelve a '
        'plegar (RF-12b)', (tester) async {
      await _open(tester, settings: _good);
      await openDialog(tester, offer());
      expect(find.textContaining('aquí'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('apartado-hours')));
      await tester.pumpAndSettle();
      expect(find.text('3 nov 2026'), findsOneWidget);
      expect(find.text('aquí 2 h  →  Trabajo 3 h'), findsOneWidget);
      expect(find.text('aquí —  →  Trabajo 1,5 h festiva'), findsOneWidget);
      expect(find.text('aquí 1 h  →  Trabajo —'), findsOneWidget);
      // Los apartados iguales no se despliegan.
      expect(find.byKey(const ValueKey('apartado-vacation')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('apartado-hours')));
      await tester.pumpAndSettle();
      expect(find.textContaining('aquí'), findsNothing);
    });

    testWidgets('multas con importe y estado; ocultos si se ocultan los '
        'importes (RF-12b, RF-12d)', (tester) async {
      await _open(tester, settings: _good);
      await openDialog(tester, offer());
      await tester.tap(find.byKey(const ValueKey('apartado-extras')));
      await tester.pumpAndSettle();
      expect(find.text('Multa inventada · 2 nov 2026'), findsOneWidget);
      expect(
        find.text('aquí 50,00 € pendiente  →  Trabajo 25,00 € pendiente'),
        findsOneWidget,
      );
      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();

      // Con los importes ocultos, el mismo detalle tapa los euros.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: BackupNotice(
              backup: backup,
              onReview: () {},
              hideAmounts: () => true,
              clock: () => _now,
            ),
          ),
        ),
      );
      await openDialog(tester, offer());
      await tester.tap(find.byKey(const ValueKey('apartado-extras')));
      await tester.pumpAndSettle();
      expect(
        find.text('aquí •••• € pendiente  →  Trabajo •••• € pendiente'),
        findsOneWidget,
      );
      expect(find.textContaining('50,00'), findsNothing);
    });

    testWidgets('más de 20: las 20 primeras y «y N más» (RF-12c)', (
      tester,
    ) async {
      await _open(tester, settings: _good);
      await openDialog(tester, offer(diff: sample(extraDays: 22)));
      expect(find.text('25 distintos'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('apartado-hours')));
      await tester.pumpAndSettle();
      expect(find.textContaining('aquí'), findsNWidgets(20));
      expect(find.text('y 5 más'), findsOneWidget);
    });

    testWidgets('desplegado, sin desbordes a 360 px con letra al 130 %', (
      tester,
    ) async {
      await _open(tester, settings: _good, width: 360, scale: 1.3);
      await openDialog(tester, offer(diff: sample(extraDays: 22)));
      await tester.tap(find.byKey(const ValueKey('apartado-hours')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
