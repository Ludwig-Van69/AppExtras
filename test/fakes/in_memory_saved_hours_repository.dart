import 'package:horas_y_vacaciones/data/saved_hours_repository.dart';
import 'package:horas_y_vacaciones/domain/saved_hours.dart';

/// Horas guardadas en memoria para los tests, con fallos simulables.
class InMemorySavedHoursRepository implements SavedHoursRepository {
  InMemorySavedHoursRepository([Iterable<SavedMove> initial = const []]) {
    for (final m in initial) {
      final id = m.id ?? _next++;
      if (id >= _next) _next = id + 1;
      byId[id] = savedMoveWithId(m, id);
    }
  }

  final byId = <int, SavedMove>{};
  int _next = 1;
  bool failWrites = false;

  @override
  Future<List<SavedMove>> all() async => byId.values.toList();

  @override
  Future<SavedMove> save(SavedMove move) async {
    if (failWrites) throw StateError('escritura simulada fallida');
    final id = move.id ?? _next++;
    final saved = savedMoveWithId(move, id);
    byId[id] = saved;
    return saved;
  }

  @override
  Future<void> delete(int id) async {
    if (failWrites) throw StateError('escritura simulada fallida');
    byId.remove(id);
  }
}
