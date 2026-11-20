/// Textos de la pantalla de copias.
library;

import '../format.dart';

/// Nombre legible de la carpeta a partir de su dirección de Android:
/// `…/tree/primary%3ADocuments%2FHoras` → «Documents/Horas».
String folderLabel(String uri) {
  const marker = '/tree/';
  final i = uri.indexOf(marker);
  var id = i < 0 ? uri : uri.substring(i + marker.length);
  try {
    id = Uri.decodeComponent(id);
  } on ArgumentError {
    // Se deja tal cual.
  }
  final colon = id.indexOf(':');
  if (colon < 0) return id;
  final path = id.substring(colon + 1);
  return path.isEmpty ? 'Almacenamiento del móvil' : path;
}

/// «hoy, 18:42», «ayer, 09:05», «el 3 de noviembre, 18:42».
String backupMoment(DateTime moment, {required DateTime now}) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${dayPhrase(moment, today: now)}, ${two(moment.hour)}:'
      '${two(moment.minute)}';
}

/// La misma frase empezando en mayúscula, para el principio de una línea.
String capitalized(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
