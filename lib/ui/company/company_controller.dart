// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';

import '../../data/company_repository.dart';
import '../../domain/company.dart';

/// La empresa y la antigüedad (026). Cada cambio se guarda y se vuelve a
/// leer, así lo que se ve es lo que hay.
class CompanyController extends ChangeNotifier {
  CompanyController({
    required CompanyRepository repository,
    DateTime Function()? clock,
    Future<void> Function()? onChanged,
  }) : _repo = repository,
       _clock = clock ?? DateTime.now,
       _onChanged = onChanged;

  final CompanyRepository _repo;
  final DateTime Function() _clock;

  /// Avisa a las copias de que hay cambios sin copiar (RF-9).
  final Future<void> Function()? _onChanged;

  Company company = Company.empty;

  /// Un guardado ha fallado; se avisa en pantalla.
  bool saveFailed = false;

  bool _disposed = false;

  DateTime get today {
    final n = _clock();
    return DateTime(n.year, n.month, n.day);
  }

  /// La antigüedad a hoy; nula sin fecha de alta (RF-4, RF-5).
  Seniority? get seniority {
    final start = company.start;
    return start == null ? null : Seniority.between(start, today);
  }

  Future<void> load() async {
    try {
      company = await _repo.company();
    } catch (_) {
      // Sin poder leerla, se queda vacía: no se muestra nada.
    }
    _notify();
  }

  /// Guarda [c] en lugar de la empresa actual (RF-2, RF-6). Devuelve falso
  /// si no se ha podido.
  Future<bool> save(Company c) async {
    if (c == company) return true;
    try {
      await _repo.save(c);
      company = c;
      saveFailed = false;
    } catch (_) {
      saveFailed = true; // sin datos personales en ningún registro
    }
    _notify();
    if (!saveFailed) await _onChanged?.call().catchError((Object _) {});
    return !saveFailed;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
