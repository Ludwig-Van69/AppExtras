import 'package:sqflite/sqflite.dart';

import '../domain/day_entry.dart';
import '../domain/saved_hours.dart';

/// Dónde se guardan los movimientos de las horas guardadas (008).
abstract interface class SavedHoursRepository {
  /// Todos, en cualquier orden.
  Future<List<SavedMove>> all();

  /// Guarda [move] y lo devuelve con su id. Si ya tenía id, lo sustituye (o
  /// lo vuelve a crear con ese id, para Deshacer un borrado).
  Future<SavedMove> save(SavedMove move);

  /// Borra el movimiento [id]; si no existe, no hace nada.
  Future<void> delete(int id);
}

/// La versión real, sobre SQLite.
class SqliteSavedHoursRepository implements SavedHoursRepository {
  SqliteSavedHoursRepository(this._db);

  final Future<Database> Function() _db;

  @override
  Future<List<SavedMove>> all() async {
    final rows = await (await _db()).query('saved_moves', orderBy: 'id');
    return [for (final r in rows) savedMoveFromRow(r)];
  }

  @override
  Future<SavedMove> save(SavedMove move) async {
    final id = await (await _db()).insert(
      'saved_moves',
      savedMoveToRow(move),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return savedMoveWithId(move, id);
  }

  @override
  Future<void> delete(int id) async =>
      (await _db()).delete('saved_moves', where: 'id = ?', whereArgs: [id]);
}

/// [move] con otro id.
SavedMove savedMoveWithId(SavedMove move, int id) => SavedMove(
  id: id,
  box: move.box,
  kind: move.kind,
  date: move.date,
  minutes: move.minutes,
  note: move.note,
  cents: move.cents,
  dayOff: move.dayOff,
);

/// Fila de la tabla `saved_moves` (también la usan las copias).
Map<String, Object?> savedMoveToRow(SavedMove m) => {
  if (m.id != null) 'id': m.id,
  'box': m.box?.name,
  'kind': m.kind.name,
  'date': dateKey(m.date),
  'minutes': m.minutes,
  'note': m.note,
  'cents': m.cents,
  'day_off': m.dayOff == null ? null : dateKey(m.dayOff!),
};

/// Lo contrario de [savedMoveToRow]. Da error si la fila no es válida.
SavedMove savedMoveFromRow(Map<String, Object?> r) => SavedMove(
  id: r['id']! as int,
  box: r['box'] == null ? null : SavedBox.values.byName(r['box']! as String),
  kind: SavedMoveKind.values.byName(r['kind']! as String),
  date: parseDateKey(r['date']! as String),
  minutes: r['minutes']! as int,
  note: r['note'] as String?,
  cents: r['cents'] as int?,
  dayOff: r['day_off'] == null ? null : parseDateKey(r['day_off']! as String),
);
