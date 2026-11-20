import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lo que la spec 003 promete del manifiesto de Android: copia del sistema
/// activada (RF-22) y ningún permiso de internet ni de almacenamiento general.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  test('la copia automática de Android está activada (RF-22)', () {
    expect(manifest, contains('android:allowBackup="true"'));
  });

  test('sin permisos de internet ni de almacenamiento general', () {
    for (final permission in [
      'INTERNET',
      'READ_EXTERNAL_STORAGE',
      'WRITE_EXTERNAL_STORAGE',
      'MANAGE_EXTERNAL_STORAGE',
      'READ_MEDIA',
    ]) {
      expect(manifest, isNot(contains(permission)), reason: permission);
    }
  });
}
