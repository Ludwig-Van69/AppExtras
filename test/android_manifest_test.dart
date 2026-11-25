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

  test('la app solo se usa en vertical', () {
    expect(manifest, contains('android:screenOrientation="portrait"'));
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

  test('la copia de Android no se lleva el código del móvil (025, RF-4)', () {
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    const res = 'android/app/src/main/res/xml/';
    final old = File('${res}backup_rules.xml').readAsStringSync();
    final rules = File('${res}data_extraction_rules.xml').readAsStringSync();
    const exclude = '<exclude domain="database" path="movil.json" />';
    expect(old, contains(exclude));
    // En la nube y al pasar a un móvil nuevo.
    expect(exclude.allMatches(rules).length, 2);
    expect(rules, contains('<cloud-backup>'));
    expect(rules, contains('<device-transfer>'));
    // Solo se excluye eso: el resto de la copia sigue (003, RF-22).
    expect(old, isNot(contains('<include')));
    expect(rules, isNot(contains('<include')));
  });
}
