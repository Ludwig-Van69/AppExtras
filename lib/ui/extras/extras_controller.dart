import 'package:flutter/foundation.dart';

import '../../data/extras_repository.dart';
import '../../domain/extras.dart';

enum ExtrasStatus { loading, ready, error }

/// Estado de las multas y los extras (007). Igual que el dinero: cada cambio
/// se guarda y después se vuelve a leer todo, así lo que se ve es lo que hay.
class ExtrasController extends ChangeNotifier {
  ExtrasController({
    required ExtrasRepository repository,
    DateTime Function()? clock,
  }) : _repo = repository,
       _clock = clock ?? DateTime.now;

  final ExtrasRepository _repo;
  final DateTime Function() _clock;

  ExtrasStatus status = ExtrasStatus.loading;

  /// En el orden de la lista (RF-6).
  List<ExtraItem> items = const [];
  ExtrasTotals totals = const ExtrasTotals(0, 0);

  /// Un guardado ha fallado; se avisa en pantalla.
  bool saveFailed = false;

  bool _disposed = false;

  DateTime get today => _clock();

  Future<void> load() async {
    if (status != ExtrasStatus.ready) {
      status = ExtrasStatus.loading;
      _notify();
    }
    try {
      await _reload();
      status = ExtrasStatus.ready;
    } catch (_) {
      status = ExtrasStatus.error;
    }
    _notify();
  }

  Future<void> _reload() async {
    final all = await _repo.all();
    items = sortExtras(all);
    totals = ExtrasTotals.of(all);
  }

  /// Guarda un apunte nuevo o cambiado. Devuelve el guardado (con su id), o
  /// nulo si falló.
  Future<ExtraItem?> save(ExtraItem item) async {
    ExtraItem? saved;
    await _write(() async => saved = await _repo.save(item));
    return saved;
  }

  /// Borra [item]; con [restore] se puede deshacer (RF-5). Devuelve si se
  /// borró de verdad.
  Future<bool> delete(ExtraItem item) async {
    final id = item.id;
    if (id == null) return false;
    await _write(() => _repo.delete(id));
    return !saveFailed;
  }

  /// Vuelve a crear un apunte borrado, con su mismo id.
  Future<void> restore(ExtraItem item) => save(item);

  Future<void> _write(Future<void> Function() action) async {
    try {
      await action();
      saveFailed = false;
    } catch (_) {
      saveFailed = true; // sin datos personales en ningún registro
    }
    try {
      await _reload();
    } catch (_) {
      // Se conserva lo último que se vio.
    }
    _notify();
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
