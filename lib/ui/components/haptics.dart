import 'package:flutter/services.dart';

/// Vibraciones ligeras al apuntar, borrar, deshacer o cambiar de día (RF-29).
/// Usan la vibración del sistema, que no necesita permisos y respeta los
/// ajustes del móvil.
abstract final class Haptics {
  /// Apuntar o deshacer.
  static Future<void> tap() => HapticFeedback.lightImpact();

  /// Cambiar de día.
  static Future<void> select() => HapticFeedback.selectionClick();

  /// Borrar.
  static Future<void> delete() => HapticFeedback.mediumImpact();
}
