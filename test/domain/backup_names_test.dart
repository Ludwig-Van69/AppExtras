import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/backup_names.dart';
import 'package:horas_y_vacaciones/domain/device_identity.dart';

void main() {
  final t = DateTime(2026, 3, 7, 8, 5, 9);
  const me = DeviceIdentity(id: 'abc123', name: 'moto g75');
  const other = DeviceIdentity(id: 'x7b2m1', name: 'Móvil trabajo');

  group('backupFileName (RF-5)', () {
    test('copia automática con fecha y hora', () {
      expect(backupFileName(t), 'horas-copia-2026-03-07_08-05-09.db');
    });

    test('copia previa a restaurar', () {
      expect(
        backupFileName(t, kind: BackupKind.beforeRestore),
        'horas-antes-de-restaurar-2026-03-07_08-05-09.db',
      );
    });

    test('si el nombre ya existe, añade -2, -3…', () {
      final first = backupFileName(t);
      final second = backupFileName(t, existing: {first});
      expect(second, 'horas-copia-2026-03-07_08-05-09-2.db');
      expect(
        backupFileName(t, existing: {first, second}),
        'horas-copia-2026-03-07_08-05-09-3.db',
      );
    });
  });

  group('parseBackupName', () {
    test('reconoce sus propios nombres', () {
      for (final kind in BackupKind.values) {
        for (final n in [
          backupFileName(t, kind: kind),
          backupFileName(
            t,
            kind: kind,
            existing: {backupFileName(t, kind: kind)},
          ),
        ]) {
          final info = parseBackupName(n);
          expect(info, isNotNull, reason: n);
          expect(info!.kind, kind);
          expect(info.takenAt, t);
          expect(info.name, n);
        }
      }
    });

    test('ignora archivos ajenos, temporales y fechas imposibles', () {
      for (final n in [
        'foto.jpg',
        'horas-2026-11-10.csv',
        'horas-copia-2026-03-07_08-05-09.db.part',
        'horas-copia-2026-02-30_08-05-09.db',
        'horas-copia-2026-03-07_25-05-09.db',
        'horas-copia-2026-03-07_08-05-09-1.db',
        'horas-copia-2026-03-07_08-05-09-x.db',
        'HORAS-COPIA-2026-03-07_08-05-09.db',
        'otra-horas-copia-2026-03-07_08-05-09.db',
      ]) {
        expect(parseBackupName(n), isNull, reason: n);
      }
    });
  });

  group('sortedBackups', () {
    test('de la más reciente a la más antigua, también con sufijos', () {
      final a = backupFileName(DateTime(2026, 1, 1));
      final b = backupFileName(DateTime(2026, 1, 1), existing: {a});
      final c = backupFileName(DateTime(2026, 1, 2));
      final s = backupFileName(
        DateTime(2025, 12, 31),
        kind: BackupKind.beforeRestore,
      );
      expect(sortedBackups([a, 'foto.jpg', s, c, b]).map((i) => i.name), [
        c,
        b,
        a,
        s,
      ]);
    });
  });

  group('con el móvil (025, RF-5, RF-7)', () {
    test('el nombre lleva código y nombre del móvil', () {
      expect(
        backupFileName(t, device: me),
        'horas-copia-2026-03-07_08-05-09_abc123_moto g75.db',
      );
      expect(
        backupFileName(t, kind: BackupKind.beforeRestore, device: other),
        'horas-antes-de-restaurar-2026-03-07_08-05-09_x7b2m1_Móvil trabajo.db',
      );
    });

    test('si se repite el segundo, el -2 va tras la hora', () {
      final first = backupFileName(t, device: me);
      expect(
        backupFileName(t, device: me, existing: {first}),
        'horas-copia-2026-03-07_08-05-09-2_abc123_moto g75.db',
      );
      // Otro móvil en el mismo segundo no choca.
      expect(
        backupFileName(t, device: other, existing: {first}),
        'horas-copia-2026-03-07_08-05-09_x7b2m1_Móvil trabajo.db',
      );
    });

    test('se lee de vuelta el móvil; las antiguas no tienen', () {
      final n = backupFileName(
        t,
        device: me,
        existing: {backupFileName(t, device: me)},
      );
      final info = parseBackupName(n)!;
      expect(info.deviceId, 'abc123');
      expect(info.deviceName, 'moto g75');
      expect(info.takenAt, t);
      expect(info.copyNumber, 2);
      final old = parseBackupName(backupFileName(t))!;
      expect(old.deviceId, isNull);
      expect(old.deviceName, isNull);
    });

    test('rechaza móviles mal formados', () {
      for (final n in [
        'horas-copia-2026-03-07_08-05-09_ABC123_x.db',
        'horas-copia-2026-03-07_08-05-09_abc12_x.db',
        'horas-copia-2026-03-07_08-05-09_abc123_.db',
        'horas-copia-2026-03-07_08-05-09_abc123_a_b.db',
        'horas-copia-2026-03-07_08-05-09_abc123_ x.db',
        'horas-copia-2026-03-07_08-05-09_abc123_${'x' * 25}.db',
        'horas-copia-2026-03-07_08-05-09-1_abc123_x.db',
      ]) {
        expect(parseBackupName(n), isNull, reason: n);
      }
    });

    test('orderKey ordena por fecha y número de copia', () {
      final a = parseBackupName(backupFileName(t, device: me))!;
      final b = parseBackupName(
        backupFileName(t, device: me, existing: {a.name}),
      )!;
      final c = parseBackupName(
        backupFileName(t.add(const Duration(seconds: 1)), device: me),
      )!;
      expect(a.orderKey, '2026-03-07_08-05-09-0001');
      expect(a.orderKey.compareTo(b.orderKey), lessThan(0));
      expect(b.orderKey.compareTo(c.orderKey), lessThan(0));
    });
  });

  group('backupsToPrune (RF-6; 025, RF-6)', () {
    List<String> autos(int n, [DeviceIdentity? d = me]) => [
      for (var i = 0; i < n; i++)
        backupFileName(DateTime(2026, 1, 1 + i), device: d),
    ];
    List<String> prune(Iterable<String> names, {int keep = backupsToKeep}) =>
        backupsToPrune(names, deviceId: me.id, keep: keep);

    test('con 10 o menos no borra nada', () {
      expect(prune(autos(10)), isEmpty);
    });

    test('con 13 borra las 3 más antiguas', () {
      final names = autos(13);
      expect(prune(names.reversed), names.take(3).toList());
    });

    test('nunca borra copias previas a restaurar ni archivos ajenos', () {
      final names = [
        ...autos(11),
        backupFileName(
          DateTime(2020),
          kind: BackupKind.beforeRestore,
          device: me,
        ),
        'notas.txt',
      ];
      expect(prune(names), [names.first]);
    });

    test('se puede elegir cuántas guardar', () {
      expect(prune(autos(3), keep: 1), autos(2));
    });

    test('solo borra las de este móvil: ni las de otro ni las antiguas', () {
      final mine = autos(12);
      final theirs = autos(15, other);
      final old = autos(14, null);
      expect(prune([...theirs, ...old, ...mine]), mine.take(2).toList());
    });
  });
}
