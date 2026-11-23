// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/first_steps_store.dart';

/// Recuerda lo que no se puede calcular de la tarjeta «Primeros pasos»:
/// si se ha visto Festivos y si la tarjeta está cerrada (024).
class FirstStepsController extends ChangeNotifier {
  FirstStepsController({
    required Future<FirstStepsState> Function() load,
    required Future<void> Function(FirstStepsState) save,
  }) : _load = load,
       _save = save;

  factory FirstStepsController.withStore(FirstStepsStore store) =>
      FirstStepsController(load: store.load, save: store.save);

  final Future<FirstStepsState> Function() _load;
  final Future<void> Function(FirstStepsState) _save;

  FirstStepsState _state = const FirstStepsState();
  FirstStepsState get state => _state;

  bool _loaded = false;

  /// Hasta leer el archivo no se enseña la tarjeta, para que no aparezca y
  /// desaparezca al arrancar.
  bool get loaded => _loaded;

  Future<void> load() async {
    _state = await _load();
    _loaded = true;
    notifyListeners();
  }

  /// Se ha abierto la pantalla de Festivos (RF-4).
  Future<void> markHolidaysSeen() => _set(_state.copyWith(holidaysSeen: true));

  /// «Ocultar», o las cuatro hechas (RF-7, RF-8).
  Future<void> close() => _set(_state.copyWith(closed: true));

  Future<void> _set(FirstStepsState s) async {
    if (s == _state) return;
    _state = s;
    notifyListeners();
    try {
      await _save(s);
    } on FileSystemException {
      // Sin poder guardar, vale lo de memoria hasta cerrar la app (RF-10).
    }
  }
}
