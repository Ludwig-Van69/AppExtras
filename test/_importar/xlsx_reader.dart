// Lector mínimo de .xlsx para el importador (016). No es parte de la app: solo
// se usa en el ordenador. Sin librerías: un .xlsx es un zip con XML dentro, y
// Dart ya trae lo necesario para descomprimirlo (ZLibDecoder).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Una hoja: valor de cada celda por su referencia («B3»). Los números van
/// como [double] y los textos como [String].
typedef Sheet = Map<String, Object>;

/// Lee todas las hojas de un .xlsx, por su nombre.
Map<String, Sheet> readXlsx(Uint8List bytes) {
  final files = unzip(bytes);
  String text(String name) {
    final f = files[name];
    if (f == null) throw FormatException('Falta $name en el .xlsx');
    return utf8.decode(f);
  }

  final shared = files.containsKey('xl/sharedStrings.xml')
      ? parseSharedStrings(text('xl/sharedStrings.xml'))
      : const <String>[];
  final targets = {
    for (final m in RegExp(
      r'<Relationship\b[^>]*?\bId="([^"]+)"[^>]*?\bTarget="([^"]+)"',
    ).allMatches(text('xl/_rels/workbook.xml.rels')))
      m[1]!: m[2]!,
  };
  // Algunos archivos ponen Target antes que Id.
  for (final m in RegExp(
    r'<Relationship\b[^>]*?\bTarget="([^"]+)"[^>]*?\bId="([^"]+)"',
  ).allMatches(text('xl/_rels/workbook.xml.rels'))) {
    targets[m[2]!] = m[1]!;
  }
  final sheets = <String, Sheet>{};
  for (final m in RegExp(
    r'<sheet\b[^>]*/?>',
  ).allMatches(text('xl/workbook.xml'))) {
    final tag = m[0]!;
    final name = _attr(tag, 'name');
    final id = _attr(tag, 'r:id');
    if (name == null || id == null) continue;
    var target = targets[id]!;
    target = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    sheets[_unescape(name)] = parseSheet(text(target), shared);
  }
  return sheets;
}

String? _attr(String tag, String name) =>
    RegExp('\\b${RegExp.escape(name)}="([^"]*)"').firstMatch(tag)?[1];

/// Los textos compartidos (`sharedStrings.xml`), en orden. Un texto con
/// formato (varios `<t>`) se une.
List<String> parseSharedStrings(String xml) => [
  for (final si in RegExp(r'<si>(.*?)</si>', dotAll: true).allMatches(xml))
    RegExp(
      r'<t\b[^>]*>(.*?)</t>',
      dotAll: true,
    ).allMatches(si[1]!).map((t) => _unescape(t[1]!)).join(),
];

/// Las celdas con valor de una hoja. Toma el valor guardado (también el de
/// las fórmulas, que Excel guarda ya calculado).
Sheet parseSheet(String xml, List<String> shared) {
  final out = <String, Object>{};
  for (final c in RegExp(
    r'<c\b([^>]*?)(?:/>|>(.*?)</c>)',
    dotAll: true,
  ).allMatches(xml)) {
    final attrs = c[1]!;
    final body = c[2] ?? '';
    final ref = _attr(attrs, 'r');
    if (ref == null) continue;
    final type = _attr(attrs, 't');
    if (type == 'inlineStr') {
      final t = RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true).firstMatch(body);
      if (t != null) out[ref] = _unescape(t[1]!);
      continue;
    }
    final v = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?[1];
    if (v == null) continue;
    switch (type) {
      case 's':
        out[ref] = shared[int.parse(v)];
      case 'str' || 'e':
        out[ref] = _unescape(v);
      case 'b':
        out[ref] = v == '1' ? 'VERDADERO' : 'FALSO';
      default:
        final n = double.tryParse(v);
        out[ref] = n ?? _unescape(v);
    }
  }
  return out;
}

String _unescape(String s) => s
    .replaceAllMapped(
      RegExp(r'&#(x?)([0-9a-fA-F]+);'),
      (m) =>
          String.fromCharCode(int.parse(m[2]!, radix: m[1]! == 'x' ? 16 : 10)),
    )
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Descomprime un zip (solo «guardado» y «deflate», que es lo que usa Excel).
Map<String, Uint8List> unzip(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  // Fin del directorio central: firma 0x06054b50, buscando desde el final.
  var end = -1;
  for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 66000; i--) {
    if (data.getUint32(i, Endian.little) == 0x06054b50) {
      end = i;
      break;
    }
  }
  if (end < 0) throw const FormatException('No es un .xlsx (zip) válido');
  final count = data.getUint16(end + 10, Endian.little);
  var p = data.getUint32(end + 16, Endian.little);
  final out = <String, Uint8List>{};
  for (var n = 0; n < count; n++) {
    if (data.getUint32(p, Endian.little) != 0x02014b50) {
      throw const FormatException('Directorio del zip dañado');
    }
    final method = data.getUint16(p + 10, Endian.little);
    final size = data.getUint32(p + 20, Endian.little);
    final nameLen = data.getUint16(p + 28, Endian.little);
    final extraLen = data.getUint16(p + 30, Endian.little);
    final commentLen = data.getUint16(p + 32, Endian.little);
    final local = data.getUint32(p + 42, Endian.little);
    final name = utf8.decode(bytes.sublist(p + 46, p + 46 + nameLen));
    p += 46 + nameLen + extraLen + commentLen;

    final lNameLen = data.getUint16(local + 26, Endian.little);
    final lExtraLen = data.getUint16(local + 28, Endian.little);
    final start = local + 30 + lNameLen + lExtraLen;
    final raw = bytes.sublist(start, start + size);
    out[name] = switch (method) {
      0 => raw,
      8 => Uint8List.fromList(ZLibDecoder(raw: true).convert(raw)),
      _ => throw FormatException('Compresión no admitida en $name'),
    };
  }
  return out;
}
