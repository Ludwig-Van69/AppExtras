import '../../data/backup_diff.dart';
import '../../domain/company.dart';
import '../../domain/day_entry.dart';
import '../../domain/day_kind.dart';
import '../../domain/extras.dart';
import '../../domain/money.dart';
import '../../domain/vacations.dart';
import '../format.dart';

/// Cuántas cosas se enseñan como mucho en cada apartado (025, RF-12c).
const diffLinesShown = 20;

/// Una línea del detalle: qué cosa es y cómo está aquí y en la copia
/// (025, RF-12b). «—» si en ese lado no está.
class DiffLine {
  const DiffLine(this.what, this.here, this.there);
  final String what;
  final String here;
  final String there;
}

const _none = '—';

/// Las líneas de un apartado, en el orden de la comparación (por fecha).
/// Con [hideAmounts], los euros salen como «•••• €» (RF-12d).
List<DiffLine> diffLines(
  BackupDiff d,
  DiffSection section, {
  bool hideAmounts = false,
}) {
  String euros(int cents) => hideAmounts ? '•••• €' : formatEuros(cents);
  String side<T>(T? x, String Function(T) text) => x == null ? _none : text(x);

  switch (section) {
    case DiffSection.hours:
      return [
        for (final p in d.days)
          DiffLine(
            shortDate((p.here ?? p.there)!.date),
            side(p.here, _day),
            side(p.there, _day),
          ),
      ];
    case DiffSection.vacation:
      return [
        for (final p in d.vacationDays)
          DiffLine(
            shortDate((p.here ?? p.there)!.date),
            side(p.here, _vacationDay),
            side(p.there, _vacationDay),
          ),
        if (d.vacationSettings case final p?) _settingsLine(p.here, p.there),
      ];
    case DiffSection.extras:
      return [
        for (final p in d.items)
          DiffLine(
            '${(p.here ?? p.there)!.concept} · '
            '${shortDate((p.here ?? p.there)!.date)}',
            side(p.here, (e) => _item(e, euros)),
            side(p.there, (e) => _item(e, euros)),
          ),
      ];
    case DiffSection.saved:
      return [
        for (final p in d.savedMoves)
          DiffLine(
            '${shortDate((p.here ?? p.there)!.date)} · '
            '${(p.here ?? p.there)!.kind.label}',
            side(p.here, (m) => '${formatMinutes(m.minutes)} h'),
            side(p.there, (m) => '${formatMinutes(m.minutes)} h'),
          ),
      ];
    case DiffSection.ratesAndMonths:
      return [
        for (final p in d.rates)
          DiffLine(
            'Tarifa ${(p.here ?? p.there)!.kind == DayKind.festive ? 'festiva' : 'normal'} '
            'desde ${shortDate((p.here ?? p.there)!.start)}',
            side(p.here, (r) => euros(r.cents)),
            side(p.there, (r) => euros(r.cents)),
          ),
        for (final p in d.months)
          DiffLine(
            monthYear(
              (p.here ?? p.there)!.month.year,
              (p.here ?? p.there)!.month.month,
            ),
            _monthStatus(p.here),
            _monthStatus(p.there),
          ),
      ];
    case DiffSection.imported:
      return [
        for (final p in d.importedMonths)
          DiffLine(
            monthYear(
              (p.here ?? p.there)!.month.year,
              (p.here ?? p.there)!.month.month,
            ),
            side(p.here, (m) => '${formatMinutes(m.totalMinutes)} h'),
            side(p.there, (m) => '${formatMinutes(m.totalMinutes)} h'),
          ),
      ];
    case DiffSection.company:
      final a = d.company?.here ?? Company.empty;
      final b = d.company?.there ?? Company.empty;
      return [
        if (a.name != b.name)
          DiffLine('Nombre de la empresa', a.name ?? _none, b.name ?? _none),
        if (a.start != b.start)
          DiffLine(
            'Fecha de alta',
            side(a.start, shortDate),
            side(b.start, shortDate),
          ),
      ];
  }
}

String _day(DayEntry e) {
  final reason = e.reason;
  return '${formatMinutes(e.minutes)} h'
      '${e.kind == DayKind.festive ? ' festiva' : ''}'
      '${reason == null || reason.isEmpty ? '' : ' · «$reason»'}';
}

/// «22 días al año» a cada lado; si eso coincide (cambia otra cosa, como un
/// año corregido a mano), «unos ajustes» y «otros».
DiffLine _settingsLine(VacationSettings? a, VacationSettings? b) {
  String text(VacationSettings? s) =>
      s == null ? _none : '${formatHalfDays(s.yearlyHalfDays)} días al año';
  final x = text(a);
  final y = text(b);
  return x == y
      ? const DiffLine('Ajustes de vacaciones', 'unos ajustes', 'otros')
      : DiffLine('Ajustes de vacaciones', x, y);
}

String _vacationDay(VacationDay v) => v.half ? 'medio día' : 'día entero';

String _item(ExtraItem e, String Function(int) euros) =>
    '${euros(e.cents)} ${extraStatusName(e.type, e.status).toLowerCase()}';

/// Un mes sin entregar no tiene registro: «abierto».
String _monthStatus(MonthRecord? m) => switch (m?.status) {
  MonthStatus.paid => 'cobrado',
  MonthStatus.delivered => 'entregado',
  _ => 'abierto',
};
