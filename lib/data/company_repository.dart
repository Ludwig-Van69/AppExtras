import 'package:sqflite/sqflite.dart';

import '../domain/company.dart';
import '../domain/day_entry.dart';

/// Dónde se guarda la empresa (026).
abstract interface class CompanyRepository {
  /// La empresa; [Company.empty] si no hay nada apuntado.
  Future<Company> company();

  /// Sustituye la empresa por [c]; vacía la borra.
  Future<void> save(Company c);
}

/// La versión real, sobre SQLite.
class SqliteCompanyRepository implements CompanyRepository {
  SqliteCompanyRepository(this._db);

  final Future<Database> Function() _db;

  @override
  Future<Company> company() async => readCompany(await _db());

  @override
  Future<void> save(Company c) async =>
      (await _db()).transaction((txn) => writeCompany(txn, c));
}

/// La empresa guardada, validada; una fila imposible da error.
Future<Company> readCompany(DatabaseExecutor db) async {
  final rows = await db.query('company');
  if (rows.isEmpty) return Company.empty;
  final r = rows.single;
  final start = r['start_date'] as String?;
  return Company(
    name: r['name'] as String?,
    start: start == null ? null : parseDateKey(start),
  );
}

/// Sustituye la empresa por [c] (vacía, sin fila). Debe ir dentro de una
/// transacción.
Future<void> writeCompany(DatabaseExecutor db, Company c) async {
  await db.delete('company');
  if (c.isEmpty) return;
  final start = c.start;
  await db.insert('company', {
    'id': 1,
    'name': c.name,
    'start_date': start == null ? null : dateKey(start),
  });
}
