/// Festivos: los de serie, los propios del usuario y el calendario que dice
/// si un día lo es (004).
library;

/// De dónde viene un festivo: nacional (de serie) o añadido por el usuario
/// (autonómicos, locales y traslados; 004, RF-2).
enum HolidayGroup { national, custom }

/// Un festivo. Tiene una sola de estas formas: cada año el mismo día
/// ([month] y [day]), relativo a la Pascua ([easterOffset]) o una fecha
/// concreta de un solo año ([date]).
class Holiday {
  const Holiday.fixed(
    this.id,
    this.name,
    this.group,
    int this.month,
    int this.day,
  ) : easterOffset = null,
      date = null;

  const Holiday.easter(this.id, this.name, this.group, int this.easterOffset)
    : month = null,
      day = null,
      date = null;

  Holiday.once(
    this.id,
    this.name,
    DateTime d, {
    this.group = HolidayGroup.custom,
  }) : month = null,
       day = null,
       easterOffset = null,
       date = DateTime(d.year, d.month, d.day);

  final String id;
  final String name;
  final HolidayGroup group;
  final int? month;
  final int? day;

  /// Días respecto al Domingo de Pascua (Viernes Santo = -2).
  final int? easterOffset;
  final DateTime? date;

  bool get isCustom => group == HolidayGroup.custom;

  /// El día en que cae en [year]; nulo si no existe (29 de febrero).
  DateTime? dateIn(int year) {
    if (date != null) return date!.year == year ? date : null;
    if (easterOffset != null) {
      final e = easterSunday(year);
      return DateTime(e.year, e.month, e.day + easterOffset!);
    }
    final d = DateTime(year, month!, day!);
    return d.month == month ? d : null;
  }
}

/// Domingo de Pascua (calendario gregoriano, algoritmo de Meeus/Jones/Butcher).
DateTime easterSunday(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = (h + l - 7 * m + 114) % 31 + 1;
  return DateTime(year, month, day);
}

/// Los festivos que trae la app: solo los 10 nacionales comunes a toda
/// España (004, RF-2). Los autonómicos, los locales y los traslados cambian
/// según el sitio, así que los añade el usuario.
final builtInHolidays = <Holiday>[
  const Holiday.fixed(
    'nat-ano-nuevo',
    'Año Nuevo',
    HolidayGroup.national,
    1,
    1,
  ),
  const Holiday.fixed('nat-reyes', 'Reyes', HolidayGroup.national, 1, 6),
  const Holiday.easter(
    'nat-viernes-santo',
    'Viernes Santo',
    HolidayGroup.national,
    -2,
  ),
  const Holiday.fixed(
    'nat-trabajo',
    'Fiesta del Trabajo',
    HolidayGroup.national,
    5,
    1,
  ),
  const Holiday.fixed('nat-asuncion', 'Asunción', HolidayGroup.national, 8, 15),
  const Holiday.fixed(
    'nat-hispanidad',
    'Fiesta Nacional',
    HolidayGroup.national,
    10,
    12,
  ),
  const Holiday.fixed(
    'nat-santos',
    'Todos los Santos',
    HolidayGroup.national,
    11,
    1,
  ),
  const Holiday.fixed(
    'nat-constitucion',
    'Constitución',
    HolidayGroup.national,
    12,
    6,
  ),
  const Holiday.fixed(
    'nat-inmaculada',
    'Inmaculada',
    HolidayGroup.national,
    12,
    8,
  ),
  const Holiday.fixed('nat-navidad', 'Navidad', HolidayGroup.national, 12, 25),
];

/// Dice si un día es festivo, según los de serie activos y los propios.
class HolidayCalendar {
  HolidayCalendar({
    Set<String> disabled = const {},
    List<Holiday> custom = const [],
  }) : holidays = [...builtInHolidays, ...custom],
       disabled = Set.unmodifiable(disabled);

  /// Todos, activos o no.
  final List<Holiday> holidays;

  /// Identificadores de los desactivados.
  final Set<String> disabled;

  bool isEnabled(Holiday h) => !disabled.contains(h.id);

  /// El festivo activo de ese día, o nulo si no es festivo.
  Holiday? holidayOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    for (final h in holidays) {
      if (isEnabled(h) && h.dateIn(d.year) == d) return h;
    }
    return null;
  }
}
