import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/ui/app.dart';
import 'package:horas_y_vacaciones/ui/catalog/catalog_screen.dart';
import 'package:horas_y_vacaciones/ui/log/log_screen.dart';

import '../fakes/in_memory_day_entry_repository.dart';
import 'test_app.dart';

void main() {
  testWidgets('la app arranca en la pantalla de apuntar (RF-1)', (
    tester,
  ) async {
    calmAnimations(tester);
    await tester.pumpWidget(
      HoursAndVacationApp(
        repository: InMemoryDayEntryRepository(),
        clock: () => DateTime(2026, 11, 6, 18),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LogScreen), findsOneWidget);
    expect(find.byType(CatalogScreen), findsNothing);
  });
}
