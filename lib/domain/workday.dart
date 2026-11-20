/// Jornada de 39 h a la semana: de lunes a jueves 8 h y el viernes 7 h
/// (020). Sirve para librar un día completo con horas guardadas.
library;

/// Recordatorio de la jornada (020, RF-1).
const workdayReminder = 'Jornada de 39 h: de lunes a jueves 8 h, viernes 7 h.';

/// Minutos de jornada de [date]: 480 de lunes a jueves, 420 el viernes y 0
/// el fin de semana (020, RF-2, RF-3).
int workdayMinutes(DateTime date) => switch (date.weekday) {
  DateTime.friday => 420,
  DateTime.saturday || DateTime.sunday => 0,
  _ => 480,
};
