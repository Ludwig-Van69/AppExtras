/// Las cantidades de horas que puede elegir el usuario, en minutos.
library;

/// Los nueve botones, iguales para días normales y festivos (RF-6).
const presetMinutes = [60, 90, 120, 150, 180, 210, 240, 270, 300];

/// Lo que ofrece «Otra»: de 0,5 a 24 h en medias horas (RF-8).
final List<int> otherMinutes = [for (var m = 30; m <= 1440; m += 30) m];

/// Si [minutes] es una elección válida del usuario.
bool isValidChoice(int minutes) =>
    minutes >= 30 && minutes <= 1440 && minutes % 30 == 0;

/// El botón que queda marcado para un total, o nulo si no es de los
/// botones (RF-9).
int? selectedPreset(int minutes) =>
    presetMinutes.contains(minutes) ? minutes : null;

/// Si se marca «Otra»: el día tiene horas, pero no son de ningún botón.
bool isOtherSelected(int minutes) =>
    minutes > 0 && selectedPreset(minutes) == null;
