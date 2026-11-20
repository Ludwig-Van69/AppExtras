import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'tokens.dart';

/// Familias de letra incluidas en la app.
abstract final class Fonts {
  static const display = 'Bricolage Grotesque';
  static const body = 'Figtree';
}

/// Estilos de texto del sistema. El color lo pone el tema o quien los use.
abstract final class AppText {
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle _display(double size, FontWeight weight) => TextStyle(
    fontFamily: Fonts.display,
    fontSize: size,
    fontWeight: weight,
    // Fuente variable: el grosor y el tamaño óptico se fijan con sus ejes.
    fontVariations: [
      FontVariation.weight(weight.value.toDouble()),
      FontVariation('opsz', size.clamp(12, 96).toDouble()),
    ],
    fontFeatures: _tabular,
    height: 1.05,
  );

  static TextStyle _body(double size, FontWeight weight) => TextStyle(
    fontFamily: Fonts.body,
    fontSize: size,
    fontWeight: weight,
    fontVariations: [FontVariation.weight(weight.value.toDouble())],
    fontFeatures: _tabular,
    height: 1.35,
  );

  /// La cifra grande de horas.
  // Grosores contenidos: la jerarquía la dan el tamaño y el color, no la
  // negrita (pasada estética «unslop»). 600 como mucho.
  static final hero = _display(
    TextSizes.hero,
    FontWeight.w600,
  ).copyWith(letterSpacing: -3, height: 1.0);
  static final display = _display(TextSizes.display, FontWeight.w600);
  static final title = _display(TextSizes.title, FontWeight.w600);

  /// Cifras de los resúmenes (euros, días, horas).
  static final figure = _display(TextSizes.figure, FontWeight.w600);
  static final body = _body(TextSizes.body, FontWeight.w400);
  static final bodyStrong = _body(TextSizes.body, FontWeight.w600);
  static final label = _body(TextSizes.label, FontWeight.w500);
  static final caption = _body(TextSizes.caption, FontWeight.w500);
}

/// Monta el tema de Flutter a partir de la paleta y las medidas.
abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.normal.strong,
      onPrimary: c.normal.onStrong,
      secondary: c.bag.strong,
      onSecondary: c.bag.onStrong,
      error: c.error,
      onError: brightness == Brightness.light
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF410002),
      surface: c.surface,
      onSurface: c.text,
      onSurfaceVariant: c.textSoft,
      outline: c.outline,
      outlineVariant: c.line,
      inverseSurface: c.text,
      onInverseSurface: c.background,
      inversePrimary: c.normal.soft,
    );

    final textTheme = TextTheme(
      displayLarge: AppText.hero,
      displaySmall: AppText.display,
      titleLarge: AppText.title,
      titleMedium: AppText.bodyStrong,
      bodyLarge: AppText.body,
      bodyMedium: AppText.body,
      labelLarge: AppText.label,
      labelMedium: AppText.caption,
      bodySmall: AppText.caption,
    ).apply(bodyColor: c.text, displayColor: c.text);

    // Botones y campos con esquina de control; la píldora queda para lo que
    // se elige (Hoy, Ayer…).
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.control),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      fontFamily: Fonts.body,
      textTheme: textTheme,
      extensions: [c],
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: c.line,
        surfaceTintColor: Colors.transparent,
        titleSpacing: Space.gutter,
        titleTextStyle: AppText.title.copyWith(color: c.text),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(Sizes.touch, Sizes.touch),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          shape: shape,
          textStyle: AppText.label,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(Sizes.touch, Sizes.touch),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          shape: shape,
          side: BorderSide(color: c.outline),
          foregroundColor: c.text,
          textStyle: AppText.label,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(Sizes.touch, Sizes.touch),
          foregroundColor: c.text,
          textStyle: AppText.label,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(Sizes.touch, Sizes.touch),
          foregroundColor: c.text,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        labelStyle: AppText.label.copyWith(color: c.textSoft),
        floatingLabelStyle: AppText.label.copyWith(color: c.text),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.l,
          vertical: Space.m,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: c.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: c.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: c.normal.strong, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.control),
          borderSide: BorderSide(color: c.error),
        ),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.medium),
          side: BorderSide(color: c.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sheet),
        ),
        titleTextStyle: AppText.title.copyWith(color: c.text),
        contentTextStyle: AppText.body.copyWith(color: c.text),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: c.text,
        contentTextStyle: AppText.body.copyWith(color: c.background),
        actionTextColor: c.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.medium),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.background,
        indicatorColor: c.normal.soft,
        height: Sizes.navBar,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => AppText.caption.copyWith(
            color: states.contains(WidgetState.selected) ? c.text : c.textSoft,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? c.text : c.textSoft,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(Sizes.touch, Sizes.touch),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: Space.s),
          ),
          textStyle: WidgetStatePropertyAll(AppText.label),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.control),
            ),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: c.outline)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? c.text : c.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? c.background : c.text,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: Space.m,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
        titleTextStyle: AppText.body.copyWith(color: c.text),
        subtitleTextStyle: AppText.caption.copyWith(color: c.textSoft),
        iconColor: c.textSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.medium),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: AppText.body.copyWith(color: c.text),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.surface),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.medium),
            ),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.normal.strong,
      ),
    );
  }
}

/// Elección de tema del usuario.
enum ThemeChoice {
  system('Automático', ThemeMode.system),
  light('Claro', ThemeMode.light),
  dark('Oscuro', ThemeMode.dark);

  const ThemeChoice(this.label, this.mode);
  final String label;
  final ThemeMode mode;
}

/// La elección de tema. La app la guarda en las preferencias y la lee al
/// abrirse (009, RF-10).
class ThemeController extends ValueNotifier<ThemeChoice> {
  ThemeController([super.value = ThemeChoice.system]);
}

/// Da acceso al [ThemeController] desde cualquier pantalla.
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()!.notifier!;
}

extension MotionContext on BuildContext {
  /// Devuelve [duration], o cero si el móvil tiene las animaciones
  /// desactivadas o reducidas (RF-10).
  Duration motion(Duration duration) =>
      MediaQuery.maybeDisableAnimationsOf(this) ?? false
      ? Duration.zero
      : duration;
}
