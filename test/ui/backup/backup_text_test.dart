import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/ui/backup/backup_text.dart';

void main() {
  group('folderLabel', () {
    test('quita el volumen y descodifica la ruta', () {
      expect(
        folderLabel(
          'content://com.android.externalstorage.documents/tree/'
          'primary%3ADocuments%2FHoras',
        ),
        'Documents/Horas',
      );
    });

    test('la raíz del almacenamiento', () {
      expect(
        folderLabel(
          'content://com.android.externalstorage.documents/tree/primary%3A',
        ),
        'Almacenamiento del móvil',
      );
    });

    test('una tarjeta SD', () {
      expect(
        folderLabel(
          'content://com.android.externalstorage.documents/tree/'
          '1A2B-3C4D%3ACopias',
        ),
        'Copias',
      );
    });

    test('una dirección rara se deja tal cual, sin fallar', () {
      expect(folderLabel('carpeta-inventada'), 'carpeta-inventada');
      expect(folderLabel('content://x/tree/%E0%A4%A'), isNotEmpty);
    });
  });

  group('backupMoment', () {
    final now = DateTime(2026, 11, 10, 20);

    test('hoy, ayer y fechas antiguas', () {
      expect(
        backupMoment(DateTime(2026, 11, 10, 18, 42), now: now),
        'hoy, 18:42',
      );
      expect(
        backupMoment(DateTime(2026, 11, 9, 9, 5), now: now),
        'ayer, 09:05',
      );
      expect(
        backupMoment(DateTime(2026, 11, 3, 18, 42), now: now),
        'el 3 de noviembre, 18:42',
      );
    });

    test('capitalized', () {
      expect(capitalized('hoy, 18:42'), 'Hoy, 18:42');
      expect(capitalized(''), '');
    });
  });
}
