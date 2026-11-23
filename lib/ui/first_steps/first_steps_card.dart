import 'package:flutter/material.dart';

import '../../domain/day_kind.dart';
import '../backup/backup_controller.dart';
import '../backup/backup_screen.dart';
import '../holidays/holidays_controller.dart';
import '../holidays/holidays_screen.dart';
import '../money/money_controller.dart';
import '../money/rates_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../vacation/vacation_controller.dart';
import '../vacation/vacation_settings_screen.dart';
import 'first_steps_controller.dart';

/// Un paso de la tarjeta: su texto, si está hecho y qué pantalla abre.
class _Step {
  const _Step(this.label, this.done, this.open);
  final String label;
  final bool done;
  final VoidCallback open;
}

/// Tarjeta «Primeros pasos» de arriba de Resumen (024). Solo lleva los pasos
/// cuya parte de la app existe; sin ninguno, no se ve.
class FirstStepsCard extends StatefulWidget {
  const FirstStepsCard({
    super.key,
    required this.steps,
    this.money,
    this.vacation,
    this.holidays,
    this.backup,
    this.waitForSaves,
    this.clock,
  });

  final FirstStepsController steps;
  final MoneyController? money;
  final VacationController? vacation;
  final HolidaysController? holidays;
  final BackupService? backup;
  final Future<void> Function()? waitForSaves;
  final DateTime Function()? clock;

  @override
  State<FirstStepsCard> createState() => _FirstStepsCardState();
}

class _FirstStepsCardState extends State<FirstStepsCard> {
  Future<void> _push(Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));

  List<_Step> _steps() {
    final money = widget.money;
    final vacation = widget.vacation;
    final holidays = widget.holidays;
    final backup = widget.backup;
    return [
      if (money != null)
        _Step(
          'Pon tus tarifas',
          money.rates.any((r) => r.kind == DayKind.normal), // RF-2
          () => _push(RatesScreen(money: money)),
        ),
      if (vacation != null)
        _Step(
          'Configura tus vacaciones',
          vacation.isConfigured, // RF-3
          () => _push(VacationSettingsScreen(vacation: vacation)),
        ),
      if (holidays != null)
        _Step(
          'Añade los festivos de tu zona',
          widget.steps.state.holidaysSeen, // RF-4
          () {
            widget.steps.markHolidaysSeen();
            _push(HolidaysScreen(holidays: holidays, clock: widget.clock));
          },
        ),
      if (backup != null)
        _Step(
          'Guarda una copia',
          backup.settings.folder != null ||
              backup.settings.lastShared != null, // RF-5
          () => _push(
            BackupScreen(
              backup: backup,
              waitForSaves: widget.waitForSaves,
              clock: widget.clock,
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.steps,
        ?widget.money,
        ?widget.vacation,
        ?widget.backup,
      ]),
      builder: (context, _) {
        final controller = widget.steps;
        if (!controller.loaded || controller.state.closed) {
          return const SizedBox.shrink();
        }
        final steps = _steps();
        if (steps.isEmpty) return const SizedBox.shrink();
        if (steps.every((s) => s.done)) {
          // RF-7: completa, se cierra para siempre.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            controller.close();
          });
          return const SizedBox.shrink();
        }
        final c = context.colors;
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.l),
          child: Material(
            key: const ValueKey('primeros-pasos'),
            color: c.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.medium),
              side: BorderSide(color: c.line),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.l,
                Space.s,
                Space.s,
                Space.s,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Primeros pasos',
                          style: AppText.bodyStrong,
                        ),
                      ),
                      TextButton(
                        onPressed: controller.close, // RF-8
                        child: const Text('Ocultar'),
                      ),
                    ],
                  ),
                  for (final s in steps)
                    ListTile(
                      contentPadding: const EdgeInsets.only(right: Space.s),
                      minVerticalPadding: 0,
                      minTileHeight: 48,
                      visualDensity: VisualDensity.compact,
                      leading: Icon(
                        s.done
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: s.done ? c.normal.strong : c.textSoft,
                        semanticLabel: s.done ? 'Hecho' : 'Pendiente',
                      ),
                      title: Text(
                        s.label,
                        style: AppText.body.copyWith(
                          color: s.done ? c.textSoft : c.text,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: s.open, // RF-6
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
