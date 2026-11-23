import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Archivo de «Primeros pasos», aparte de la base de datos y de
/// `ajustes.json`: restaurar una copia no lo cambia (024, RF-9).
const firstStepsFileName = 'primeros-pasos.json';

/// Lo que se recuerda de la tarjeta «Primeros pasos» (024).
class FirstStepsState {
  const FirstStepsState({this.holidaysSeen = false, this.closed = false});

  /// Se ha abierto la pantalla de Festivos alguna vez (RF-4).
  final bool holidaysSeen;

  /// La tarjeta se cerró para siempre: con «Ocultar» o al completarla (RF-7,
  /// RF-8).
  final bool closed;

  FirstStepsState copyWith({bool? holidaysSeen, bool? closed}) =>
      FirstStepsState(
        holidaysSeen: holidaysSeen ?? this.holidaysSeen,
        closed: closed ?? this.closed,
      );

  @override
  bool operator ==(Object other) =>
      other is FirstStepsState &&
      other.holidaysSeen == holidaysSeen &&
      other.closed == closed;

  @override
  int get hashCode => Object.hash(holidaysSeen, closed);
}

/// Lee y guarda [FirstStepsState] en un archivo JSON.
class FirstStepsStore {
  FirstStepsStore(File file) : _locate = (() async => file);

  FirstStepsStore.inAppFolder()
    : _locate = (() async =>
          File(p.join(await getDatabasesPath(), firstStepsFileName)));

  final Future<File> Function() _locate;

  /// Lo guardado. Si falta o está dañado, el estado inicial (RF-10): lo peor
  /// que pasa es volver a ver la tarjeta.
  Future<FirstStepsState> load() async {
    try {
      final json = jsonDecode(await (await _locate()).readAsString());
      if (json is Map<String, Object?>) {
        return FirstStepsState(
          holidaysSeen: json['holidaysSeen'] == true,
          closed: json['closed'] == true,
        );
      }
    } on FileSystemException {
      // No existe o no se puede leer.
    } on FormatException {
      // JSON dañado.
    }
    return const FirstStepsState();
  }

  /// Guarda en un temporal y lo renombra, para no dejar el archivo a medias.
  Future<void> save(FirstStepsState s) async {
    final file = await _locate();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'version': 1,
        'holidaysSeen': s.holidaysSeen,
        'closed': s.closed,
      }),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}
