import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'haptics.dart';

/// Aviso con «Deshacer» que ha mostrado una pantalla. Sirve para quitarlo al
/// cerrarla sin tocar los avisos de otras pantallas.
class UndoHandle {
  UndoHandle._(this._messenger, this._controller) {
    _controller.closed.whenComplete(() => _open = false);
  }

  final ScaffoldMessengerState _messenger;
  final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _controller;
  bool _open = true;

  /// Quita el aviso solo si sigue en pantalla. Como cada aviso sustituye al
  /// anterior, si sigue abierto es el que se está viendo.
  void dismiss() {
    if (_open) {
      _open = false;
      _messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.remove);
    }
  }
}

/// Sistema de edición de toda la app (RF-20): los cambios ya están guardados
/// y este aviso permite deshacer el último durante 5 segundos.
///
/// Sustituye a cualquier aviso anterior, para que «Deshacer» siempre se
/// refiera al último cambio. La pantalla que lo muestra guarda el
/// [UndoHandle] y lo quita al cerrarse; además, si ya se cerró, el aviso no
/// hace nada.
UndoHandle showUndo(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
}) {
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  final controller = messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: Motion.undo,
      // Con acción, Flutter lo dejaría fijo; aquí debe irse solo.
      persist: false,
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () {
          if (!context.mounted) return;
          Haptics.tap();
          onUndo();
        },
      ),
    ),
  );
  return UndoHandle._(messenger, controller);
}
