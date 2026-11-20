import 'package:flutter/material.dart';

import '../data/day_entry_repository.dart';
import 'backup/backup_controller.dart';
import 'components/app_nav_bar.dart';
import 'extras/extras_controller.dart';
import 'extras/extras_screen.dart';
import 'holidays/holidays_controller.dart';
import 'log/log_screen.dart';
import 'metrics/metrics_screen.dart';
import 'money/money_controller.dart';
import 'money/money_screen.dart';
import 'settings/settings_screen.dart';
import 'vacation/vacation_controller.dart';
import 'vacation/vacation_screen.dart';

/// Las secciones que existen ahora. Cada feature nueva añade la suya aquí
/// (Métricas fue la última, en la 014). Ajustes no es una sección: se abre con el
/// engranaje de la esquina de cada una (007, RF-16).
const _sections = [
  AppSection.log,
  AppSection.money,
  AppSection.vacation,
  AppSection.extra,
  AppSection.metrics,
];

/// La app con su barra de secciones abajo, al alcance del pulgar.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.repository,
    this.clock,
    this.backup,
    this.holidays,
    this.money,
    this.extras,
    this.vacation,
  });

  final DayEntryRepository repository;
  final DateTime Function()? clock;
  final BackupService? backup;
  final HolidaysController? holidays;
  final MoneyController? money;
  final ExtrasController? extras;
  final VacationController? vacation;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  AppSection _section = AppSection.log;
  final _saves = SaveWaiter();
  final _extraTab = ValueNotifier(ExtraTab.extras);
  late int _restoredSeen;

  @override
  void initState() {
    super.initState();
    _restoredSeen = widget.backup?.restoredCount ?? 0;
    widget.backup?.addListener(_backupChanged);
  }

  @override
  void dispose() {
    widget.backup?.removeListener(_backupChanged);
    _extraTab.dispose();
    super.dispose();
  }

  /// Tras restaurar una copia se vuelve a Apuntar, en el día de hoy.
  void _backupChanged() {
    final n = widget.backup!.restoredCount;
    if (n != _restoredSeen) {
      _restoredSeen = n;
      widget.money?.load();
      widget.extras?.load();
      widget.vacation?.load();
      // Ajustes y Copias se cierran: se vuelve a Apuntar, en el día de hoy.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      if (_section != AppSection.log) setState(() => _section = AppSection.log);
    }
  }

  void _openExtra(ExtraTab tab) {
    _extraTab.value = tab;
    setState(() => _section = AppSection.extra);
  }

  void _openSettings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(
        backup: widget.backup,
        holidays: widget.holidays,
        money: widget.money,
        vacation: widget.vacation,
        saves: _saves,
        clock: widget.clock,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final gear = SettingsButton(onPressed: _openSettings);
    final sections = [
      for (final s in _sections)
        if ((s != AppSection.money || widget.money != null) &&
            (s != AppSection.extra || widget.extras != null) &&
            (s != AppSection.vacation || widget.vacation != null) &&
            (s != AppSection.metrics || widget.money != null))
          s,
    ];
    return Scaffold(
      body: IndexedStack(
        index: _sections.indexOf(_section),
        children: [
          LogScreen(
            settingsButton: gear,
            repository: widget.repository,
            clock: widget.clock,
            backup: widget.backup,
            holidays: widget.holidays,
            saves: _saves,
            money: widget.money,
            vacation: widget.vacation,
            savedMoves: widget.money?.hasSavedHours ?? false
                ? widget.money!.readSavedMoves
                : null,
          ),
          if (widget.money != null)
            MoneyScreen(
              money: widget.money!,
              extras: widget.extras,
              onOpenExtras: () => _openExtra(ExtraTab.extras),
              vacation: widget.vacation,
              onOpenVacation: widget.vacation == null
                  ? null
                  : () => setState(() => _section = AppSection.vacation),
              onOpenSaved: widget.extras == null
                  ? null
                  : () => _openExtra(ExtraTab.saved),
              actions: [gear],
            )
          else
            const SizedBox.shrink(),
          if (widget.vacation != null)
            VacationScreen(vacation: widget.vacation!, actions: [gear])
          else
            const SizedBox.shrink(),
          if (widget.extras != null)
            ExtrasScreen(
              extras: widget.extras!,
              money: widget.money,
              tab: _extraTab,
              actions: [gear],
            )
          else
            const SizedBox.shrink(),
          if (widget.money != null)
            MetricsScreen(
              money: widget.money!,
              holidays: widget.holidays,
              vacation: widget.vacation,
              actions: [gear],
            )
          else
            const SizedBox.shrink(),
        ],
      ),
      // Con una sola sección no hace falta barra.
      bottomNavigationBar: sections.length < 2
          ? null
          : AppNavBar(
              sections: sections,
              current: _section,
              onChanged: (s) => setState(() => _section = s),
            ),
    );
  }
}
