import 'package:sqflite/sqflite.dart';

import '../domain/day_entry.dart';
import '../domain/extras.dart';

/// Dónde se guardan las multas y los extras (007).
abstract interface class ExtrasRepository {
  /// Todos, en cualquier orden.
  Future<List<ExtraItem>> all();

  /// Guarda [item] y lo devuelve con su id. Si ya tenía id, lo sustituye (o
  /// lo vuelve a crear con ese id, para Deshacer un borrado).
  Future<ExtraItem> save(ExtraItem item);

  /// Borra el apunte [id]; si no existe, no hace nada.
  Future<void> delete(int id);
}

/// La versión real, sobre SQLite.
class SqliteExtrasRepository implements ExtrasRepository {
  SqliteExtrasRepository(this._db);

  final Future<Database> Function() _db;

  @override
  Future<List<ExtraItem>> all() async {
    final rows = await (await _db()).query('extras', orderBy: 'id');
    return [for (final r in rows) extraFromRow(r)];
  }

  @override
  Future<ExtraItem> save(ExtraItem item) async {
    final id = await (await _db()).insert(
      'extras',
      extraToRow(item),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return item.copyWith(id: id);
  }

  @override
  Future<void> delete(int id) async =>
      (await _db()).delete('extras', where: 'id = ?', whereArgs: [id]);
}

/// Fila de la tabla `extras` (también la usan las copias).
Map<String, Object?> extraToRow(ExtraItem e) => {
  if (e.id != null) 'id': e.id,
  'kind': e.type.name,
  'date': dateKey(e.date),
  'cents': e.cents,
  'concept': e.concept,
  'status': e.status.name,
  'closed_on': e.closedOn == null ? null : dateKey(e.closedOn!),
  'early_payment': e.earlyPayment ? 1 : 0,
  'company_pays': e.companyPays ? 1 : 0,
};

/// Lo contrario de [extraToRow]. Da error si la fila no es válida.
ExtraItem extraFromRow(Map<String, Object?> r) => ExtraItem(
  id: r['id']! as int,
  type: ExtraType.values.byName(r['kind']! as String),
  date: parseDateKey(r['date']! as String),
  cents: r['cents']! as int,
  concept: r['concept']! as String,
  status: ExtraStatus.values.byName(r['status']! as String),
  closedOn: r['closed_on'] == null
      ? null
      : parseDateKey(r['closed_on']! as String),
  // Las copias anteriores a la v8 no tienen estas columnas (019, RF-6).
  earlyPayment: _flag(r['early_payment']),
  companyPays: _flag(r['company_pays']),
);

bool _flag(Object? v) => switch (v) {
  null || 0 => false,
  1 => true,
  _ => throw FormatException('Valor no válido', v),
};
