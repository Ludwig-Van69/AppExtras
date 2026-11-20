import 'package:flutter/material.dart';

/// Tipos de dato que tienen color propio.
enum DataKind { normal, festive, vacation, bag }

/// Colores de un tipo de dato.
@immutable
class KindColors {
  const KindColors({
    required this.strong,
    required this.onStrong,
    required this.soft,
    Color? fill,
    Color? onFill,
  }) : fill = fill ?? strong,
       onFill = onFill ?? onStrong;

  /// Color principal: botones seleccionados, cifras y textos.
  final Color strong;

  /// Texto encima de [strong].
  final Color onStrong;

  /// Relleno de baldosas y muestras. Igual que [strong] salvo en las
  /// vacaciones, cuyo amarillo vivo no sirve como texto (013, RF-8).
  final Color fill;

  /// Texto encima de [fill].
  final Color onFill;

  /// Color suave: el agua de la Marea y fondos tenues.
  final Color soft;

  KindColors lerp(KindColors other, double t) => KindColors(
    strong: Color.lerp(strong, other.strong, t)!,
    onStrong: Color.lerp(onStrong, other.onStrong, t)!,
    soft: Color.lerp(soft, other.soft, t)!,
    fill: Color.lerp(fill, other.fill, t)!,
    onFill: Color.lerp(onFill, other.onFill, t)!,
  );
}

/// Paleta del estilo «Marea», en versión clara y oscura.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.text,
    required this.textSoft,
    required this.line,
    required this.outline,
    required this.empty,
    required this.error,
    required this.normal,
    required this.festive,
    required this.vacation,
    required this.bag,
    required this.medals,
  });

  final Color background;
  final Color surface;
  final Color text;
  final Color textSoft;

  /// Separadores decorativos.
  final Color line;

  /// Bordes de campos y botones: deben verse sobre el fondo.
  final Color outline;

  /// Baldosa del Mosaico sin datos.
  final Color empty;
  final Color error;

  final KindColors normal;
  final KindColors festive;
  final KindColors vacation;
  final KindColors bag;

  /// Trofeos de oro, plata y bronce de Métricas (018, RF-6), con contraste
  /// de al menos 3:1 sobre el fondo.
  final List<Color> medals;

  KindColors of(DataKind kind) => switch (kind) {
    DataKind.normal => normal,
    DataKind.festive => festive,
    DataKind.vacation => vacation,
    DataKind.bag => bag,
  };

  static const light = AppColors(
    medals: [Color(0xFF9A7300), Color(0xFF66747B), Color(0xFF9A5A2B)],
    background: Color(0xFFF2F8F8),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF0F2A30),
    textSoft: Color(0xFF4A646A),
    line: Color(0xFFCADCDE),
    outline: Color(0xFF6C868B),
    empty: Color(0xFFE0ECED),
    error: Color(0xFFB3261E),
    normal: KindColors(
      strong: Color(0xFF0B6E78),
      onStrong: Color(0xFFFFFFFF),
      soft: Color(0xFFBDE7E3),
    ),
    festive: KindColors(
      strong: Color(0xFFB23C16),
      onStrong: Color(0xFFFFFFFF),
      soft: Color(0xFFFFD6C4),
    ),
    // Amarillo (013, RF-8): relleno vivo con letra oscura; como texto, un
    // dorado oscuro que se lee sobre el fondo claro.
    vacation: KindColors(
      strong: Color(0xFF806400),
      onStrong: Color(0xFFFFFFFF),
      soft: Color(0xFFFFF0A6),
      fill: Color(0xFFF5C400),
      onFill: Color(0xFF2B2300),
    ),
    bag: KindColors(
      strong: Color(0xFF5546C0),
      onStrong: Color(0xFFFFFFFF),
      soft: Color(0xFFDEDAFF),
    ),
  );

  static const dark = AppColors(
    medals: [Color(0xFFF2C14E), Color(0xFFC3CED3), Color(0xFFD9955F)],
    background: Color(0xFF0A1D24),
    surface: Color(0xFF12303A),
    text: Color(0xFFEAF6F6),
    textSoft: Color(0xFFA5BEC2),
    line: Color(0xFF27424B),
    outline: Color(0xFF6A8990),
    empty: Color(0xFF1A3A44),
    error: Color(0xFFFFB4AB),
    normal: KindColors(
      strong: Color(0xFF62D8D1),
      onStrong: Color(0xFF06262A),
      soft: Color(0xFF0F4752),
    ),
    festive: KindColors(
      strong: Color(0xFFFF9B73),
      onStrong: Color(0xFF2B0F05),
      soft: Color(0xFF76302A),
    ),
    vacation: KindColors(
      strong: Color(0xFFFFD84D),
      onStrong: Color(0xFF2A2200),
      soft: Color(0xFF4A4210),
    ),
    bag: KindColors(
      strong: Color(0xFFB8ABFF),
      onStrong: Color(0xFF1B1240),
      soft: Color(0xFF2E2763),
    ),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: c(background, other.background),
      surface: c(surface, other.surface),
      text: c(text, other.text),
      textSoft: c(textSoft, other.textSoft),
      line: c(line, other.line),
      outline: c(outline, other.outline),
      empty: c(empty, other.empty),
      error: c(error, other.error),
      normal: normal.lerp(other.normal, t),
      festive: festive.lerp(other.festive, t),
      vacation: vacation.lerp(other.vacation, t),
      bag: bag.lerp(other.bag, t),
      medals: [
        for (var i = 0; i < medals.length; i++) c(medals[i], other.medals[i]),
      ],
    );
  }
}

extension AppColorsContext on BuildContext {
  /// Paleta del tema actual.
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
