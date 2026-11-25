import 'package:horas_y_vacaciones/data/company_repository.dart';
import 'package:horas_y_vacaciones/domain/company.dart';

/// La empresa en memoria para los tests, con fallos simulables.
class InMemoryCompanyRepository implements CompanyRepository {
  InMemoryCompanyRepository([this.stored = Company.empty]);

  Company stored;
  bool failWrites = false;

  @override
  Future<Company> company() async => stored;

  @override
  Future<void> save(Company c) async {
    if (failWrites) throw StateError('escritura simulada fallida');
    stored = c;
  }
}
