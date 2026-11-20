import 'day_kind.dart';
import 'money.dart';

/// Máximo de un mes del Excel por tipo: 31 días de 24 horas, en minutos.
const maxImportedMinutes = 31 * 24 * 60;

/// Un mes que viene del Excel solo como total, sin días (016, RF-1).
class ImportedMonth {
  ImportedMonth(this.month, this.normalMinutes, this.festiveMinutes) {
    for (final (name, v) in [
      ('normalMinutes', normalMinutes),
      ('festiveMinutes', festiveMinutes),
    ]) {
      if (v < 0 || v > maxImportedMinutes) {
        throw ArgumentError.value(v, name, 'fuera de rango');
      }
    }
    if (normalMinutes + festiveMinutes == 0) {
      throw ArgumentError('un mes del Excel debe tener horas');
    }
  }

  final YearMonth month;
  final int normalMinutes;
  final int festiveMinutes;

  int get totalMinutes => normalMinutes + festiveMinutes;

  int minutesOf(DayKind kind) =>
      kind == DayKind.festive ? festiveMinutes : normalMinutes;

  @override
  bool operator ==(Object other) =>
      other is ImportedMonth &&
      other.month == month &&
      other.normalMinutes == normalMinutes &&
      other.festiveMinutes == festiveMinutes;

  @override
  int get hashCode => Object.hash(month, normalMinutes, festiveMinutes);
}

/// Un mes del Excel con la tarifa de cada tipo vigente el día 1 del mes
/// (016, RF-2). Una tarifa nula: no había ninguna ese día.
class PricedImport {
  const PricedImport(this.month, this.normalRate, this.festiveRate);
  final ImportedMonth month;
  final int? normalRate;
  final int? festiveRate;

  int? rateOf(DayKind kind) =>
      kind == DayKind.festive ? festiveRate : normalRate;

  /// Céntimos × minutos de un tipo, sin redondear; 0 si no tiene tarifa.
  int weightOf(DayKind kind) => (rateOf(kind) ?? 0) * month.minutesOf(kind);
}
