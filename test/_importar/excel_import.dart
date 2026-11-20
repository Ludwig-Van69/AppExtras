// Lógica del importador del Excel (016, RF-10 a RF-15). No es parte de la
// app: solo se usa en el ordenador. Pura y probada con datos inventados.
import 'package:horas_y_vacaciones/domain/day_entry.dart';
import 'package:horas_y_vacaciones/domain/day_kind.dart';
import 'package:horas_y_vacaciones/domain/imported_month.dart';
import 'package:horas_y_vacaciones/domain/money.dart';

import 'xlsx_reader.dart';

const monthNames = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

/// Lo que sale de leer el Excel: lo que se va a crear y el informe.
class ExcelImport {
  ExcelImport({
    required this.detailYear,
    required this.days,
    required this.imported,
    required this.records,
    required this.rates,
    required this.notes,
    required this.problems,
    required this.checks,
  });

  /// El año del que hay días (hojas Enero a Diciembre).
  final int detailYear;
  final List<DayEntry> days;
  final List<ImportedMonth> imported;
  final List<MonthRecord> records;
  final List<Rate> rates;

  /// Datos raros corregidos o descartados, para revisarlos (RF-13, RF-15).
  final List<String> notes;

  /// Lo que impide crear la copia: totales que no cuadran o datos ilegibles.
  final List<String> problems;

  /// Las comprobaciones de totales, para el informe.
  final List<String> checks;

  bool get ok => problems.isEmpty;

  /// El informe que se enseña antes de crear nada (RF-13).
  String report() {
    final b = StringBuffer()
      ..writeln('INFORME DE IMPORTACIÓN DEL EXCEL')
      ..writeln('Días de $detailYear: ${days.length}')
      ..writeln(
        'Meses del Excel (solo total): ${imported.length}'
        '${imported.isEmpty ? '' : ' (de ${_ym(imported.first.month)} a ${_ym(imported.last.month)})'}',
      )
      ..writeln(
        'Meses cobrados: ${records.length}; abiertos: los demás con horas',
      )
      ..writeln(
        'Tarifas: ${[for (final r in rates) '${r.kind == DayKind.normal ? 'normal' : 'festiva'} ${r.cents / 100} € desde ${_date(r.start)}'].join('; ')}',
      )
      ..writeln()
      ..writeln('COMPROBACIONES')
      ..writeAll(checks.map((c) => '  $c\n'))
      ..writeln()
      ..writeln('DATOS RAROS CORREGIDOS O DESCARTADOS (${notes.length})')
      ..writeAll(notes.map((n) => '  $n\n'))
      ..writeln()
      ..writeln(
        ok
            ? 'RESULTADO: todo cuadra.'
            : 'RESULTADO: NO CUADRA. No se crea la copia.\n'
                  '${problems.map((p) => '  $p').join('\n')}',
      );
    return b.toString();
  }
}

String _ym(YearMonth m) => '${monthNames[m.month - 1].toLowerCase()} ${m.year}';
String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';
String _h(int minutes) => '${(minutes / 60).toString().replaceAll('.', ',')} h';

/// Índice de columna (0 = A) de una referencia como «AB12».
int columnOf(String ref) {
  var n = 0;
  for (final ch in ref.codeUnits) {
    if (ch < 65 || ch > 90) break;
    n = n * 26 + (ch - 64);
  }
  return n - 1;
}

/// Fila (1 = primera) de una referencia como «AB12».
int rowOf(String ref) => int.parse(ref.replaceAll(RegExp('[A-Z]'), ''));

/// Referencia de la columna [col] (0 = A) y la fila [row].
String refOf(int col, int row) {
  var c = col + 1;
  var letters = '';
  while (c > 0) {
    final r = (c - 1) % 26;
    letters = String.fromCharCode(65 + r) + letters;
    c = (c - 1) ~/ 26;
  }
  return '$letters$row';
}

/// Minutos enteros de unas horas del Excel (con decimales).
int minutesOf(double hours) => (hours * 60).round();

/// Interpreta el libro: días del año de detalle, totales mensuales de los
/// años anteriores, estados y tarifas, con sus comprobaciones.
///
/// [paidUntil]: último mes cobrado (incluido); los posteriores, abiertos
/// (RF-11). [rateStart] y las tarifas: las que se conocen (RF-12).
ExcelImport importWorkbook(
  Map<String, Sheet> book, {
  required YearMonth paidUntil,
  required DateTime rateStart,
  int normalRateCents = 1500,
  int festiveRateCents = 2000,
}) {
  final notes = <String>[];
  final problems = <String>[];
  final checks = <String>[];

  // ---- Resumen: totales por mes y año ------------------------------------
  final resumen = book['Resumen'];
  if (resumen == null) {
    return _failed('No hay hoja «Resumen».');
  }
  int? janRow;
  int? totalRow;
  for (final e in resumen.entries) {
    if (columnOf(e.key) != 1 || e.value is! String) continue;
    final t = (e.value as String).trim();
    if (t == 'Enero' && (janRow == null || rowOf(e.key) < janRow)) {
      janRow = rowOf(e.key);
    }
    if (t == 'Total anual') totalRow = rowOf(e.key);
  }
  if (janRow == null || totalRow == null) {
    return _failed('En «Resumen» no encuentro la tabla de meses.');
  }
  for (var m = 0; m < 12; m++) {
    final name = resumen[refOf(1, janRow + m)];
    if (name is! String || name.trim() != monthNames[m]) {
      return _failed(
        'En «Resumen», la fila ${janRow + m} debería ser ${monthNames[m]}.',
      );
    }
  }
  // Fila de años: dos por encima de «Enero» (año, y debajo Normal/Festivo).
  final yearCol = <int, int>{};
  for (var row = janRow - 1; row >= janRow - 3 && yearCol.isEmpty; row--) {
    for (final e in resumen.entries) {
      if (rowOf(e.key) != row || e.value is! double) continue;
      final y = (e.value as double).round();
      if (y >= 2000 && y <= 2100) yearCol[y] = columnOf(e.key);
    }
  }
  if (yearCol.isEmpty) return _failed('En «Resumen» no encuentro los años.');
  final years = yearCol.keys.toList()..sort();
  final detailYear = years.last;

  double cell(int col, int row, String what) {
    final v = resumen[refOf(col, row)];
    if (v == null) return 0;
    if (v is double) return v;
    problems.add('«Resumen» ${refOf(col, row)} ($what) no es un número: «$v»');
    return 0;
  }

  final summary = <YearMonth, (int, int)>{};
  for (final y in years) {
    for (var m = 0; m < 12; m++) {
      final row = janRow + m;
      final normal = minutesOf(cell(yearCol[y]!, row, 'normales'));
      final festive = minutesOf(cell(yearCol[y]! + 1, row, 'festivas'));
      if (normal < 0 || festive < 0) {
        problems.add('${monthNames[m]} $y tiene horas negativas');
      }
      if (normal + festive > 0) {
        summary[YearMonth(y, m + 1)] = (normal, festive);
      }
    }
  }

  // ---- Hojas de meses: los días del año de detalle -----------------------
  final days = <DayEntry>[];
  for (var m = 0; m < 12; m++) {
    final sheet = book[monthNames[m]];
    if (sheet == null) {
      notes.add('No hay hoja «${monthNames[m]}»: ese mes queda sin días.');
      continue;
    }
    int? normalCol;
    int? festiveCol;
    int? reasonCol;
    for (final e in sheet.entries) {
      if (rowOf(e.key) != 1 || e.value is! String) continue;
      final h = (e.value as String).trim().toLowerCase();
      if (h == 'horas extra') normalCol = columnOf(e.key);
      if (h == 'horas extra festivas') festiveCol = columnOf(e.key);
      if (h == 'motivo') reasonCol = columnOf(e.key);
    }
    if (normalCol == null || festiveCol == null) {
      problems.add('En «${monthNames[m]}» no encuentro las columnas de horas.');
      continue;
    }
    final inMonth = DateTime(detailYear, m + 2, 0).day;
    // Los días van en las filas 2 a 32 (día 1 a 31); debajo, totales y
    // notas del propio Excel, que no son días.
    for (var row = 2; row <= 32; row++) {
      final dayCell = sheet[refOf(0, row)];
      final where = '${monthNames[m]} fila $row';
      final n = sheet[refOf(normalCol, row)];
      final f = sheet[refOf(festiveCol, row)];
      var reason = reasonCol == null ? null : sheet[refOf(reasonCol, row)];
      double hours(Object? v, String col) {
        if (v == null) return 0;
        if (v is double) return v;
        // Un texto en la columna de horas: es un motivo mal colocado.
        final current = reason;
        if (current == null || (current is String && current.trim().isEmpty)) {
          reason = v;
          notes.add('$where: «$v» estaba en $col; pasa a Motivo');
        } else {
          notes.add('$where: «$v» en $col se descarta (ya hay motivo)');
        }
        return 0;
      }

      final normal = minutesOf(hours(n, 'horas normales'));
      final festive = minutesOf(hours(f, 'horas festivas'));
      if (normal == 0 && festive == 0) {
        if (reason is String && (reason as String).trim().isNotEmpty) {
          notes.add('$where: motivo sin horas («$reason»), se descarta');
        }
        continue;
      }
      if (dayCell is! double || dayCell != dayCell.roundToDouble()) {
        problems.add('$where: hay horas pero el día no es un número');
        continue;
      }
      final day = dayCell.round();
      if (day != row - 1 || day < 1 || day > inMonth) {
        problems.add('$where: el día $day no encaja en ${monthNames[m]}');
        continue;
      }
      if (normal < 0 || festive < 0) {
        problems.add('$where: horas negativas');
        continue;
      }
      // Un día solo tiene un tipo: con las dos, todo festivo (RF-15).
      final kind = festive > 0 ? DayKind.festive : DayKind.normal;
      if (normal > 0 && festive > 0) {
        notes.add(
          '$where: normales y festivas a la vez; se guarda todo como festivo',
        );
      }
      var text = reason is String ? (reason as String).trim() : null;
      if (text != null && text.isEmpty) text = null;
      if (text != null && text.length > maxReasonLength) {
        notes.add('$where: motivo de más de $maxReasonLength letras, se corta');
        text = text.substring(0, maxReasonLength).trimRight();
      }
      try {
        days.add(
          DayEntry(
            date: DateTime(detailYear, m + 1, day),
            minutes: normal + festive,
            kind: kind,
            reason: text,
          ),
        );
      } on ArgumentError catch (e) {
        problems.add('$where: ${e.message}');
      }
    }
  }

  // ---- Comprobaciones ------------------------------------------------------
  // Año de detalle: la suma de los días de cada mes frente a «Resumen».
  for (var m = 1; m <= 12; m++) {
    final ym = YearMonth(detailYear, m);
    var normal = 0;
    var festive = 0;
    for (final d in days.where((d) => d.date.month == m)) {
      d.kind == DayKind.festive ? festive += d.minutes : normal += d.minutes;
    }
    final (sn, sf) = summary[ym] ?? (0, 0);
    if (normal != sn || festive != sf) {
      problems.add(
        '${_ym(ym)}: los días suman ${_h(normal)} normales y ${_h(festive)} '
        'festivas, pero «Resumen» dice ${_h(sn)} y ${_h(sf)}',
      );
    }
  }
  final imported = [
    for (final e in summary.entries)
      if (e.key.year < detailYear) ImportedMonth(e.key, e.value.$1, e.value.$2),
  ]..sort((a, b) => a.month.compareTo(b.month));

  // Cada año: lo importado frente a «Total anual».
  for (final y in years) {
    final (normal, festive) = y == detailYear
        ? days.fold(
            (0, 0),
            (s, d) => d.kind == DayKind.festive
                ? (s.$1, s.$2 + d.minutes)
                : (s.$1 + d.minutes, s.$2),
          )
        : imported.where((i) => i.month.year == y).fold((
            0,
            0,
          ), (s, i) => (s.$1 + i.normalMinutes, s.$2 + i.festiveMinutes));
    final tn = minutesOf(cell(yearCol[y]!, totalRow, 'total normales'));
    final tf = minutesOf(cell(yearCol[y]! + 1, totalRow, 'total festivas'));
    final same = normal == tn && festive == tf;
    checks.add(
      '$y: importado ${_h(normal)} normales y ${_h(festive)} festivas; '
      '«Total anual» ${_h(tn)} y ${_h(tf)} → ${same ? 'cuadra' : 'NO CUADRA'}',
    );
    if (!same) problems.add('$y no cuadra con el «Total anual» del Excel');
  }

  // ---- Estados y tarifas ---------------------------------------------------
  final withHours = {
    for (final i in imported) i.month,
    for (final d in days) YearMonth.of(d.date),
  }.toList()..sort();
  final records = [
    for (final m in withHours)
      if (m.compareTo(paidUntil) <= 0)
        MonthRecord(
          m,
          deliveredOn: DateTime(m.year, m.month + 1, 0),
          paidOn: DateTime(m.year, m.month + 1, 0),
        ),
  ];
  final rates = [
    Rate(DayKind.normal, rateStart, normalRateCents),
    Rate(DayKind.festive, rateStart, festiveRateCents),
  ];
  return ExcelImport(
    detailYear: detailYear,
    days: days,
    imported: imported,
    records: records,
    rates: rates,
    notes: notes,
    problems: problems,
    checks: checks,
  );
}

ExcelImport _failed(String problem) => ExcelImport(
  detailYear: 0,
  days: const [],
  imported: const [],
  records: const [],
  rates: const [],
  notes: const [],
  problems: [problem],
  checks: const [],
);
