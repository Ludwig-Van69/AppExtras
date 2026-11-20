/// Texto del CSV que se abre con Excel en español (RF-19, RF-21).
library;

import 'day_entry.dart';
import 'day_kind.dart';
import 'extras.dart';
import 'imported_month.dart';
import 'money.dart';
import 'saved_hours.dart';
import 'vacations.dart';

/// Marca de inicio UTF-8: sin ella Excel estropea las tildes.
const _bom = '﻿';

/// Excel en español separa columnas con «;» y filas con CRLF.
const _sep = ';';
const _eol = '\r\n';

/// Nombre del archivo para el día [date], p. ej. `horas-2026-11-10.csv`.
/// Si ya existe alguno de [existing], añade `-2`, `-3`… para no pisarlo.
String csvFileName(DateTime date, {Set<String> existing = const {}}) {
  final base = 'horas-${dateKey(date)}';
  var name = '$base.csv';
  for (var n = 2; existing.contains(name); n++) {
    name = '$base-$n.csv';
  }
  return name;
}

/// Horas con coma decimal y como mucho 2 decimales, sin ceros de sobra
/// («2,5», «2», «0,33»). Es solo para leer: el dato exacto va en Minutos.
String csvHours(int minutes) {
  final cents = (minutes * 100 / 60).round();
  final whole = cents ~/ 100;
  final dec = (cents % 100)
      .toString()
      .padLeft(2, '0')
      .replaceFirst(RegExp(r'0$'), '');
  return dec.isEmpty || dec == '0' ? '$whole' : '$whole,$dec';
}

/// El CSV completo: cabecera y una fila por día, ordenadas por fecha. Si hay
/// [extras], van detrás, tras una línea vacía, con su propia cabecera (007,
/// RF-15). Igual los movimientos de las horas guardadas [savedMoves] (008,
/// RF-22), y las vacaciones: los días marcados y, si hay [vacation], los
/// días de cada año (010, RF-21).
String buildCsv(
  Iterable<DayEntry> entries, {
  Iterable<ExtraItem> extras = const [],
  Iterable<SavedMove> savedMoves = const [],
  Iterable<ImportedMonth> imported = const [],
  Iterable<MonthRecord> months = const [],
  Iterable<VacationDay> vacationDays = const [],
  VacationOverview? vacation,
}) {
  final sorted = entries.toList()..sort((a, b) => a.date.compareTo(b.date));
  final out = StringBuffer(_bom)
    ..write(['Fecha', 'Horas', 'Minutos', 'Tipo', 'Motivo'].join(_sep))
    ..write(_eol);
  for (final e in sorted) {
    out
      ..write(
        [
          _date(e.date),
          csvHours(e.minutes),
          '${e.minutes}',
          e.kind == DayKind.festive ? 'Festiva' : 'Normal',
          _field(e.reason ?? ''),
        ].join(_sep),
      )
      ..write(_eol);
  }
  if (extras.isNotEmpty) {
    final items = extras.toList()..sort((a, b) => a.date.compareTo(b.date));
    out
      ..write(_eol)
      ..write(
        [
          'Fecha',
          'Tipo',
          'Concepto',
          'Importe (€)',
          'Estado',
          'Cerrada el',
          'Pronto pago',
          'La paga la empresa',
        ].join(_sep),
      )
      ..write(_eol);
    for (final e in items) {
      out
        ..write(
          [
            _date(e.date),
            extraTypeName(e.type),
            _field(e.concept),
            // El importe completo; las dos columnas de detrás dicen si
            // cuenta la mitad o nada (019, RF-6).
            csvEuros(e.type == ExtraType.fine ? -e.cents : e.cents),
            extraStatusName(e.type, e.status),
            e.closedOn == null ? '' : _date(e.closedOn!),
            e.earlyPayment ? 'Sí' : '',
            e.companyPays ? 'Sí' : '',
          ].join(_sep),
        )
        ..write(_eol);
    }
  }
  if (imported.isNotEmpty) {
    // Meses del Excel: solo su total, sin días (016, RF-9).
    final statusOf = {for (final r in months) r.month: r.status};
    final sortedMonths = imported.toList()
      ..sort((a, b) => a.month.compareTo(b.month));
    out
      ..write(_eol)
      ..write(
        [
          'Mes del Excel',
          'Horas normales',
          'Horas festivas',
          'Estado',
        ].join(_sep),
      )
      ..write(_eol);
    for (final m in sortedMonths) {
      out
        ..write(
          [
            '${m.month.month.toString().padLeft(2, '0')}/${m.month.year}',
            csvHours(m.normalMinutes),
            csvHours(m.festiveMinutes),
            switch (statusOf[m.month] ?? MonthStatus.open) {
              MonthStatus.open => 'Abierto',
              MonthStatus.delivered => 'Entregado',
              MonthStatus.paid => 'Cobrado',
            },
          ].join(_sep),
        )
        ..write(_eol);
    }
  }
  if (savedMoves.isNotEmpty) {
    final moves = savedMoves.toList()..sort((a, b) => a.date.compareTo(b.date));
    out
      ..write(_eol)
      ..write(
        [
          'Fecha',
          'Cajón',
          'Movimiento',
          'Horas',
          'Minutos',
          'Importe cobrado (€)',
          'Nota',
        ].join(_sep),
      )
      ..write(_eol);
    for (final m in moves) {
      final sign = m.kind.isIn ? '' : '-';
      out
        ..write(
          [
            _date(m.date),
            m.box.label,
            m.kind.label,
            '$sign${csvHours(m.minutes)}',
            '${m.signedMinutes}',
            m.cents == null ? '' : csvEuros(m.cents!),
            _field(m.note ?? ''),
          ].join(_sep),
        )
        ..write(_eol);
    }
  }
  if (vacationDays.isNotEmpty) {
    final days = vacationDays.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    out
      ..write(_eol)
      ..write(['Vacaciones', 'Cuenta para el año', 'Medio día'].join(_sep))
      ..write(_eol);
    for (final d in days) {
      out
        ..write([_date(d.date), '${d.year}', d.half ? 'Sí' : ''].join(_sep))
        ..write(_eol);
    }
  }
  if (vacation != null) {
    out
      ..write(_eol)
      ..write(
        [
          'Año',
          'Días generados',
          'Días disfrutados',
          'Días que quedan',
        ].join(_sep),
      )
      ..write(_eol);
    for (final r in vacation.byOwnYear) {
      out
        ..write(
          [
            '${r.year}',
            csvHalfDays(r.generatedHalfDays),
            csvHalfDays(r.usedHalfDays),
            csvHalfDays(r.leftHalfDays),
          ].join(_sep),
        )
        ..write(_eol);
    }
  }
  return out.toString();
}

/// Medios días como días con coma: 21 → «10,5», −11 → «-5,5».
String csvHalfDays(int halfDays) {
  final sign = halfDays < 0 ? '-' : '';
  final abs = halfDays.abs();
  return '$sign${abs ~/ 2}${abs.isOdd ? ',5' : ''}';
}

/// Euros con coma decimal y signo, sin separador de miles («-100,00»), para
/// que Excel los lea como número.
String csvEuros(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  return '$sign${abs ~/ 100},${(abs % 100).toString().padLeft(2, '0')}';
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/'
    '${d.year.toString().padLeft(4, '0')}';

/// Entrecomilla un texto si lleva «;», comillas o saltos de línea.
/// Un texto que empieza por = + - o @ lo tomaría Excel como fórmula: va con
/// una comilla simple delante, que Excel no muestra (013, RF-19).
String _field(String text) {
  final s = RegExp(r'^[=+\-@]').hasMatch(text) ? "'$text" : text;
  return RegExp(r'[;"\r\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
}
