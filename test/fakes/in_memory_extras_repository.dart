import 'package:horas_y_vacaciones/data/extras_repository.dart';
import 'package:horas_y_vacaciones/domain/extras.dart';

/// Multas y extras en memoria para los tests, con fallos simulables.
class InMemoryExtrasRepository implements ExtrasRepository {
  InMemoryExtrasRepository([Iterable<ExtraItem> initial = const []]) {
    for (final e in initial) {
      final id = e.id ?? _next++;
      if (id >= _next) _next = id + 1;
      byId[id] = e.copyWith(id: id);
    }
  }

  final byId = <int, ExtraItem>{};
  int _next = 1;
  bool failWrites = false;

  @override
  Future<List<ExtraItem>> all() async => byId.values.toList();

  @override
  Future<ExtraItem> save(ExtraItem item) async {
    if (failWrites) throw StateError('escritura simulada fallida');
    final id = item.id ?? _next++;
    final saved = item.copyWith(id: id);
    byId[id] = saved;
    return saved;
  }

  @override
  Future<void> delete(int id) async {
    if (failWrites) throw StateError('escritura simulada fallida');
    byId.remove(id);
  }
}
