import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/data/app_settings.dart';
import 'package:horas_y_vacaciones/domain/device_identity.dart';
import 'package:horas_y_vacaciones/domain/backup_names.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/backup/backup_controller.dart';
import 'package:horas_y_vacaciones/ui/backup/backup_screen.dart';

import '../../fakes/fake_backup_service.dart';
import '../test_app.dart';

final _now = DateTime(2026, 11, 10, 20);
const _folder =
    'content://com.android.externalstorage.documents/tree/'
    'primary%3ADocuments%2FHoras';

late FakeBackupService fake;
Future<void> Function()? _waitForSaves;

/// Abre la pantalla de copias dentro de una «pantalla anterior», para poder
/// comprobar que se vuelve a ella.
Future<void> _open(
  WidgetTester tester, {
  BackupSettings? settings,
  double width = 390,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  fake = FakeBackupService(settings: settings ?? const BackupSettings());
  calmAnimations(tester);
  await tester.binding.setSurfaceSize(Size(width, 800));
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.platformDispatcher.clearAllTestValues();
  });
  await tester.pumpWidget(
    HoursAndVacationApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BackupScreen(
                    backup: fake,
                    waitForSaves: _waitForSaves,
                    clock: () => _now,
                  ),
                ),
              ),
              child: const Text('pantalla anterior'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('pantalla anterior'));
  await tester.pumpAndSettle();
}

BackupSettings _good() => BackupSettings(
  folder: _folder,
  lastSuccess: DateTime(2026, 11, 10, 18, 42),
  dirty: false,
);

Future<void> _openRestore(WidgetTester tester) async {
  await tester.tap(find.text('Restaurar una copia'));
  await tester.pumpAndSettle();
}

const _me = DeviceIdentity(id: 'abc123', name: 'moto g75');
const _other = DeviceIdentity(id: 'x7b2m1', name: 'Móvil trabajo');

void main() {
  setUp(() => _waitForSaves = null);

  group('pantalla de copias', () {
    testWidgets('sin carpeta: lo dice y se puede elegir (RF-1, RF-10)', (
      tester,
    ) async {
      await _open(tester);
      expect(find.text('Copias y exportación'), findsOneWidget);
      expect(find.text('Sin elegir'), findsOneWidget);
      expect(find.text('Todavía ninguna'), findsOneWidget);
      await tester.tap(find.byTooltip('Elegir carpeta'));
      await tester.pumpAndSettle();
      expect(fake.calls, ['chooseFolder']);
      expect(find.text('Documents/Horas'), findsOneWidget);
      expect(find.byTooltip('Cambiar carpeta'), findsOneWidget);
    });

    testWidgets('muestra carpeta y última copia correcta (RF-10)', (
      tester,
    ) async {
      await _open(tester, settings: _good());
      expect(find.text('Documents/Horas'), findsOneWidget);
      expect(find.text('Hoy, 18:42'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('si la última copia falló, dice el motivo (RF-10)', (
      tester,
    ) async {
      await _open(
        tester,
        settings: _good().copyWith(
          lastError: () => 'La carpeta de las copias ya no está disponible.',
        ),
      );
      expect(
        find.text(
          'La última copia falló. La carpeta de las copias ya no está '
          'disponible.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    });

    testWidgets('«Hacer copia ahora» dice si ha ido bien o mal (RF-11)', (
      tester,
    ) async {
      await _open(tester, settings: _good());
      await tester.tap(find.text('Hacer copia ahora'));
      await tester.pumpAndSettle();
      expect(fake.calls, ['backupNow']);
      expect(find.text('Copia hecha correctamente.'), findsOneWidget);

      fake.backupResult = const BackupOutcome.fail('No hay espacio.');
      await tester.tap(find.text('Hacer copia ahora'));
      await tester.pumpAndSettle();
      expect(find.text('No hay espacio.'), findsOneWidget);
    });

    testWidgets('«Exportar a Excel» y el aviso de que no hay horas (RF-21)', (
      tester,
    ) async {
      await _open(tester, settings: _good());
      await tester.tap(find.text('Exportar a Excel'));
      await tester.pumpAndSettle();
      expect(fake.calls, ['exportCsv']);
      expect(
        find.text('Listo: elige dónde enviar el archivo.'),
        findsOneWidget,
      );

      fake.exportResult = const BackupOutcome.fail(
        'Aún no hay horas que exportar.',
      );
      await tester.tap(find.text('Exportar a Excel'));
      await tester.pumpAndSettle();
      expect(find.text('Aún no hay horas que exportar.'), findsOneWidget);
    });

    testWidgets('mientras trabaja, bloquea los botones y lo indica', (
      tester,
    ) async {
      await _open(tester, settings: _good());
      fake.busy = true;
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      for (final label in [
        'Hacer copia ahora',
        'Restaurar una copia',
        'Exportar a Excel',
      ]) {
        final button = tester.widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        );
        expect(button.onPressed, isNull, reason: label);
      }
    });

    testWidgets('explica cómo llevar las copias al ordenador o a otro móvil '
        '(025, RF-19)', (tester) async {
      await _open(tester);
      await tester.tap(
        find.byTooltip('Más información: Llevar las copias a otro sitio'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Solo enviar'), findsOneWidget);
      expect(
        find.textContaining('«Enviar y recibir» en ambos'),
        findsOneWidget,
      );
      expect(find.textContaining('por turnos'), findsOneWidget);
    });
  });

  group('este móvil (025, RF-2, RF-3)', () {
    testWidgets('muestra el nombre y se cambia', (tester) async {
      await _open(tester, settings: _good());
      expect(find.text('Este móvil'), findsOneWidget);
      expect(find.text('moto g75'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cambiar-nombre-movil')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('nombre-movil')),
        '  Móvil  trabajo ',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(fake.device!.name, 'Móvil trabajo');
      expect(find.text('Móvil trabajo'), findsOneWidget);
      expect(find.text('Nombre de este móvil'), findsNothing);
    });

    testWidgets('un nombre que no vale no se guarda y dice por qué', (
      tester,
    ) async {
      await _open(tester, settings: _good());
      await tester.tap(find.byKey(const ValueKey('cambiar-nombre-movil')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('nombre-movil')),
        'móvil_1',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Usa de 1 a 24 letras, números, espacios o guiones'),
        findsOneWidget,
      );
      expect(fake.device!.name, 'moto g75');
      // Cancelar deja el nombre como estaba.
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('moto g75'), findsOneWidget);
    });
  });

  group('restaurar', () {
    final copies = [
      listing(DateTime(2026, 11, 10, 18, 42, 5), 21, device: _me),
      listing(DateTime(2026, 11, 3, 9, 5, 0), 1, device: _other),
      listing(
        DateTime(2026, 10, 30, 12, 0, 0),
        4,
        kind: BackupKind.beforeRestore,
        device: _me,
      ),
      listing(DateTime(2025, 12, 1, 8, 0, 0), null),
    ];

    testWidgets('lista las copias con fecha, móvil y número de días '
        '(RF-12; 025, RF-7, RF-8)', (tester) async {
      await _open(tester, settings: _good());
      fake.listing = copies;
      await _openRestore(tester);
      expect(find.text('Hoy, 18:42'), findsOneWidget);
      expect(find.text('Este móvil · 21 días con horas'), findsOneWidget);
      expect(find.text('El 3 de noviembre, 09:05'), findsOneWidget);
      expect(find.text('Móvil trabajo · 1 día con horas'), findsOneWidget);
      expect(find.text('Este móvil · 4 días con horas'), findsOneWidget);
      expect(
        find.text('El 30 de octubre, 12:00 · antes de restaurar'),
        findsOneWidget,
      );
      expect(find.text('Copia antigua · no se puede leer'), findsOneWidget);
    });

    testWidgets(
      'pide confirmación con el texto exacto y se puede cancelar (RF-13)',
      (tester) async {
        await _open(tester, settings: _good());
        fake.listing = copies;
        await _openRestore(tester);
        await tester.tap(find.text('El 3 de noviembre, 09:05'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Se sustituirán todos tus datos por los de la copia del 3 de '
            'noviembre. Antes guardaremos una copia de lo que tienes ahora.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(fake.calls, isEmpty);
        expect(find.text('Restaurar una copia'), findsWidgets);
      },
    );

    testWidgets('con el año si la copia no es de este año', (tester) async {
      await _open(tester, settings: _good());
      fake.listing = copies;
      await _openRestore(tester);
      await tester.tap(find.text('Copia antigua · no se puede leer'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('la copia del 1 de diciembre de 2025'),
        findsOneWidget,
      );
    });

    testWidgets(
      'al confirmar espera los guardados, restaura y vuelve atrás (RF-14)',
      (tester) async {
        var saved = false;
        _waitForSaves = () async => saved = true;
        await _open(tester, settings: _good());
        fake.listing = copies;
        await _openRestore(tester);
        await tester.tap(find.text('El 3 de noviembre, 09:05'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restaurar'));
        await tester.pumpAndSettle();

        expect(saved, isTrue);
        expect(fake.calls, [
          'restoreFromFolder:horas-copia-2026-11-03_09-05-00_x7b2m1_Móvil trabajo.db',
        ]);
        expect(find.text('pantalla anterior'), findsOneWidget);
        expect(find.text('Copia restaurada.'), findsOneWidget);
      },
    );

    testWidgets(
      'si falla, explica por qué y se queda en la lista (RF-15, RF-16)',
      (tester) async {
        await _open(tester, settings: _good());
        fake.listing = copies;
        fake.restoreResult = const BackupOutcome.fail(
          'Este archivo no es una copia de esta app o está dañado.',
        );
        await _openRestore(tester);
        await tester.tap(find.text('Hoy, 18:42'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restaurar').last);
        await tester.pumpAndSettle();
        expect(
          find.text('Este archivo no es una copia de esta app o está dañado.'),
          findsOneWidget,
        );
        expect(find.text('pantalla anterior'), findsNothing);
        expect(find.text('Elegir otro archivo…'), findsOneWidget);
      },
    );

    testWidgets(
      'sin copias o sin carpeta lo dice, y deja elegir un archivo (RF-17)',
      (tester) async {
        await _open(tester);
        await _openRestore(tester);
        expect(
          find.textContaining('Aún no has elegido carpeta'),
          findsOneWidget,
        );

        fake.fileToPick = '/cache/elegido.db';
        await tester.tap(find.text('Elegir otro archivo…'));
        await tester.pumpAndSettle();
        expect(find.textContaining('por los de este archivo'), findsOneWidget);
        await tester.tap(find.text('Restaurar').last);
        await tester.pumpAndSettle();
        expect(fake.calls, ['restoreFromFile:/cache/elegido.db']);
        expect(find.text('pantalla anterior'), findsOneWidget);
      },
    );

    testWidgets('cancelar el selector de archivos no hace nada', (
      tester,
    ) async {
      await _open(tester, settings: _good());
      await _openRestore(tester);
      expect(find.text('No hay copias en la carpeta todavía.'), findsOneWidget);
      await tester.tap(find.text('Elegir otro archivo…'));
      await tester.pumpAndSettle();
      expect(fake.calls, isEmpty);
      expect(find.textContaining('Se sustituirán'), findsNothing);
    });
  });

  group('tamaños sin desbordes', () {
    for (final width in [360.0, 412.0]) {
      for (final scale in [1.0, 1.3]) {
        for (final brightness in Brightness.values) {
          testWidgets(
            '${width.toInt()} px, letra al ${(scale * 100).toInt()} %, '
            '${brightness.name}',
            (tester) async {
              await _open(
                tester,
                width: width,
                scale: scale,
                brightness: brightness,
                settings: BackupSettings(
                  folder:
                      'content://com.android.externalstorage.documents/tree/'
                      'primary%3ADocuments%2FMis%20copias%20de%20horas%2FMuy'
                      '%20larga%2FCarpeta',
                  lastSuccess: DateTime(2026, 10, 1, 8, 5),
                  lastError:
                      'La carpeta de las copias ya no está disponible. '
                      'Elige la carpeta otra vez.',
                ),
              );
              expect(tester.takeException(), isNull);
              for (final label in [
                'Hacer copia ahora',
                'Restaurar una copia',
                'Exportar a Excel',
              ]) {
                // La pantalla se desplaza: se llega al botón antes de medirlo.
                await tester.scrollUntilVisible(find.text(label), 100);
                expect(
                  tester
                      .getSize(
                        find
                            .ancestor(
                              of: find.text(label),
                              matching: find.byWidgetPredicate(
                                (w) => w is ButtonStyleButton,
                              ),
                            )
                            .first,
                      )
                      .height,
                  greaterThanOrEqualTo(48),
                  reason: label,
                );
              }
              fake.listing = [
                listing(
                  DateTime(2025, 10, 30, 12),
                  400,
                  kind: BackupKind.beforeRestore,
                ),
                listing(DateTime(2026, 11, 3, 9, 5), 1),
              ];
              await _openRestore(tester);
              expect(tester.takeException(), isNull);
              expect(find.text('Elegir otro archivo…'), findsOneWidget);
            },
          );
        }
      }
    }
  });

  group('compartir copia (023)', () {
    testWidgets('sin carpeta se puede compartir; dice la fecha y cómo '
        'recuperarla (RF-1, RF-10, RF-11)', (tester) async {
      await _open(tester);
      expect(find.textContaining('Última copia compartida'), findsNothing);
      fake.sharedAt = DateTime(2026, 11, 10, 18);
      await tester.tap(find.byKey(const ValueKey('compartir-copia')));
      await tester.pumpAndSettle();
      expect(fake.calls, ['shareBackup']);
      expect(find.text('Listo: elige dónde guardar la copia.'), findsOneWidget);
      expect(find.text('Última copia compartida: hoy, 18:00'), findsOneWidget);
      await tester.tap(find.byTooltip('Más información: Compartir copia'));
      await tester.pumpAndSettle();
      expect(find.textContaining('«Elegir otro archivo…»'), findsOneWidget);
    });

    testWidgets('si falla, dice el motivo (RF-3)', (tester) async {
      await _open(tester, settings: _good());
      fake.shareResult = const BackupOutcome.fail('Sin espacio.');
      await tester.tap(find.byKey(const ValueKey('compartir-copia')));
      await tester.pumpAndSettle();
      expect(find.text('Sin espacio.'), findsOneWidget);
    });

    testWidgets('mientras trabaja, no se puede pulsar', (tester) async {
      await _open(tester);
      fake.busy = true;
      await tester.pump();
      final b = tester.widget<ButtonStyleButton>(
        find.byKey(const ValueKey('compartir-copia')),
      );
      expect(b.onPressed, isNull);
    });
  });
}
