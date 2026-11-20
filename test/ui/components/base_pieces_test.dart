import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horas_y_vacaciones/ui/components/app_nav_bar.dart';
import 'package:horas_y_vacaciones/ui/theme/app_colors.dart';

import '../test_app.dart';

/// Piezas base con datos inventados (RF-18).
Widget _pieces() => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    FilledButton(onPressed: () {}, child: const Text('Guardar copia')),
    OutlinedButton(onPressed: () {}, child: const Text('Elegir carpeta')),
    const TextField(decoration: InputDecoration(labelText: 'Motivo')),
    DropdownMenu<String>(
      label: const Text('Tipo de hora'),
      initialSelection: 'normal',
      dropdownMenuEntries: const [
        DropdownMenuEntry(value: 'normal', label: 'Normal'),
        DropdownMenuEntry(value: 'festiva', label: 'Festiva'),
      ],
    ),
    const Card(
      child: ListTile(
        title: Text('Octubre'),
        subtitle: Text('Papel entregado'),
        trailing: Text('270,00 €'),
      ),
    ),
  ],
);

void main() {
  for (final brightness in Brightness.values) {
    final c = brightness == Brightness.light ? AppColors.light : AppColors.dark;

    testWidgets('Piezas base en tema ${brightness.name} (RF-18)', (
      tester,
    ) async {
      await tester.pumpWidget(testApp(_pieces(), brightness: brightness));
      await tester.pumpAndSettle();

      for (final t in [
        'Guardar copia',
        'Elegir carpeta',
        'Motivo',
        'Tipo de hora',
        'Octubre',
        'Papel entregado',
        '270,00 €',
      ]) {
        expect(find.text(t), findsWidgets, reason: t);
      }

      final card = tester.widget<Material>(
        find
            .descendant(of: find.byType(Card), matching: find.byType(Material))
            .first,
      );
      expect(card.color, c.surface);

      for (final f in [
        find.byType(FilledButton),
        find.byType(OutlinedButton),
      ]) {
        expect(tester.getSize(f).height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('Navegación inferior en tema ${brightness.name}', (
      tester,
    ) async {
      var section = AppSection.log;
      await tester.pumpWidget(
        testApp(
          StatefulBuilder(
            builder: (context, setState) => AppNavBar(
              current: section,
              onChanged: (s) => setState(() => section = s),
            ),
          ),
          brightness: brightness,
        ),
      );
      for (final s in AppSection.values) {
        expect(find.text(s.label), findsOneWidget);
      }
      await tester.tap(find.text('Vacaciones'));
      await tester.pumpAndSettle();
      expect(section, AppSection.vacation);
      expect(tester.getSize(find.byType(NavigationBar)).height, 64);
    });
  }
}
