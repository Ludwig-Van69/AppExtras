import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/domain/backup_names.dart';

void main() {
  final t = DateTime(2026, 3, 7, 8, 5, 9);

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

  group('backupsToPrune (RF-6)', () {
    List<String> autos(int n) => [
      for (var i = 0; i < n; i++) backupFileName(DateTime(2026, 1, 1 + i)),
    ];

    test('con 10 o menos no borra nada', () {
      expect(backupsToPrune(autos(10)), isEmpty);
    });

    test('con 13 borra las 3 más antiguas', () {
      final names = autos(13);
      expect(backupsToPrune(names.reversed), names.take(3).toList());
    });

    test('nunca borra copias previas a restaurar ni archivos ajenos', () {
      final names = [
        ...autos(11),
        backupFileName(DateTime(2020), kind: BackupKind.beforeRestore),
        'notas.txt',
      ];
      expect(backupsToPrune(names), [names.first]);
    });

    test('se puede elegir cuántas guardar', () {
      expect(backupsToPrune(autos(3), keep: 1), autos(2));
    });
  });
}
