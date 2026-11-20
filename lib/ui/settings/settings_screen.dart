import 'package:flutter/material.dart';

import '../backup/backup_controller.dart';
import '../backup/backup_screen.dart';
import '../backup/backup_text.dart';
import '../help_screen.dart';
import '../holidays/holidays_controller.dart';
import '../holidays/holidays_screen.dart';
import '../money/money_controller.dart';
import '../money/rates_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/decor_colors.dart';
import '../theme/tokens.dart';
import '../vacation/vacation_controller.dart';
import '../vacation/vacation_settings_screen.dart';

/// Permite esperar a que la pantalla de apuntar termine de guardar, desde
/// otras pantallas (por ejemplo, antes de restaurar una copia).
class SaveWaiter {
  Future<void> Function()? _idle;

  /// La pantalla de apuntar dice cómo esperar sus guardados.
  void attach(Future<void> Function()? idle) => _idle = idle;

  Future<void> wait() async => _idle == null ? null : await _idle!();
}

/// Sección «Ajustes»: la puerta a copias, festivos, ayuda y catálogo.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    this.backup,
    this.holidays,
    this.money,
    this.vacation,
    this.saves,
    this.clock,
  });

  final BackupService? backup;
  final HolidaysController? holidays;
  final MoneyController? money;
  final VacationController? vacation;
  final SaveWaiter? saves;
  final DateTime Function()? clock;

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final backup = this.backup;
    final holidays = this.holidays;
    final money = this.money;
    final vacation = this.vacation;
    Widget tile(IconData icon, String title, String? subtitle, Widget screen) =>
        ListTile(
          contentPadding: EdgeInsets.zero,
          minVerticalPadding: Space.m,
          leading: Icon(icon, color: c.textSoft),
          title: Text(title, style: AppText.bodyStrong),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, screen),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.s,
          Space.gutter,
          Space.xxxl,
        ),
        children: [
          if (backup != null)
            ListenableBuilder(
              listenable: backup,
              builder: (context, _) {
                final s = backup.settings;
                final last = s.lastSuccess;
                final subtitle = s.folder == null
                    ? 'Aún sin carpeta'
                    : s.lastError != null
                    ? 'La última copia falló'
                    : last == null
                    ? 'Todavía ninguna copia'
                    : 'Última copia: '
                          '${backupMoment(last, now: (clock ?? DateTime.now)())}';
                return tile(
                  Icons.cloud_upload_outlined,
                  'Copias y exportación',
                  subtitle,
                  BackupScreen(
                    backup: backup,
                    waitForSaves: saves?.wait,
                    clock: clock,
                  ),
                );
              },
            ),
          if (money != null)
            tile(
              Icons.sell_outlined,
              'Tarifas',
              'Euros por hora, normales y festivas',
              RatesScreen(money: money),
            ),
          if (vacation != null)
            tile(
              Icons.beach_access_outlined,
              'Vacaciones',
              'Primer año y días de cada año',
              VacationSettingsScreen(vacation: vacation),
            ),
          if (holidays != null)
            tile(
              Icons.event_outlined,
              'Festivos',
              'Nacionales, regionales, locales y los tuyos',
              HolidaysScreen(holidays: holidays, clock: clock),
            ),
          const _ThemePicker(),
          tile(Icons.help_outline, 'Ayuda', null, const HelpScreen()),
        ],
      ),
    );
  }
}

/// «Aspecto»: Automático (sigue al móvil), Claro u Oscuro, al momento (009,
/// RF-9).
class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.contrast, color: c.textSoft),
              const SizedBox(width: Space.l),
              Text('Aspecto', style: AppText.bodyStrong),
            ],
          ),
          const SizedBox(height: Space.s),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeChoice>(
              showSelectedIcon: false,
              segments: [
                for (final t in ThemeChoice.values)
                  ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {theme.value},
              onSelectionChanged: (v) => theme.value = v.first,
            ),
          ),
          if (CalendarDecorScope.maybeOf(context) case final decor?)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Calendarios temáticos'),
              subtitle: const Text(
                'Dibujos de Navidad, Reyes, Carnaval y las estaciones',
              ),
              value: decor.value,
              onChanged: (v) => decor.value = v,
            ),
        ],
      ),
    );
  }
}
