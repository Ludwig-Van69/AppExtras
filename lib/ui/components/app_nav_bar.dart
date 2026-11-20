import 'package:flutter/material.dart';

/// Secciones principales de la app.
enum AppSection {
  log('Apuntar', Icons.edit_calendar_outlined, Icons.edit_calendar),
  money('Resumen', Icons.payments_outlined, Icons.payments),
  vacation('Vacaciones', Icons.beach_access_outlined, Icons.beach_access),
  extra('Extra', Icons.receipt_long_outlined, Icons.receipt_long),
  metrics('Métricas', Icons.bar_chart_outlined, Icons.bar_chart);

  const AppSection(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Barra de navegación inferior, al alcance del pulgar.
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.current,
    required this.onChanged,
    this.sections = AppSection.values,
  });

  /// Las secciones que existen ahora, en orden.
  final List<AppSection> sections;
  final AppSection current;
  final ValueChanged<AppSection> onChanged;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: sections.indexOf(current),
      onDestinationSelected: (i) => onChanged(sections[i]),
      destinations: [
        for (final s in sections)
          NavigationDestination(
            icon: Icon(s.icon),
            selectedIcon: Icon(s.selectedIcon),
            label: s.label,
          ),
      ],
    );
  }
}

/// El engranaje de la esquina superior derecha que abre Ajustes (007, RF-16).
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Ajustes',
    icon: const Icon(Icons.settings_outlined),
    onPressed: onPressed,
  );
}
