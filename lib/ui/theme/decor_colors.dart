import 'package:flutter/material.dart';

/// Colores de los dibujos de temporada (013, RF-9). Solo decoran: nunca
/// llevan texto encima ni dan significado a un dato.
@immutable
class DecorColors {
  const DecorColors({
    required this.gold,
    required this.red,
    required this.green,
    required this.snow,
    required this.purple,
    required this.pink,
    required this.orange,
    required this.blue,
    required this.ink,
    required this.paper,
  });

  final Color gold;
  final Color red;
  final Color green;
  final Color snow;
  final Color purple;
  final Color pink;
  final Color orange;
  final Color blue;

  /// Trazos neutros (murciélago, leña).
  final Color ink;

  /// Blanco del dibujo (pompón y borde del gorro): el de la superficie.
  final Color paper;

  static const light = DecorColors(
    gold: Color(0xFFC99A00),
    red: Color(0xFFC8402A),
    green: Color(0xFF2E7D5B),
    snow: Color(0xFF9FC3CC),
    purple: Color(0xFF6A4BC4),
    pink: Color(0xFFD6457E),
    orange: Color(0xFFE07A1F),
    blue: Color(0xFF2C7FB8),
    ink: Color(0xFF4A646A),
    paper: Color(0xFFFFFFFF),
  );

  static const dark = DecorColors(
    gold: Color(0xFFFFD84D),
    red: Color(0xFFFF8A73),
    green: Color(0xFF6BD3A0),
    snow: Color(0xFFCFE6EC),
    purple: Color(0xFFB8ABFF),
    pink: Color(0xFFFF8DB8),
    orange: Color(0xFFFFB15C),
    blue: Color(0xFF7CC4F2),
    ink: Color(0xFFA5BEC2),
    paper: Color(0xFF12303A),
  );

  static DecorColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Si los calendarios llevan sus dibujos de temporada (013, RF-11). Activado
/// de serie; la app lo guarda en las preferencias.
class CalendarDecorController extends ValueNotifier<bool> {
  CalendarDecorController([super.value = true]);
}

/// Da acceso al [CalendarDecorController]. Sin él, los dibujos se ven.
class CalendarDecorScope extends InheritedNotifier<CalendarDecorController> {
  const CalendarDecorScope({
    super.key,
    required CalendarDecorController controller,
    required super.child,
  }) : super(notifier: controller);

  static CalendarDecorController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CalendarDecorScope>()
      ?.notifier;

  static bool enabled(BuildContext context) => maybeOf(context)?.value ?? true;
}
